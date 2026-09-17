import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';

void main() {
  test('create returns an immutable snapshot of the gateway bytes', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final expected = LibraryBackupFile(
      bytes: bytes,
      suggestedName: 'prepbook-backup-20260913-120000.prepbook',
    );
    bytes[0] = 9;
    final gateway = _RecordingLibraryBackupGateway(createResult: expected);

    final actual = await CreateLibraryBackup(gateway)();

    expect(actual, same(expected));
    expect(() => actual.bytes[1] = 8, throwsUnsupportedError);
    expect(actual.bytes, [1, 2, 3]);
    expect(gateway.createCalls, 1);
  });

  test('restore forwards the selected archive bytes exactly once', () async {
    final bytes = Uint8List.fromList([4, 5, 6]);
    final gateway = _RecordingLibraryBackupGateway();

    await RestoreLibraryBackup(gateway)(bytes);

    expect(gateway.restoreCalls, 1);
    expect(gateway.restoredBytes, same(bytes));
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
      RestoreLibraryBackup(gateway)(Uint8List(0)),
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
  Uint8List? restoredBytes;

  @override
  Future<LibraryBackupFile> create() async {
    createCalls++;
    final error = createError;
    if (error != null) throw error;
    return createResult!;
  }

  @override
  Future<void> restore(Uint8List archiveBytes) async {
    restoreCalls++;
    restoredBytes = archiveBytes;
    final error = restoreError;
    if (error != null) throw error;
  }
}
