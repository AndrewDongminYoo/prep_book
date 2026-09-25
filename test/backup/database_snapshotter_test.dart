import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late String databasePath;
  late String candidatePath;
  late String snapshotPath;
  late Database db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prep-book-snapshot-');
    databasePath = '${directory.path}/library.db';
    candidatePath = '${directory.path}/candidate.db';
    snapshotPath = '${directory.path}/snapshot.db';
    db = await openPrepBookDatabase(
      path: databasePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'captures WAL data while an owned-connection write stays queued',
    () async {
      await db.rawQuery('PRAGMA journal_mode = WAL');
      final ingredients = SqfliteIngredientRepository(db);
      await ingredients.upsert(
        Ingredient(id: 'before', name: 'Before', defaultUnit: Unit.gram),
      );
      expect(await File('$databasePath-wal').length(), greaterThan(0));

      late Future<int> queuedWrite;
      final files = _CopyHookBackupFiles(
        onCopy: (source) async {
          if (source != databasePath) return;
          var writeCompleted = false;
          queuedWrite = db
              .insert('ingredients', {
                'id': 'during',
                'name': 'During',
                'default_unit': 'g',
              })
              .whenComplete(() => writeCompleted = true);
          await Future<void>.delayed(Duration.zero);
          expect(
            writeCompleted,
            isFalse,
            reason: 'the file copy must run while the connection is locked',
          );
        },
      );
      final validator = BackupDatabaseValidator(factory: databaseFactoryFfi);
      final snapshotter = DatabaseSnapshotter(
        connection: db,
        databasePath: databasePath,
        files: files,
        validateCandidate: validator.validate,
        createCandidatePath: () => candidatePath,
      );

      await snapshotter.create(destinationPath: snapshotPath);
      await queuedWrite;

      final captured = await openPrepBookDatabase(
        path: snapshotPath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      addTearDown(captured.close);
      final capturedIds = (await captured.query(
        'ingredients',
      )).map((row) => row['id']).toList();
      final liveIds = (await db.query(
        'ingredients',
      )).map((row) => row['id']).toList();
      expect(capturedIds, ['before']);
      expect(liveIds, containsAll(['before', 'during']));
      expect(db.isOpen, isTrue);
      expect(File(candidatePath).existsSync(), isFalse);
    },
  );

  test('validates a separate, identical copy of the snapshot', () async {
    await _storeIngredient(db, 'kept');
    Uint8List? validatedBytes;
    final snapshotter = DatabaseSnapshotter(
      connection: db,
      databasePath: databasePath,
      files: const IoBackupFiles(),
      validateCandidate: ({required candidatePath, required manifestSchemaVersion}) async {
        expect(candidatePath, isNot(snapshotPath));
        validatedBytes = await File(candidatePath).readAsBytes();
      },
      createCandidatePath: () => candidatePath,
    );

    await snapshotter.create(destinationPath: snapshotPath);

    expect(await File(snapshotPath).readAsBytes(), validatedBytes);
    expect(File(candidatePath).existsSync(), isFalse);
  });

  test('retries when a write commits after the checkpoint', () async {
    await db.rawQuery('PRAGMA journal_mode = WAL');
    await _storeIngredient(db, 'before');
    var checkpointCalls = 0;
    final connection = _CheckpointHookDatabase(
      db,
      afterCheckpoint: () async {
        checkpointCalls++;
        if (checkpointCalls == 1) {
          await _storeIngredient(db, 'during');
        }
      },
    );
    final validator = BackupDatabaseValidator(factory: databaseFactoryFfi);
    final snapshotter = DatabaseSnapshotter(
      connection: connection,
      databasePath: databasePath,
      files: const IoBackupFiles(),
      validateCandidate: validator.validate,
      createCandidatePath: () => candidatePath,
    );

    await snapshotter.create(destinationPath: snapshotPath);

    final captured = await openPrepBookDatabase(
      path: snapshotPath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    addTearDown(captured.close);
    expect(await _ingredientIds(captured), ['before', 'during']);
    expect(checkpointCalls, 2);
  });

  test(
    'validation failure keeps live open and removes the candidate and snapshot',
    () async {
      final failure = LibraryBackupException(
        LibraryBackupFailureKind.invalidDatabase,
        cause: StateError('candidate rejected'),
        stackTrace: StackTrace.current,
      );
      final snapshotter = DatabaseSnapshotter(
        connection: db,
        databasePath: databasePath,
        files: const IoBackupFiles(),
        validateCandidate: ({required candidatePath, required manifestSchemaVersion}) async {
          expect(File(candidatePath).existsSync(), isTrue);
          expect(manifestSchemaVersion, currentSchemaVersion);
          throw failure;
        },
        createCandidatePath: () => candidatePath,
      );

      await expectLater(
        snapshotter.create(destinationPath: snapshotPath),
        throwsA(same(failure)),
      );

      expect(db.isOpen, isTrue);
      expect(File(snapshotPath).existsSync(), isFalse);
      expect(File(candidatePath).existsSync(), isFalse);
      expect(File('$candidatePath-wal').existsSync(), isFalse);
      expect(File('$candidatePath-shm').existsSync(), isFalse);
    },
  );

  test('rejects an oversized live database before copying it', () async {
    final files = _CopyHookBackupFiles(
      reportedLength: maxLibraryBackupBytes + 1,
      onCopy: (_) async => fail('an oversized database must not be copied'),
    );
    final snapshotter = DatabaseSnapshotter(
      connection: db,
      databasePath: databasePath,
      files: files,
      validateCandidate: ({required candidatePath, required manifestSchemaVersion}) async {},
      createCandidatePath: () => candidatePath,
    );

    await expectLater(
      snapshotter.create(destinationPath: snapshotPath),
      throwsA(
        isA<LibraryBackupException>().having(
          (error) => error.kind,
          'kind',
          LibraryBackupFailureKind.backupTooLarge,
        ),
      ),
    );

    expect(db.isOpen, isTrue);
    expect(File(snapshotPath).existsSync(), isFalse);
    expect(File(candidatePath).existsSync(), isFalse);
  });
}

/// Real file operations with a hook on every copy and an optional fixed
/// length report.
final class _CopyHookBackupFiles implements BackupFiles {
  new({required this.onCopy, this.reportedLength});

  final Future<void> Function(String source) onCopy;
  final int? reportedLength;
  static const _delegate = IoBackupFiles();

  @override
  Future<int> length(String path) async => reportedLength ?? await _delegate.length(path);

  @override
  Future<int?> lengthIfExists(String path) => _delegate.lengthIfExists(path);

  @override
  Stream<List<int>> openRead(String path) => _delegate.openRead(path);

  @override
  Future<int> writeStream(String path, Stream<List<int>> content, {required bool flush}) =>
      _delegate.writeStream(path, content, flush: flush);

  @override
  Future<void> copy(String source, String destination, {required bool flush}) async {
    await onCopy(source);
    await _delegate.copy(source, destination, flush: flush);
  }

  @override
  Future<void> renameReplacing(String source, String destination) => _delegate.renameReplacing(source, destination);

  @override
  Future<void> deleteIfExists(String path) => _delegate.deleteIfExists(path);

  @override
  Future<void> deleteDatabaseSidecars(String databasePath) => _delegate.deleteDatabaseSidecars(databasePath);

  @override
  Future<String> createTemporaryDirectory(String prefix) => _delegate.createTemporaryDirectory(prefix);

  @override
  Future<void> deleteDirectory(String path) => _delegate.deleteDirectory(path);
}

final class _CheckpointHookDatabase implements Database {
  new(this._delegate, {required this.afterCheckpoint});

  final Database _delegate;
  final Future<void> Function() afterCheckpoint;

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    final result = await _delegate.rawQuery(sql, arguments);
    if (sql == 'PRAGMA wal_checkpoint(TRUNCATE)') {
      await afterCheckpoint();
    }
    return result;
  }

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => _delegate.transaction(action, exclusive: exclusive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _storeIngredient(Database db, String id) =>
    db.insert('ingredients', {'id': id, 'name': id, 'default_unit': 'g'});

Future<List<String>> _ingredientIds(Database db) async => [
  for (final row in await db.query('ingredients', orderBy: 'id')) row['id']! as String,
];
