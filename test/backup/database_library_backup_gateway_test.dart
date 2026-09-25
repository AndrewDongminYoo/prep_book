import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/persistence/persistence.dart';

import '../application/fakes.dart';

void main() {
  late _RecordingBackupFiles files;
  late Directory candidates;

  setUp(() async {
    files = _RecordingBackupFiles();
    candidates = await Directory.systemTemp.createTemp('prep-book-gateway-');
    _candidatePath = '${candidates.path}/candidate.db';
  });

  tearDown(() async {
    for (final directory in files.created) {
      await const IoBackupFiles().deleteDirectory(directory);
    }
    await candidates.delete(recursive: true);
  });

  test('create encodes a staged snapshot and uses one instant', () async {
    var clockCalls = 0;
    final instant = DateTime(2026, 9, 13, 10, 11, 12);
    String? snapshotPath;
    String? encodedDatabasePath;
    int? encodedSchema;
    DateTime? encodedCreatedAt;
    final gateway = _gateway(
      files: files,
      createSnapshot: (destinationPath) async {
        snapshotPath = destinationPath;
        await File(destinationPath).writeAsBytes([1, 2, 3]);
      },
      encodeArchive:
          ({
            required databasePath,
            required archivePath,
            required databaseSchemaVersion,
            required createdAtUtc,
          }) async {
            encodedDatabasePath = databasePath;
            encodedSchema = databaseSchemaVersion;
            encodedCreatedAt = createdAtUtc;
            expect(await File(databasePath).readAsBytes(), [1, 2, 3]);
            await File(archivePath).writeAsBytes([4, 5]);
          },
      now: () {
        clockCalls++;
        return instant;
      },
    );

    final backup = await gateway.create();

    expect(files.created, hasLength(1));
    expect(snapshotPath, startsWith(files.created.single));
    expect(encodedDatabasePath, snapshotPath);
    expect(encodedSchema, currentSchemaVersion);
    expect(encodedCreatedAt, instant.toUtc());
    expect(clockCalls, 1);
    expect(backup.suggestedName, 'prepbook-backup-20260913-101112.prepbook');
    expect(backup.archive.length, 2);
    expect(await _readAll(backup.archive), [4, 5]);
    expect(
      File(snapshotPath!).existsSync(),
      isFalse,
      reason: 'the snapshot is released once the archive holds it',
    );

    await backup.archive.discard();
    await backup.archive.discard();

    expect(Directory(files.created.single).existsSync(), isFalse);
    expect(files.deletedDirectories, [files.created.single]);
  });

  test('create removes its staging directory when a step fails', () async {
    final typed = LibraryBackupException(
      LibraryBackupFailureKind.invalidArchive,
      cause: const FormatException('bad archive'),
      stackTrace: StackTrace.current,
    );
    final snapshotCause = StateError('snapshot failed');
    final encodeCause = StateError('encode failed');

    await expectLater(
      _gateway(files: files, createSnapshot: (_) async => throw typed).create(),
      throwsA(same(typed)),
    );
    await expectLater(
      _gateway(files: files, createSnapshot: (_) async => throw snapshotCause).create(),
      throwsA(_failureWithCause(LibraryBackupFailureKind.saveFailed, snapshotCause)),
    );
    await expectLater(
      _gateway(
        files: files,
        encodeArchive: ({
          required databasePath,
          required archivePath,
          required databaseSchemaVersion,
          required createdAtUtc,
        }) async => throw encodeCause,
      ).create(),
      throwsA(_failureWithCause(LibraryBackupFailureKind.saveFailed, encodeCause)),
    );

    expect(files.created, hasLength(3));
    expect(files.created.where((path) => Directory(path).existsSync()), isEmpty);
  });

  test('create maps a failure to stage at all without cleanup', () async {
    const cause = FileSystemException('no temporary directory');
    files.createFailure = cause;

    await expectLater(
      _gateway(files: files).create(),
      throwsA(_failureWithCause(LibraryBackupFailureKind.saveFailed, cause)),
    );

    expect(files.deletedDirectories, isEmpty);
  });

  test('restore rejects the outer limit before reading or decoding', () async {
    var decodeCalls = 0;
    final archive = MemoryBackupArchive([1, 2, 3, 4]);
    final gateway = _gateway(
      files: files,
      maxArchiveBytes: 3,
      decodeArchive: ({required archivePath, required databasePath}) {
        decodeCalls++;
        throw UnimplementedError();
      },
    );

    await expectLater(
      gateway.restore(archive),
      throwsA(_failureKind(LibraryBackupFailureKind.backupTooLarge)),
    );

    expect(archive.readCount, 0);
    expect(files.created, isEmpty);
    expect(decodeCalls, 0);
  });

  test('restore decodes the staged archive into the session candidate', () async {
    var decodeCalls = 0;
    var restoreCalls = 0;
    final archive = MemoryBackupArchive([1, 2, 3, 4, 5], chunkSize: 2);
    final candidatePath = '${candidates.path}/candidate.db';
    late int stagedSchema;
    final gateway = _gateway(
      files: files,
      decodeArchive: ({required archivePath, required databasePath}) async {
        decodeCalls++;
        expect(archivePath, startsWith(files.created.single));
        expect(await File(archivePath).readAsBytes(), [1, 2, 3, 4, 5]);
        expect(databasePath, candidatePath);
        await File(databasePath).writeAsBytes([6, 7]);
        return DecodedLibraryBackup(
          databaseSchemaVersion: 1,
          createdAtUtc: DateTime.utc(2026, 9, 13),
        );
      },
      restoreDatabase: (stageCandidate) async {
        restoreCalls++;
        stagedSchema = await stageCandidate(candidatePath);
        expect(await File(candidatePath).readAsBytes(), [6, 7]);
      },
    );

    await gateway.restore(archive);

    expect(decodeCalls, 1);
    expect(restoreCalls, 1);
    expect(stagedSchema, 1);
    expect(archive.readCount, 1);
    expect(archive.discardCount, 0, reason: 'the caller still owns the archive');
    expect(Directory(files.created.single).existsSync(), isFalse);
  });

  test('restore bounds an archive that grows past the limit while read', () async {
    final gateway = _gateway(files: files, maxArchiveBytes: 3);

    await expectLater(
      gateway.restore(_MisreportedArchive(declaredLength: 2, bytes: [1, 2, 3, 4])),
      throwsA(_failureKind(LibraryBackupFailureKind.backupTooLarge)),
    );

    expect(Directory(files.created.single).existsSync(), isFalse);
  });

  test('restore rejects an archive whose length differs from its declaration', () async {
    var decodeCalls = 0;
    final gateway = _gateway(
      files: files,
      decodeArchive: ({required archivePath, required databasePath}) {
        decodeCalls++;
        throw UnimplementedError();
      },
    );

    await expectLater(
      gateway.restore(_MisreportedArchive(declaredLength: 4, bytes: [1, 2])),
      throwsA(_failureKind(LibraryBackupFailureKind.restoreFailed)),
    );

    expect(decodeCalls, 0);
    expect(Directory(files.created.single).existsSync(), isFalse);
  });

  test('restore preserves typed failures and maps diagnostic causes', () async {
    final typed = LibraryBackupException(
      LibraryBackupFailureKind.invalidArchive,
      cause: const FormatException('bad archive'),
      stackTrace: StackTrace.current,
    );
    final restoreCause = StateError('replacement failed');

    await expectLater(
      _gateway(
        files: files,
        decodeArchive: ({required archivePath, required databasePath}) async => throw typed,
      ).restore(MemoryBackupArchive([1])),
      throwsA(same(typed)),
    );
    await expectLater(
      _gateway(
        files: files,
        decodeArchive: ({required archivePath, required databasePath}) async => throw restoreCause,
      ).restore(MemoryBackupArchive([1])),
      throwsA(_failureWithCause(LibraryBackupFailureKind.restoreFailed, restoreCause)),
    );

    expect(files.created.where((path) => Directory(path).existsSync()), isEmpty);
  });

  test('a cleanup failure does not hide the outcome already reached', () async {
    files.deleteFailure = const FileSystemException('directory busy');
    var restoreCalls = 0;

    await _gateway(
      files: files,
      restoreDatabase: (stageCandidate) async => restoreCalls++,
    ).restore(MemoryBackupArchive([1]));
    final cause = StateError('snapshot failed');
    await expectLater(
      _gateway(files: files, createSnapshot: (_) async => throw cause).create(),
      throwsA(_failureWithCause(LibraryBackupFailureKind.saveFailed, cause)),
    );

    expect(restoreCalls, 1);
    expect(files.deletedDirectories, hasLength(2));
  });

  test('one guard rejects overlap and clears for retry', () async {
    final snapshot = Completer<void>();
    var snapshotCalls = 0;
    var decodeCalls = 0;
    var restoreCalls = 0;
    final gateway = _gateway(
      files: files,
      createSnapshot: (destinationPath) async {
        snapshotCalls++;
        await snapshot.future;
        await File(destinationPath).writeAsBytes([9]);
      },
      decodeArchive: ({required archivePath, required databasePath}) async {
        decodeCalls++;
        return DecodedLibraryBackup(
          databaseSchemaVersion: 1,
          createdAtUtc: DateTime.utc(2026, 9, 13),
        );
      },
      restoreDatabase: (stageCandidate) async {
        restoreCalls++;
        await stageCandidate('${candidates.path}/candidate.db');
      },
    );

    final creating = gateway.create();
    await expectLater(
      gateway.restore(MemoryBackupArchive([1])),
      throwsA(_failureKind(LibraryBackupFailureKind.restoreFailed)),
    );
    expect(decodeCalls, 0);
    expect(restoreCalls, 0);

    snapshot.complete();
    await (await creating).archive.discard();
    expect(snapshotCalls, 1);
    await gateway.restore(MemoryBackupArchive([1]));

    expect(decodeCalls, 1);
    expect(restoreCalls, 1);
  });
}

DatabaseLibraryBackupGateway _gateway({
  required BackupFiles files,
  int maxArchiveBytes = maxLibraryBackupBytes,
  CreateDatabaseSnapshot? createSnapshot,
  EncodeBackupArchive? encodeArchive,
  DecodeBackupArchive? decodeArchive,
  RestoreDatabaseSnapshot? restoreDatabase,
  DateTime Function()? now,
}) => DatabaseLibraryBackupGateway(
  maxArchiveBytes: maxArchiveBytes,
  files: files,
  createSnapshot: createSnapshot ?? (destinationPath) => File(destinationPath).writeAsBytes(const [1, 2, 3]),
  encodeArchive:
      encodeArchive ??
      ({
        required databasePath,
        required archivePath,
        required databaseSchemaVersion,
        required createdAtUtc,
      }) => File(archivePath).writeAsBytes(const [4, 5, 6]),
  decodeArchive:
      decodeArchive ??
      ({required archivePath, required databasePath}) async => DecodedLibraryBackup(
        databaseSchemaVersion: 1,
        createdAtUtc: DateTime.utc(2026, 9, 13),
      ),
  restoreDatabase: restoreDatabase ?? (stageCandidate) => stageCandidate(_candidatePath),
  now: now ?? () => DateTime(2026, 9, 13),
);

/// Where the default restore stages its candidate, inside the test's own
/// temporary directory.
late String _candidatePath;

Future<List<int>> _readAll(LibraryBackupArchive archive) async => [
  await for (final chunk in archive.openRead()) ...chunk,
];

/// An archive whose content does not match the length it declares.
final class _MisreportedArchive implements LibraryBackupArchive {
  new({required this.declaredLength, required this.bytes});

  final int declaredLength;
  final List<int> bytes;

  @override
  int get length => declaredLength;

  @override
  Stream<List<int>> openRead() => Stream.fromIterable([
    for (final byte in bytes) [byte],
  ]);

  @override
  Future<void> discard() async {}
}

/// Real file operations, recording every temporary directory created and
/// removed, with injectable failures for the two directory operations.
final class _RecordingBackupFiles implements BackupFiles {
  static const _delegate = IoBackupFiles();

  final created = <String>[];
  final deletedDirectories = <String>[];
  Exception? createFailure;
  Exception? deleteFailure;

  @override
  Future<String> createTemporaryDirectory(String prefix) async {
    final failure = createFailure;
    if (failure != null) throw failure;
    final path = await _delegate.createTemporaryDirectory(prefix);
    created.add(path);
    return path;
  }

  @override
  Future<void> deleteDirectory(String path) async {
    deletedDirectories.add(path);
    final failure = deleteFailure;
    if (failure != null) throw failure;
    await _delegate.deleteDirectory(path);
  }

  @override
  Future<int> length(String path) => _delegate.length(path);

  @override
  Future<int?> lengthIfExists(String path) => _delegate.lengthIfExists(path);

  @override
  Stream<List<int>> openRead(String path) => _delegate.openRead(path);

  @override
  Future<int> writeStream(String path, Stream<List<int>> content, {required bool flush}) =>
      _delegate.writeStream(path, content, flush: flush);

  @override
  Future<void> copy(String source, String destination, {required bool flush}) =>
      _delegate.copy(source, destination, flush: flush);

  @override
  Future<void> renameReplacing(String source, String destination) => _delegate.renameReplacing(source, destination);

  @override
  Future<void> deleteIfExists(String path) => _delegate.deleteIfExists(path);

  @override
  Future<void> deleteDatabaseSidecars(String databasePath) => _delegate.deleteDatabaseSidecars(databasePath);
}

Matcher _failureKind(LibraryBackupFailureKind kind) =>
    isA<LibraryBackupException>().having((error) => error.kind, 'kind', kind);

Matcher _failureWithCause(LibraryBackupFailureKind kind, Object cause) => isA<LibraryBackupException>()
    .having((error) => error.kind, 'kind', kind)
    .having((error) => error.cause, 'cause', same(cause))
    .having((error) => error.stackTrace, 'stackTrace', isNotNull);
