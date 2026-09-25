import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';

import 'fakes.dart';

void main() {
  test('create returns the gateway backup and leaves its archive to the caller', () async {
    final archive = MemoryBackupArchive([1, 2, 3]);
    final expected = LibraryBackupFile(
      archive: archive,
      suggestedName: 'prepbook-backup-20260913-120000.prepbook',
    );
    final gateway = _RecordingLibraryBackupGateway(createResult: expected);

    final actual = await CreateLibraryBackup(gateway)();

    expect(actual, same(expected));
    expect(actual.archive, same(archive));
    expect(archive.discardCount, 0);
    expect(gateway.createCalls, 1);
  });

  test('restore forwards the selected archive exactly once without discarding it', () async {
    final archive = MemoryBackupArchive([4, 5, 6]);
    final gateway = _RecordingLibraryBackupGateway();

    await RestoreLibraryBackup(gateway)(archive);

    expect(gateway.restoreCalls, 1);
    expect(gateway.restoredArchive, same(archive));
    expect(archive.discardCount, 0);
  });

  test('create preserves a typed failure and its diagnostics', () async {
    final cause = StateError('snapshot failed');
    final stackTrace = StackTrace.current;
    final failure = LibraryBackupException(
      LibraryBackupFailureKind.invalidDatabase,
      cause: cause,
      stackTrace: stackTrace,
    );
    final gateway = _RecordingLibraryBackupGateway(createError: failure);

    await expectLater(CreateLibraryBackup(gateway)(), throwsA(same(failure)));
    expect(failure.cause, same(cause));
    expect(failure.stackTrace, same(stackTrace));
  });

  test('restore preserves a typed failure and its diagnostics', () async {
    final cause = StateError('replacement failed');
    final stackTrace = StackTrace.current;
    final failure = LibraryBackupException(
      LibraryBackupFailureKind.restoreFailed,
      cause: cause,
      stackTrace: stackTrace,
    );
    final gateway = _RecordingLibraryBackupGateway(restoreError: failure);

    await expectLater(
      RestoreLibraryBackup(gateway)(MemoryBackupArchive(const [])),
      throwsA(same(failure)),
    );
    expect(failure.cause, same(cause));
    expect(failure.stackTrace, same(stackTrace));
  });
}

final class _RecordingLibraryBackupGateway implements LibraryBackupGateway {
  new({
    this.createResult,
    this.createError,
    this.restoreError,
  });

  final LibraryBackupFile? createResult;
  final LibraryBackupException? createError;
  final LibraryBackupException? restoreError;

  int createCalls = 0;
  int restoreCalls = 0;
  LibraryBackupArchive? restoredArchive;

  @override
  Future<LibraryBackupFile> create() async {
    createCalls++;
    final error = createError;
    if (error != null) throw error;
    return createResult!;
  }

  @override
  Future<void> restore(LibraryBackupArchive archive) async {
    restoreCalls++;
    restoredArchive = archive;
    final error = restoreError;
    if (error != null) throw error;
  }
}
