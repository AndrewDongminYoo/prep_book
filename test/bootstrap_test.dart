import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/bootstrap.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    sqflite.databaseFactory = databaseFactoryFfi;
  });

  late Directory directory;
  late String databasePath;
  late _RecordingDatabaseFactory factory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prep-book-bootstrap-');
    databasePath = '${directory.path}/library.db';
    factory = _RecordingDatabaseFactory(databaseFactoryFfi);
  });

  tearDown(() async {
    if (await databaseFactoryFfi.databaseExists(databasePath)) {
      final db = await databaseFactoryFfi.openDatabase(databasePath);
      if (db.isOpen) await db.close();
    }
    await directory.delete(recursive: true);
  });

  test('SystemClock reads the current wall clock', () {
    final before = DateTime.now();

    final actual = const SystemClock().now();

    final after = DateTime.now();
    expect(actual.isBefore(before), isFalse);
    expect(actual.isAfter(after), isFalse);
  });

  test('AppBlocObserver forwards changes and errors', () async {
    const observer = AppBlocObserver();
    final bloc = _ObserverProbe();

    observer
      ..onChange(bloc, const Change(currentState: 0, nextState: 1))
      ..onError(bloc, StateError('probe'), StackTrace.current);

    await bloc.close();
  });

  test('uses the default factory and database path resolver', () async {
    final previousDatabasesPath = await databaseFactoryFfi.getDatabasesPath();
    await databaseFactoryFfi.setDatabasesPath(directory.path);
    addTearDown(
      () => databaseFactoryFfi.setDatabasesPath(previousDatabasesPath),
    );
    databasePath = '${directory.path}/prep_book.db';
    final mounts = <Widget>[];

    await bootstrap(
      builder:
          ({
            required recipes,
            required ingredients,
            required runs,
            required createLibraryBackup,
            required restoreLibraryBackup,
            required restored,
            required restoreFailure,
          }) => const SizedBox(),
      mount: mounts.add,
    );

    expect(await databaseFactoryFfi.databaseExists(databasePath), isTrue);
    expect(mounts, hasLength(1));
    FlutterError.onError!(
      FlutterErrorDetails(exception: StateError('handled framework error')),
    );
  });

  test('opens, prepares, builds, and mounts initial root once', () async {
    var prepareCalls = 0;
    var buildCalls = 0;
    final mounts = <Widget>[];

    await bootstrap(
      builder:
          ({
            required recipes,
            required ingredients,
            required runs,
            required createLibraryBackup,
            required restoreLibraryBackup,
            required restored,
            required restoreFailure,
          }) {
            buildCalls++;
            expect(restored, isFalse);
            expect(recipes, isA<SqfliteRecipeRepository>());
            expect(ingredients, isA<SqfliteIngredientRepository>());
            expect(runs, isA<SqfliteProductionRunRepository>());
            expect(createLibraryBackup, isA<CreateLibraryBackup>());
            expect(restoreLibraryBackup, isA<RestoreLibraryBackup>());
            return const SizedBox(key: ValueKey('initial'));
          },
      prepare: ({required recipes, required ingredients, required runs}) async {
        prepareCalls++;
      },
      resolveDatabasePath: () async => databasePath,
      factory: factory,
      mount: mounts.add,
    );

    expect(factory.openCalls, 1);
    expect(prepareCalls, 1);
    expect(buildCalls, 1);
    expect(mounts, hasLength(1));
    expect((mounts.single as SizedBox).key, const ValueKey('initial'));
  });

  test('the composed backup use case snapshots the live database', () async {
    final mounts = <Widget>[];
    CreateLibraryBackup? createBackup;

    await bootstrap(
      builder:
          ({
            required recipes,
            required ingredients,
            required runs,
            required createLibraryBackup,
            required restoreLibraryBackup,
            required restored,
            required restoreFailure,
          }) {
            createBackup = createLibraryBackup;
            return const SizedBox();
          },
      resolveDatabasePath: () async => databasePath,
      factory: factory,
      mount: mounts.add,
    );

    final backup = await createBackup!();
    final decoded = const BackupArchiveCodec().decode(backup.bytes);

    expect(decoded.databaseSchemaVersion, currentSchemaVersion);
    expect(decoded.databaseBytes, isNotEmpty);
    expect(mounts, hasLength(1));
  });

  test('concurrent startup calls join the first run', () async {
    final prepareStarted = Completer<void>();
    final releasePrepare = Completer<void>();
    var prepareCalls = 0;
    var buildCalls = 0;
    final mounts = <Widget>[];

    final first = bootstrap(
      builder:
          ({
            required recipes,
            required ingredients,
            required runs,
            required createLibraryBackup,
            required restoreLibraryBackup,
            required restored,
            required restoreFailure,
          }) {
            buildCalls++;
            return const SizedBox();
          },
      prepare: ({required recipes, required ingredients, required runs}) async {
        prepareCalls++;
        prepareStarted.complete();
        await releasePrepare.future;
      },
      resolveDatabasePath: () async => databasePath,
      factory: factory,
      mount: mounts.add,
    );
    await prepareStarted.future;

    final second = bootstrap(
      builder:
          ({
            required recipes,
            required ingredients,
            required runs,
            required createLibraryBackup,
            required restoreLibraryBackup,
            required restored,
            required restoreFailure,
          }) => throw StateError('the joined builder must not run'),
      resolveDatabasePath: () async => '${directory.path}/other.db',
      factory: factory,
      mount: (_) => throw StateError('the joined mount must not run'),
    );
    releasePrepare.complete();
    await Future.wait([first, second]);

    expect(factory.openCalls, 1);
    expect(prepareCalls, 1);
    expect(buildCalls, 1);
    expect(mounts, hasLength(1));
  });

  test('startup failure retry reruns the complete sequence', () async {
    var prepareCalls = 0;
    var buildCalls = 0;
    final mounts = <Widget>[];
    final retryMounted = Completer<void>();

    await bootstrap(
      builder:
          ({
            required recipes,
            required ingredients,
            required runs,
            required createLibraryBackup,
            required restoreLibraryBackup,
            required restored,
            required restoreFailure,
          }) {
            buildCalls++;
            return const SizedBox();
          },
      prepare: ({required recipes, required ingredients, required runs}) async {
        prepareCalls++;
        if (prepareCalls == 1) throw StateError('first prepare failed');
      },
      resolveDatabasePath: () async => databasePath,
      factory: factory,
      mount: (widget) {
        mounts.add(widget);
        if (widget is SizedBox && !retryMounted.isCompleted) {
          retryMounted.complete();
        }
      },
    );

    expect(mounts.single, isA<StartupFailureApp>());
    (mounts.single as StartupFailureApp).onRetry();
    await retryMounted.future;

    expect(factory.openCalls, 2);
    expect(prepareCalls, 2);
    expect(buildCalls, 1);
    expect(mounts.last, isA<SizedBox>());
  });

  test(
    'restore rebuilds repositories, skips prepare, and mounts fresh root',
    () async {
      var prepareCalls = 0;
      final repositorySets = <List<Object>>[];
      final restoredFlags = <bool>[];
      final mounts = <Widget>[];
      RestoreLibraryBackup? restoreOperation;
      final archive = await _backupArchive(
        '${directory.path}/source.db',
        ingredientId: 'restored',
      );

      await bootstrap(
        builder:
            ({
              required recipes,
              required ingredients,
              required runs,
              required createLibraryBackup,
              required restoreLibraryBackup,
              required restored,
              required restoreFailure,
            }) {
              restoreOperation = restoreLibraryBackup;
              repositorySets.add([recipes, ingredients, runs]);
              restoredFlags.add(restored);
              return SizedBox(key: ValueKey('root-${restoredFlags.length}'));
            },
        prepare:
            ({required recipes, required ingredients, required runs}) async {
              prepareCalls++;
              await ingredients.upsert(
                Ingredient(
                  id: 'previous',
                  name: 'Previous',
                  defaultUnit: Unit.gram,
                ),
              );
            },
        resolveDatabasePath: () async => databasePath,
        factory: factory,
        mount: mounts.add,
      );

      await restoreOperation!(archive);

      expect(prepareCalls, 1);
      expect(restoredFlags, [false, true]);
      expect(mounts, hasLength(2));
      expect(repositorySets, hasLength(2));
      for (var index = 0; index < 3; index++) {
        expect(repositorySets[1][index], isNot(same(repositorySets[0][index])));
      }
      final restoredIngredients =
          repositorySets.last[1] as IngredientRepository;
      expect((await restoredIngredients.listAll()).map((value) => value.id), [
        'restored',
      ]);
    },
  );

  testWidgets('restore replaces retained root state', (tester) async {
    final previousFlutterError = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previousFlutterError);
    final mounts = <Widget>[];
    RestoreLibraryBackup? restoreOperation;
    late Uint8List archive;
    await tester.runAsync(() async {
      archive = await _backupArchive(
        '${directory.path}/source.db',
        ingredientId: 'restored',
      );
      await bootstrap(
        builder:
            ({
              required recipes,
              required ingredients,
              required runs,
              required createLibraryBackup,
              required restoreLibraryBackup,
              required restored,
              required restoreFailure,
            }) {
              restoreOperation = restoreLibraryBackup;
              return _MountIdentityProbe(restored ? 'restored' : 'initial');
            },
        resolveDatabasePath: () async => databasePath,
        factory: factory,
        mount: mounts.add,
      );
    });
    FlutterError.onError = previousFlutterError;

    await tester.pumpWidget(mounts.single);
    expect(find.text('initial'), findsOneWidget);

    await tester.runAsync(() => restoreOperation!(archive));
    await tester.pumpWidget(mounts.last);

    expect(find.text('restored'), findsOneWidget);
    expect(find.text('initial'), findsNothing);
  });

  test('recovered restore remount carries its failure notice', () async {
    final failures = <LibraryBackupFailureKind?>[];
    final mounts = <Widget>[];
    RestoreLibraryBackup? restoreOperation;
    final archive = await _backupArchive(
      '${directory.path}/source.db',
      ingredientId: 'restored',
    );

    await bootstrap(
      builder:
          ({
            required recipes,
            required ingredients,
            required runs,
            required createLibraryBackup,
            required restoreLibraryBackup,
            required restored,
            required restoreFailure,
          }) {
            restoreOperation = restoreLibraryBackup;
            failures.add(restoreFailure);
            if (restored) throw StateError('replacement activation failed');
            return const SizedBox();
          },
      resolveDatabasePath: () async => databasePath,
      factory: factory,
      mount: mounts.add,
    );

    await expectLater(
      restoreOperation!(archive),
      throwsA(_failureKind(LibraryBackupFailureKind.restoreFailed)),
    );

    expect(failures, [null, null, LibraryBackupFailureKind.restoreFailed]);
    expect(mounts, hasLength(2));
  });

  test('unrecoverable restore mounts retryable startup failure', () async {
    var buildCalls = 0;
    final mounts = <Widget>[];
    RestoreLibraryBackup? restoreOperation;
    final archive = await _backupArchive(
      '${directory.path}/source.db',
      ingredientId: 'restored',
    );

    await bootstrap(
      builder:
          ({
            required recipes,
            required ingredients,
            required runs,
            required createLibraryBackup,
            required restoreLibraryBackup,
            required restored,
            required restoreFailure,
          }) {
            buildCalls++;
            restoreOperation = restoreLibraryBackup;
            if (buildCalls > 1) throw StateError('root rebuild failed');
            return const SizedBox();
          },
      resolveDatabasePath: () async => databasePath,
      factory: factory,
      mount: mounts.add,
    );

    await expectLater(
      restoreOperation!(archive),
      throwsA(_failureKind(LibraryBackupFailureKind.recoveryFailed)),
    );

    expect(buildCalls, 3);
    expect(mounts, hasLength(2));
    expect(mounts.last, isA<StartupFailureApp>());
    expect((mounts.last as StartupFailureApp).onRetry, isNotNull);
  });
}

final class _ObserverProbe extends BlocBase<int> {
  _ObserverProbe() : super(0);
}

final class _MountIdentityProbe extends StatefulWidget {
  const _MountIdentityProbe(this.label);

  final String label;

  @override
  State<_MountIdentityProbe> createState() => _MountIdentityProbeState();
}

final class _MountIdentityProbeState extends State<_MountIdentityProbe> {
  late final String label = widget.label;

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.ltr, child: Text(label));
}

Matcher _failureKind(LibraryBackupFailureKind kind) =>
    isA<LibraryBackupException>().having((error) => error.kind, 'kind', kind);

Future<Uint8List> _backupArchive(
  String sourcePath, {
  required String ingredientId,
}) async {
  final db = await openPrepBookDatabase(
    path: sourcePath,
    factory: databaseFactoryFfi,
    singleInstance: false,
  );
  await SqfliteIngredientRepository(db).upsert(
    Ingredient(id: ingredientId, name: ingredientId, defaultUnit: Unit.gram),
  );
  await db.close();
  final databaseBytes = await File(sourcePath).readAsBytes();
  return const BackupArchiveCodec().encode(
    databaseBytes: databaseBytes,
    databaseSchemaVersion: currentSchemaVersion,
    createdAtUtc: DateTime.utc(2026, 9, 13),
  );
}

final class _RecordingDatabaseFactory implements DatabaseFactory {
  _RecordingDatabaseFactory(this._delegate);

  final DatabaseFactory _delegate;
  int openCalls = 0;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    openCalls++;
    return _delegate.openDatabase(path, options: options);
  }

  @override
  Future<bool> databaseExists(String path) => _delegate.databaseExists(path);

  @override
  Future<void> deleteDatabase(String path) => _delegate.deleteDatabase(path);

  @override
  Future<String> getDatabasesPath() => _delegate.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) =>
      _delegate.setDatabasesPath(path);

  @override
  Future<Uint8List> readDatabaseBytes(String path) =>
      _delegate.readDatabaseBytes(path);

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) =>
      _delegate.writeDatabaseBytes(path, bytes);
}
