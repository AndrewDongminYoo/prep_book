import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/library_backup/cubit/library_backup_cubit.dart';
import 'package:prep_book/presentation/library_backup/view/library_backup_platform.dart';

void main() {
  test('backup creates, saves, and succeeds in order', () async {
    final gateway = _RecordingGateway();
    final platform = _RecordingPlatform();
    final backup = LibraryBackupFile(
      bytes: Uint8List.fromList([1, 2]),
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
    expect(cubit.state.action, LibraryBackupAction.create);
    await subscription.cancel();
    await cubit.close();
  });

  test('backup save cancellation returns to neutral idle', () async {
    final gateway = _RecordingGateway();
    final platform = _RecordingPlatform()..saveResult = false;
    final cubit = _cubit(gateway, platform);

    await cubit.start(LibraryBackupAction.create);

    expect(cubit.state.status, LibraryBackupStatus.idle);
    expect(cubit.state.action, isNull);
    expect(cubit.state.failure, isNull);
    await cubit.close();
  });

  test('restore waits for confirmation and discards on cancel', () async {
    final gateway = _RecordingGateway();
    final platform = _RecordingPlatform()
      ..pickedBytes = Uint8List.fromList([3, 4]);
    final cubit = _cubit(gateway, platform);

    await cubit.start(LibraryBackupAction.restore);

    expect(cubit.state.status, LibraryBackupStatus.awaitingConfirmation);
    expect(cubit.state.pendingRestoreBytes, [3, 4]);
    expect(gateway.restored, isEmpty);

    cubit.cancelRestore();

    expect(cubit.state.status, LibraryBackupStatus.idle);
    expect(cubit.state.pendingRestoreBytes, isNull);
    expect(gateway.restored, isEmpty);
    await cubit.close();
  });

  test('confirmed restore emits restoring then success', () async {
    final gateway = _RecordingGateway();
    final platform = _RecordingPlatform()
      ..pickedBytes = Uint8List.fromList([5, 6]);
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
    expect(gateway.restored.single, [5, 6]);
    await subscription.cancel();
    await cubit.close();
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
    final platform = _RecordingPlatform()
      ..pickError = StateError('pick failed');
    final cubit = _cubit(_RecordingGateway(), platform);

    await cubit.start(LibraryBackupAction.restore);

    expect(cubit.state.status, LibraryBackupStatus.failed);
    expect(cubit.state.failure, LibraryBackupFailureKind.restoreFailed);
    await cubit.close();
  });

  test('restore preserves a typed failure category', () async {
    final failure = LibraryBackupException(
      LibraryBackupFailureKind.invalidDatabase,
      cause: StateError('candidate failed'),
      stackTrace: StackTrace.current,
    );
    final gateway = _RecordingGateway()..restoreError = failure;
    final platform = _RecordingPlatform()
      ..pickedBytes = Uint8List.fromList([7]);
    final cubit = _cubit(gateway, platform);
    await cubit.start(LibraryBackupAction.restore);

    await cubit.confirmRestore();

    expect(cubit.state.status, LibraryBackupStatus.failed);
    expect(cubit.state.failure, LibraryBackupFailureKind.invalidDatabase);
    await cubit.close();
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
        bytes: Uint8List.fromList([9]),
        suggestedName: 'backup.prepbook',
      ),
    );
    await first;
    await cubit.close();
  });

  test('closing during backup creation prevents the save picker', () async {
    final gateway = _RecordingGateway();
    final platform = _RecordingPlatform();
    final pending = Completer<LibraryBackupFile>();
    gateway.pendingCreate = pending.future;
    final cubit = _cubit(gateway, platform);

    final operation = cubit.start(LibraryBackupAction.create);
    await Future<void>.delayed(Duration.zero);
    await cubit.close();
    pending.complete(
      LibraryBackupFile(
        bytes: Uint8List.fromList([10]),
        suggestedName: 'backup.prepbook',
      ),
    );
    await operation;

    expect(platform.saved, isEmpty);
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
  final restored = <Uint8List>[];

  @override
  Future<LibraryBackupFile> create() async {
    createCalls++;
    final error = createError;
    if (error != null) throw error;
    final pending = pendingCreate;
    if (pending != null) return await pending;
    return createdBackup ??
        LibraryBackupFile(
          bytes: Uint8List.fromList([1]),
          suggestedName: 'backup.prepbook',
        );
  }

  @override
  Future<void> restore(Uint8List archiveBytes) async {
    restoreCalls++;
    final error = restoreError;
    if (error != null) throw error;
    restored.add(Uint8List.fromList(archiveBytes));
  }
}

final class _RecordingPlatform implements LibraryBackupPlatform {
  int pickCalls = 0;
  Uint8List? pickedBytes;
  Object? pickError;
  bool saveResult = true;
  final saved = <LibraryBackupFile>[];

  @override
  Future<Uint8List?> pickBackup() async {
    pickCalls++;
    final error = pickError;
    if (error != null) return await Future<Uint8List?>.error(error);
    return pickedBytes;
  }

  @override
  Future<bool> saveBackup(LibraryBackupFile backup) async {
    saved.add(backup);
    return saveResult;
  }
}
