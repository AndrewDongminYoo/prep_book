import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/persistence/persistence.dart';

void main() {
  test('create transfers encoded bytes and uses one instant', () async {
    var snapshotCalls = 0;
    var encodeCalls = 0;
    var clockCalls = 0;
    final databaseBytes = Uint8List.fromList([1, 2, 3]);
    final archiveBytes = Uint8List.fromList([4, 5]);
    final instant = DateTime(2026, 9, 13, 10, 11, 12);
    Uint8List? encodedDatabase;
    int? encodedSchema;
    DateTime? encodedCreatedAt;
    final gateway = DatabaseLibraryBackupGateway(
      createSnapshot: () async {
        snapshotCalls++;
        return databaseBytes;
      },
      encodeArchive:
          ({
            required databaseBytes,
            required databaseSchemaVersion,
            required createdAtUtc,
          }) {
            encodeCalls++;
            encodedDatabase = databaseBytes;
            encodedSchema = databaseSchemaVersion;
            encodedCreatedAt = createdAtUtc;
            return archiveBytes;
          },
      decodeArchive: (_) => throw UnimplementedError(),
      restoreDatabase: (_, {required manifestSchemaVersion}) => throw UnimplementedError(),
      now: () {
        clockCalls++;
        return instant;
      },
    );

    final backup = await gateway.create();

    expect(snapshotCalls, 1);
    expect(encodeCalls, 1);
    expect(clockCalls, 1);
    expect(encodedDatabase, databaseBytes);
    expect(encodedSchema, currentSchemaVersion);
    expect(encodedCreatedAt, instant.toUtc());
    expect(backup.bytes, archiveBytes);
    expect(backup.suggestedName, 'prepbook-backup-20260913-101112.prepbook');
    archiveBytes[0] = 9;
    expect(backup.bytes, [9, 5]);
  });

  test('restore rejects the outer limit before decoding', () async {
    var decodeCalls = 0;
    final gateway = _gateway(
      maxArchiveBytes: 3,
      decodeArchive: (_) {
        decodeCalls++;
        throw UnimplementedError();
      },
    );

    await expectLater(
      gateway.restore(Uint8List.fromList([1, 2, 3, 4])),
      throwsA(_failureKind(LibraryBackupFailureKind.backupTooLarge)),
    );

    expect(decodeCalls, 0);
  });

  test('restore decodes once and passes exact database metadata', () async {
    var decodeCalls = 0;
    var restoreCalls = 0;
    final archiveBytes = Uint8List.fromList([1, 2]);
    final databaseBytes = Uint8List.fromList([3, 4]);
    late Uint8List receivedBytes;
    late int receivedSchema;
    final gateway = _gateway(
      decodeArchive: (bytes) {
        decodeCalls++;
        expect(bytes, archiveBytes);
        return DecodedLibraryBackup(
          databaseBytes: databaseBytes,
          databaseSchemaVersion: 1,
          createdAtUtc: DateTime.utc(2026, 9, 13),
        );
      },
      restoreDatabase: (bytes, {required manifestSchemaVersion}) async {
        restoreCalls++;
        receivedBytes = bytes;
        receivedSchema = manifestSchemaVersion;
      },
    );

    await gateway.restore(archiveBytes);

    expect(decodeCalls, 1);
    expect(restoreCalls, 1);
    expect(receivedBytes, databaseBytes);
    expect(receivedSchema, 1);
  });

  test('preserves typed failures and maps diagnostic causes', () async {
    final typed = LibraryBackupException(
      LibraryBackupFailureKind.invalidArchive,
      cause: const FormatException('bad archive'),
      stackTrace: StackTrace.current,
    );
    final createCause = StateError('snapshot failed');
    final restoreCause = StateError('replacement failed');

    await expectLater(
      _gateway(createSnapshot: () async => throw typed).create(),
      throwsA(same(typed)),
    );
    await expectLater(
      _gateway(createSnapshot: () async => throw createCause).create(),
      throwsA(
        _failureWithCause(LibraryBackupFailureKind.saveFailed, createCause),
      ),
    );
    await expectLater(
      _gateway(
        decodeArchive: (_) => throw restoreCause,
      ).restore(Uint8List.fromList([1])),
      throwsA(
        _failureWithCause(LibraryBackupFailureKind.restoreFailed, restoreCause),
      ),
    );
  });

  test('one guard rejects overlap and clears for retry', () async {
    final snapshot = Completer<Uint8List>();
    var snapshotCalls = 0;
    var decodeCalls = 0;
    var restoreCalls = 0;
    final gateway = _gateway(
      createSnapshot: () {
        snapshotCalls++;
        return snapshot.future;
      },
      decodeArchive: (_) {
        decodeCalls++;
        return DecodedLibraryBackup(
          databaseBytes: Uint8List.fromList([2]),
          databaseSchemaVersion: 1,
          createdAtUtc: DateTime.utc(2026, 9, 13),
        );
      },
      restoreDatabase: (_, {required manifestSchemaVersion}) async {
        restoreCalls++;
      },
    );

    final creating = gateway.create();
    await expectLater(
      gateway.restore(Uint8List.fromList([1])),
      throwsA(_failureKind(LibraryBackupFailureKind.restoreFailed)),
    );
    expect(snapshotCalls, 1);
    expect(decodeCalls, 0);
    expect(restoreCalls, 0);

    snapshot.complete(Uint8List.fromList([9]));
    await creating;
    await gateway.restore(Uint8List.fromList([1]));

    expect(decodeCalls, 1);
    expect(restoreCalls, 1);
  });
}

DatabaseLibraryBackupGateway _gateway({
  int maxArchiveBytes = maxLibraryBackupBytes,
  CreateDatabaseSnapshot? createSnapshot,
  EncodeBackupArchive? encodeArchive,
  DecodeBackupArchive? decodeArchive,
  RestoreDatabaseSnapshot? restoreDatabase,
}) => DatabaseLibraryBackupGateway(
  maxArchiveBytes: maxArchiveBytes,
  createSnapshot: createSnapshot ?? () async => Uint8List.fromList(const [1, 2, 3]),
  encodeArchive:
      encodeArchive ??
      ({
        required databaseBytes,
        required databaseSchemaVersion,
        required createdAtUtc,
      }) => Uint8List.fromList(const [4, 5, 6]),
  decodeArchive:
      decodeArchive ??
      (_) => DecodedLibraryBackup(
        databaseBytes: Uint8List.fromList(const [7, 8, 9]),
        databaseSchemaVersion: 1,
        createdAtUtc: DateTime.utc(2026, 9, 13),
      ),
  restoreDatabase: restoreDatabase ?? (_, {required manifestSchemaVersion}) async {},
  now: () => DateTime(2026, 9, 13),
);

Matcher _failureKind(LibraryBackupFailureKind kind) =>
    isA<LibraryBackupException>().having((error) => error.kind, 'kind', kind);

Matcher _failureWithCause(LibraryBackupFailureKind kind, Object cause) => isA<LibraryBackupException>()
    .having((error) => error.kind, 'kind', kind)
    .having((error) => error.cause, 'cause', same(cause))
    .having((error) => error.stackTrace, 'stackTrace', isNotNull);
