import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
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
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

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

/// Runs the flavor-independent setup, then the widget [builder] returns.
///
/// [builder] receives the three repositories rather than the open database
/// or a bare path, because that is what every current caller needs: the app
/// builds its use cases from them and the development entrypoint seeds
/// through them. Opening the database here rather than in an entrypoint is
/// what keeps the three flavors from each carrying a copy of that, and it
/// is what keeps `sqflite` out of them.
///
/// Everything that can fail before a widget tree exists is caught here and
/// answered with [StartupFailureApp]. `FlutterError.onError` does not cover
/// it: that handler is for errors the framework raises while building,
/// laying out or painting, and none of this has reached a frame yet. Left
/// uncaught, the exception escapes `main`, `runApp` is never called, and
/// the launch screen stays up with no message and no way out.
///
/// A call made while another run is still in flight joins that run instead
/// of starting a second one; see [_startupInFlight].
Future<void> bootstrap(
  FutureOr<Widget> Function(
    RecipeRepository recipes,
    IngredientRepository ingredients,
    ProductionRunRepository runs,
  )
  builder,
) {
  final inFlight = _startupInFlight;
  if (inFlight != null) return inFlight;

  final run = _runStartup(builder);
  _startupInFlight = run;
  return run.whenComplete(() {
    _startupInFlight = null;
  });
}

/// The startup sequence itself. Separate from [bootstrap] so the guard
/// there reads as one statement and cannot be skipped by an early return
/// inside the sequence.
Future<void> _runStartup(
  FutureOr<Widget> Function(
    RecipeRepository recipes,
    IngredientRepository ingredients,
    ProductionRunRepository runs,
  )
  builder,
) async {
  // Resolving the databases directory is a platform-channel call, so the
  // binding has to exist before it. `runApp` initializes it too, but that
  // is after the database is already open.
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  final Widget app;
  try {
    // Joined with a literal separator rather than through `package:path`,
    // which this project does not depend on directly. Both supported
    // platforms are POSIX.
    final databasesPath = await getDatabasesPath();
    final db = await openPrepBookDatabase(
      path: '$databasesPath/$_databaseFileName',
    );
    // Inside the guard as well as the open, because the development
    // entrypoint seeds here and a failed seed leaves the same blank
    // screen. `runApp` itself stays outside it: once a tree is mounted,
    // replacing it with a failure screen would be worse than the failure.
    app = await builder(
      SqfliteRecipeRepository(db),
      SqfliteIngredientRepository(db),
      SqfliteProductionRunRepository(db),
    );
  } on Object catch (error, stackTrace) {
    log('startup failed', error: error, stackTrace: stackTrace);
    runApp(
      StartupFailureApp(
        onRetry: () {
          // Whole sequence again, not just the open: the retry has to end
          // in a `runApp`, and this is the function that does one. Through
          // `bootstrap` rather than `_runStartup`, because that is where
          // the in-flight guard is and repeated taps arrive here.
          unawaited(bootstrap(builder));
        },
      ),
    );
    return;
  }

  runApp(app);
}
