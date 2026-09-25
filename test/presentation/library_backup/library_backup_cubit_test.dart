import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/library_backup/cubit/library_backup_cubit.dart';
import 'package:prep_book/presentation/library_backup/view/library_backup_platform.dart';

import '../../application/fakes.dart';

void main() {
  test('backup creates, saves, succeeds, and then discards the archive', () async {
    final gateway = _RecordingGateway();
    final platform = _RecordingPlatform();
    final archive = MemoryBackupArchive([1, 2]);
    final backup = LibraryBackupFile(
      archive: archive,
      suggestedName: 'backup.prepbook',
    );
    gateway.createdBackup = backup;
    final cubit = _cubit(gateway, platform);
    final states = <LibraryBackupState>[];
    final subscription = cubit.stream.listen(states.add);

    await cubit.start(LibraryBackupAction.create);
    await Future<void>.delayed(Duration.zero);

    expect(states.map((state) => state.status), [
      LibraryBackupStatus.creating,
      LibraryBackupStatus.succeeded,
    ]);
    expect(gateway.createCalls, 1);
    expect(platform.saved, [backup]);
    expect(platform.discardsSeenBySave, [0]);
    expect(archive.discardCount, 1);
    expect(cubit.state.action, LibraryBackupAction.create);
    await subscription.cancel();
    await cubit.close();
    expect(archive.discardCount, 1);
  });

  test('backup save cancellation discards the archive and returns to idle', () async {
    final archive = MemoryBackupArchive([1]);
    final gateway = _RecordingGateway()
      ..createdBackup = LibraryBackupFile(
        archive: archive,
        suggestedName: 'backup.prepbook',
      );
    final platform = _RecordingPlatform()..saveResult = false;
    final cubit = _cubit(gateway, platform);

    await cubit.start(LibraryBackupAction.create);

    expect(cubit.state.status, LibraryBackupStatus.idle);
    expect(cubit.state.action, isNull);
    expect(cubit.state.failure, isNull);
    expect(archive.discardCount, 1);
    await cubit.close();
  });

  test('a failed save still discards the archive', () async {
    final archive = MemoryBackupArchive([1]);
    final gateway = _RecordingGateway()
      ..createdBackup = LibraryBackupFile(
        archive: archive,
        suggestedName: 'backup.prepbook',
      );
    final platform = _RecordingPlatform()..saveError = StateError('save failed');
    final cubit = _cubit(gateway, platform);

    await cubit.start(LibraryBackupAction.create);

    expect(cubit.state.status, LibraryBackupStatus.failed);
    expect(cubit.state.failure, LibraryBackupFailureKind.saveFailed);
    expect(archive.discardCount, 1);
    await cubit.close();
  });

  test('restore waits for confirmation and discards on cancel', () async {
    final gateway = _RecordingGateway();
    final archive = MemoryBackupArchive([3, 4]);
    final platform = _RecordingPlatform()..picked = archive;
    final cubit = _cubit(gateway, platform);

    await cubit.start(LibraryBackupAction.restore);

    expect(cubit.state.status, LibraryBackupStatus.awaitingConfirmation);
    expect(cubit.state.pendingRestore, same(archive));
    expect(archive.discardCount, 0);
    expect(gateway.restored, isEmpty);

    await cubit.cancelRestore();

    expect(cubit.state.status, LibraryBackupStatus.idle);
    expect(cubit.state.pendingRestore, isNull);
    expect(archive.discardCount, 1);
    expect(gateway.restored, isEmpty);
    await cubit.close();
    expect(archive.discardCount, 1);
  });

  test('cancel outside confirmation changes nothing', () async {
    final cubit = _cubit(_RecordingGateway(), _RecordingPlatform());

    await cubit.cancelRestore();

    expect(cubit.state, const LibraryBackupState());
    await cubit.close();
  });

  test('confirmed restore emits restoring then success and then discards', () async {
    final gateway = _RecordingGateway();
    final archive = MemoryBackupArchive([5, 6]);
    final platform = _RecordingPlatform()..picked = archive;
    final cubit = _cubit(gateway, platform);
    final statuses = <LibraryBackupStatus>[];
    final subscription = cubit.stream.listen(
      (state) => statuses.add(state.status),
    );
    await cubit.start(LibraryBackupAction.restore);

    await cubit.confirmRestore();
    await Future<void>.delayed(Duration.zero);

    expect(statuses, [
      LibraryBackupStatus.awaitingConfirmation,
      LibraryBackupStatus.restoring,
      LibraryBackupStatus.succeeded,
    ]);
    expect(gateway.restored.single, same(archive));
    expect(gateway.discardsSeenByRestore, [0]);
    expect(archive.discardCount, 1);
    expect(cubit.state.pendingRestore, isNull);
    await subscription.cancel();
    await cubit.close();
    expect(archive.discardCount, 1);
  });

  test('picker cancellation returns to neutral idle', () async {
    final cubit = _cubit(_RecordingGateway(), _RecordingPlatform());

    await cubit.start(LibraryBackupAction.restore);

    expect(cubit.state.status, LibraryBackupStatus.idle);
    expect(cubit.state.action, isNull);
    expect(cubit.state.failure, isNull);
    await cubit.close();
  });

  test('picker errors use the restore fallback category', () async {
    final platform = _RecordingPlatform()..pickError = StateError('pick failed');
    final cubit = _cubit(_RecordingGateway(), platform);

    await cubit.start(LibraryBackupAction.restore);

    expect(cubit.state.status, LibraryBackupStatus.failed);
    expect(cubit.state.failure, LibraryBackupFailureKind.restoreFailed);
    await cubit.close();
  });

  test('restore preserves a typed failure category and discards', () async {
    final failure = LibraryBackupException(
      LibraryBackupFailureKind.invalidDatabase,
      cause: StateError('candidate failed'),
      stackTrace: StackTrace.current,
    );
    final gateway = _RecordingGateway()..restoreError = failure;
    final archive = MemoryBackupArchive([7]);
    final platform = _RecordingPlatform()..picked = archive;
    final cubit = _cubit(gateway, platform);
    await cubit.start(LibraryBackupAction.restore);

    await cubit.confirmRestore();

    expect(cubit.state.status, LibraryBackupStatus.failed);
    expect(cubit.state.failure, LibraryBackupFailureKind.invalidDatabase);
    expect(archive.discardCount, 1);
    await cubit.close();
    expect(archive.discardCount, 1);
  });

  test('every typed failure becomes a localizable failed state', () async {
    for (final kind in LibraryBackupFailureKind.values) {
      final gateway = _RecordingGateway()
        ..createError = LibraryBackupException(
          kind,
          cause: StateError('$kind'),
          stackTrace: StackTrace.current,
        );
      final cubit = _cubit(gateway, _RecordingPlatform());

      await cubit.start(LibraryBackupAction.create);

      expect(cubit.state.status, LibraryBackupStatus.failed);
      expect(cubit.state.failure, kind);
      await cubit.close();
    }
  });

  test('repeated actions while busy invoke no second dependency', () async {
    final gateway = _RecordingGateway();
    final platform = _RecordingPlatform();
    final pending = Completer<LibraryBackupFile>();
    gateway.pendingCreate = pending.future;
    final cubit = _cubit(gateway, platform);

    final first = cubit.start(LibraryBackupAction.create);
    await Future<void>.delayed(Duration.zero);
    await cubit.start(LibraryBackupAction.create);
    await cubit.start(LibraryBackupAction.restore);

    expect(gateway.createCalls, 1);
    expect(platform.pickCalls, 0);
    pending.complete(
      LibraryBackupFile(
        archive: MemoryBackupArchive([9]),
        suggestedName: 'backup.prepbook',
      ),
    );
    await first;
    await cubit.close();
  });

  test('closing during backup creation prevents the save picker and discards', () async {
    final gateway = _RecordingGateway();
    final platform = _RecordingPlatform();
    final pending = Completer<LibraryBackupFile>();
    gateway.pendingCreate = pending.future;
    final cubit = _cubit(gateway, platform);
    final archive = MemoryBackupArchive([10]);

    final operation = cubit.start(LibraryBackupAction.create);
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    pending.complete(
      LibraryBackupFile(archive: archive, suggestedName: 'backup.prepbook'),
    );
    await operation;

    expect(platform.saved, isEmpty);
    expect(archive.discardCount, 1);
  });

  test('closing while a restore awaits confirmation discards it', () async {
    final gateway = _RecordingGateway();
    final archive = MemoryBackupArchive([11]);
    final cubit = _cubit(gateway, _RecordingPlatform()..picked = archive);
    await cubit.start(LibraryBackupAction.restore);

    await cubit.close();

    expect(archive.discardCount, 1);
    expect(gateway.restored, isEmpty);
  });

  test('a pick that lands after close is discarded, not held', () async {
    final pending = Completer<LibraryBackupArchive?>();
    final platform = _RecordingPlatform()..pendingPick = pending.future;
    final cubit = _cubit(_RecordingGateway(), platform);
    final archive = MemoryBackupArchive([12]);

    final operation = cubit.start(LibraryBackupAction.restore);
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    pending.complete(archive);
    await operation;

    expect(archive.discardCount, 1);
  });

  group('a discard that fails is reported without changing the outcome', () {
    late _ErrorRecordingObserver observer;
    final discardError = StateError('temporary directory busy');

    setUp(() {
      final previous = Bloc.observer;
      observer = _ErrorRecordingObserver();
      Bloc.observer = observer;
      addTearDown(() => Bloc.observer = previous);
    });

    test('after a completed save', () async {
      final archive = MemoryBackupArchive([1], discardError: discardError);
      final gateway = _RecordingGateway()
        ..createdBackup = LibraryBackupFile(
          archive: archive,
          suggestedName: 'backup.prepbook',
        );
      final cubit = _cubit(gateway, _RecordingPlatform());

      await cubit.start(LibraryBackupAction.create);

      expect(cubit.state.status, LibraryBackupStatus.succeeded);
      expect(cubit.state.failure, isNull);
      expect(observer.errors, [same(discardError)]);
      await cubit.close();
    });

    test('after a completed restore', () async {
      final gateway = _RecordingGateway();
      final archive = MemoryBackupArchive([2], discardError: discardError);
      final cubit = _cubit(gateway, _RecordingPlatform()..picked = archive);
      await cubit.start(LibraryBackupAction.restore);

      await cubit.confirmRestore();

      expect(gateway.restored.single, same(archive));
      expect(cubit.state.status, LibraryBackupStatus.succeeded);
      expect(cubit.state.failure, isNull);
      expect(observer.errors, [same(discardError)]);
      await cubit.close();
    });

    test('after a cancelled restore', () async {
      final archive = MemoryBackupArchive([3], discardError: discardError);
      final cubit = _cubit(
        _RecordingGateway(),
        _RecordingPlatform()..picked = archive,
      );
      await cubit.start(LibraryBackupAction.restore);

      await cubit.cancelRestore();

      expect(cubit.state.status, LibraryBackupStatus.idle);
      expect(observer.errors, [same(discardError)]);
      await cubit.close();
    });

    test('when the dialog closes over a pending restore', () async {
      final archive = MemoryBackupArchive([4], discardError: discardError);
      final cubit = _cubit(
        _RecordingGateway(),
        _RecordingPlatform()..picked = archive,
      );
      await cubit.start(LibraryBackupAction.restore);

      await cubit.close();

      expect(archive.discardCount, 1);
      expect(observer.errors, [same(discardError)]);
    });

    test('when a pick lands after the dialog closed', () async {
      final pending = Completer<LibraryBackupArchive?>();
      final cubit = _cubit(
        _RecordingGateway(),
        _RecordingPlatform()..pendingPick = pending.future,
      );
      final archive = MemoryBackupArchive([5], discardError: discardError);

      final operation = cubit.start(LibraryBackupAction.restore);
      await Future<void>.delayed(Duration.zero);
      await cubit.close();
      pending.complete(archive);
      await operation;

      expect(archive.discardCount, 1);
      expect(observer.errors, [same(discardError)]);
    });
  });

  test('a cancelled pick that lands after close emits nothing', () async {
    final pending = Completer<LibraryBackupArchive?>();
    final platform = _RecordingPlatform()..pendingPick = pending.future;
    final cubit = _cubit(_RecordingGateway(), platform);

    final operation = cubit.start(LibraryBackupAction.restore);
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    pending.complete();
    await operation;

    expect(cubit.state.status, LibraryBackupStatus.idle);
  });
}

LibraryBackupCubit _cubit(
  _RecordingGateway gateway,
  _RecordingPlatform platform,
) => LibraryBackupCubit(
  createBackup: CreateLibraryBackup(gateway),
  restoreBackup: RestoreLibraryBackup(gateway),
  platform: platform,
);

final class _RecordingGateway implements LibraryBackupGateway {
  int createCalls = 0;
  int restoreCalls = 0;
  LibraryBackupFile? createdBackup;
  Future<LibraryBackupFile>? pendingCreate;
  LibraryBackupException? createError;
  LibraryBackupException? restoreError;
  final restored = <LibraryBackupArchive>[];
  final discardsSeenByRestore = <int>[];

  @override
  Future<LibraryBackupFile> create() async {
    createCalls++;
    final error = createError;
    if (error != null) throw error;
    final pending = pendingCreate;
    if (pending != null) return await pending;
    return createdBackup ??
        LibraryBackupFile(
          archive: MemoryBackupArchive([1]),
          suggestedName: 'backup.prepbook',
        );
  }

  @override
  Future<void> restore(LibraryBackupArchive archive) async {
    restoreCalls++;
    if (archive is MemoryBackupArchive) {
      discardsSeenByRestore.add(archive.discardCount);
    }
    final error = restoreError;
    if (error != null) throw error;
    restored.add(archive);
  }
}

final class _RecordingPlatform implements LibraryBackupPlatform {
  int pickCalls = 0;
  LibraryBackupArchive? picked;
  Future<LibraryBackupArchive?>? pendingPick;
  Object? pickError;
  bool saveResult = true;
  Error? saveError;
  final saved = <LibraryBackupFile>[];
  final discardsSeenBySave = <int>[];

  @override
  Future<LibraryBackupArchive?> pickBackup() async {
    pickCalls++;
    final error = pickError;
    if (error != null) return await Future<LibraryBackupArchive?>.error(error);
    final pending = pendingPick;
    if (pending != null) return await pending;
    return picked;
  }

  @override
  Future<bool> saveBackup(LibraryBackupFile backup) async {
    saved.add(backup);
    final archive = backup.archive;
    if (archive is MemoryBackupArchive) {
      discardsSeenBySave.add(archive.discardCount);
    }
    final error = saveError;
    if (error != null) throw error;
    return saveResult;
  }
}

final class _ErrorRecordingObserver extends BlocObserver {
  final errors = <Object>[];

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    errors.add(error);
    super.onError(bloc, error, stackTrace);
  }
}
