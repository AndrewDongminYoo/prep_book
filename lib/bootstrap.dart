import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite/sqflite.dart';

/// The file the application's SQLite database lives in, under the
/// platform's databases directory.
const _databaseFileName = 'prep_book.db';

/// The platform clock, which is what every use case needing "now" is bound
/// to outside a test.
///
/// Lives here because this is the composition root: a test binds its own
/// fixed clock, and nothing else in `lib/` should be reading the wall clock
/// on its own.
final class SystemClock implements Clock {
  /// Creates the clock.
  const new();

  @override
  DateTime now() => DateTime.now();
}

class AppBlocObserver extends BlocObserver {
  const new();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    super.onError(bloc, error, stackTrace);
  }
}

/// The startup run currently in flight, or `null` between runs.
///
/// [StartupFailureApp] renders its retry as an always-enabled button, so
/// two rapid taps would otherwise start two overlapping runs. In the
/// development flavor both would read an empty library and both would seed
/// it, and the loser would throw on the primary key the winner had just
/// written — remounting the failure screen over a database that opened
/// fine. Cleared when the run settles, either way, rather than latched: a
/// run that failed has to leave the next retry able to start, so a flag
/// that is only ever set would kill the retry button instead of guarding
/// it.
Future<void>? _startupInFlight;

/// Builds one application root from active repositories and backup use cases.
typedef PrepBookAppBuilder = FutureOr<Widget> Function({
  required RecipeRepository recipes,
  required IngredientRepository ingredients,
  required ProductionRunRepository runs,
  required CreateLibraryBackup createLibraryBackup,
  required RestoreLibraryBackup restoreLibraryBackup,
  required bool restored,
  required LibraryBackupFailureKind? restoreFailure,
});

/// Performs flavor-specific database preparation during initial startup only.
typedef PrepareDatabase = FutureOr<void> Function({
  required RecipeRepository recipes,
  required IngredientRepository ingredients,
  required ProductionRunRepository runs,
});

/// Resolves the live SQLite file used by one startup attempt.
typedef ResolveDatabasePath = Future<String> Function();

/// Mounts one complete application root.
typedef MountRoot = void Function(Widget widget);

/// Opens the database and mounts a rebuildable application root.
///
/// A call made while another startup run is in flight joins that run.
Future<void> bootstrap({
  required PrepBookAppBuilder builder,
  PrepareDatabase? prepare,
  ResolveDatabasePath? resolveDatabasePath,
  DatabaseFactory? factory,
  MountRoot? mount,
}) {
  final inFlight = _startupInFlight;
  if (inFlight != null) return inFlight;

  final activeFactory = factory ?? databaseFactory;
  final pathResolver =
      resolveDatabasePath ?? () async => '${await activeFactory.getDatabasesPath()}/$_databaseFileName';
  final rootMount = mount ?? runApp;
  late final VoidCallback retry;
  retry = () {
    unawaited(
      bootstrap(
        builder: builder,
        prepare: prepare,
        resolveDatabasePath: resolveDatabasePath,
        factory: factory,
        mount: mount,
      ),
    );
  };
  final run = _runStartup(
    builder: builder,
    prepare: prepare,
    resolveDatabasePath: pathResolver,
    factory: activeFactory,
    mount: rootMount,
    retry: retry,
  );
  _startupInFlight = run;
  return run.whenComplete(() {
    _startupInFlight = null;
  });
}

Future<void> _runStartup({
  required PrepBookAppBuilder builder,
  required PrepareDatabase? prepare,
  required ResolveDatabasePath resolveDatabasePath,
  required DatabaseFactory factory,
  required MountRoot mount,
  required VoidCallback retry,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  Database? initialConnection;
  try {
    final databasePath = await resolveDatabasePath();
    initialConnection = await openPrepBookDatabase(
      path: databasePath,
      factory: factory,
    );
    const files = IoBackupFiles();
    final validator = BackupDatabaseValidator(factory: factory);
    const codec = BackupArchiveCodec();
    late DatabaseSession session;
    late final DatabaseLibraryBackupGateway gateway;
    var hasMountedRoot = false;

    Future<void> buildAndMount(
      ({
        RecipeRepository recipes,
        IngredientRepository ingredients,
        ProductionRunRepository runs,
      })
      repositories, {
      required bool restored,
      required LibraryBackupFailureKind? restoreFailure,
    }) async {
      final root = await builder(
        recipes: repositories.recipes,
        ingredients: repositories.ingredients,
        runs: repositories.runs,
        createLibraryBackup: CreateLibraryBackup(gateway),
        restoreLibraryBackup: RestoreLibraryBackup(gateway),
        restored: restored,
        restoreFailure: restoreFailure,
      );
      final mountedRoot = hasMountedRoot ? KeyedSubtree(key: UniqueKey(), child: root) : root;
      hasMountedRoot = true;
      mount(mountedRoot);
    }

    Future<void> activate(Database connection, {required bool restored}) => buildAndMount(
      _repositories(connection),
      restored: restored,
      restoreFailure: restored ? null : LibraryBackupFailureKind.restoreFailed,
    );

    void mountFailure() {
      mount(StartupFailureApp(onRetry: retry));
    }

    session = DatabaseSession(
      connection: initialConnection,
      databasePath: databasePath,
      factory: factory,
      files: files,
      validateCandidate: validator.validate,
      activate: activate,
      mountRecoveryFailure: mountFailure,
    );
    gateway = DatabaseLibraryBackupGateway(
      createSnapshot: () => DatabaseSnapshotter(
        connection: session.connection,
        databasePath: databasePath,
        factory: factory,
        files: files,
        validateCandidate: validator.validate,
      ).create(),
      encodeArchive: codec.encode,
      decodeArchive: codec.decode,
      restoreDatabase: session.restore,
      now: DateTime.now,
    );
    final repositories = _repositories(initialConnection);
    await prepare?.call(
      recipes: repositories.recipes,
      ingredients: repositories.ingredients,
      runs: repositories.runs,
    );
    await buildAndMount(repositories, restored: false, restoreFailure: null);
  } on Object catch (error, stackTrace) {
    if (initialConnection?.isOpen ?? false) {
      try {
        await initialConnection!.close();
      } on Object catch (closeError, closeStackTrace) {
        log(
          'startup database close failed',
          error: closeError,
          stackTrace: closeStackTrace,
        );
      }
    }
    log('startup failed', error: error, stackTrace: stackTrace);
    mount(StartupFailureApp(onRetry: retry));
  }
}

({
  RecipeRepository recipes,
  IngredientRepository ingredients,
  ProductionRunRepository runs,
})
_repositories(Database db) => (
  recipes: SqfliteRecipeRepository(db),
  ingredients: SqfliteIngredientRepository(db),
  runs: SqfliteProductionRunRepository(db),
);
