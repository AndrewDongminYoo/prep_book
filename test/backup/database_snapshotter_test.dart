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
  late Database db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prep-book-snapshot-');
    databasePath = '${directory.path}/library.db';
    candidatePath = '${directory.path}/candidate.db';
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
      final factory = _ReadHookDatabaseFactory(
        databaseFactoryFfi,
        onRead: () async {
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
            reason: 'the file read must run while the connection is locked',
          );
        },
      );
      final validator = BackupDatabaseValidator(factory: factory);
      final snapshotter = DatabaseSnapshotter(
        connection: db,
        databasePath: databasePath,
        factory: factory,
        files: const IoBackupFiles(),
        validateCandidate: validator.validate,
        createCandidatePath: () => candidatePath,
      );

      final bytes = await snapshotter.create();
      await queuedWrite;

      final capturedPath = '${directory.path}/captured.db';
      await databaseFactoryFfi.writeDatabaseBytes(capturedPath, bytes);
      final captured = await openPrepBookDatabase(
        path: capturedPath,
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
      factory: databaseFactoryFfi,
      files: const IoBackupFiles(),
      validateCandidate: validator.validate,
      createCandidatePath: () => candidatePath,
    );

    final bytes = await snapshotter.create();

    final capturedPath = '${directory.path}/captured-after-gap.db';
    await databaseFactoryFfi.writeDatabaseBytes(capturedPath, bytes);
    final captured = await openPrepBookDatabase(
      path: capturedPath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    addTearDown(captured.close);
    expect(await _ingredientIds(captured), ['before', 'during']);
    expect(checkpointCalls, 2);
  });

  test(
    'validation failure keeps live open and removes the candidate',
    () async {
      final failure = LibraryBackupException(
        LibraryBackupFailureKind.invalidDatabase,
        cause: StateError('candidate rejected'),
        stackTrace: StackTrace.current,
      );
      final snapshotter = DatabaseSnapshotter(
        connection: db,
        databasePath: databasePath,
        factory: databaseFactoryFfi,
        files: const IoBackupFiles(),
        validateCandidate: ({required candidatePath, required manifestSchemaVersion}) async {
          expect(File(candidatePath).existsSync(), isTrue);
          expect(manifestSchemaVersion, currentSchemaVersion);
          throw failure;
        },
        createCandidatePath: () => candidatePath,
      );

      await expectLater(snapshotter.create(), throwsA(same(failure)));

      expect(db.isOpen, isTrue);
      expect(File(candidatePath).existsSync(), isFalse);
      expect(File('$candidatePath-wal').existsSync(), isFalse);
      expect(File('$candidatePath-shm').existsSync(), isFalse);
    },
  );

  test('rejects an oversized live database before reading its bytes', () async {
    var didReadDatabaseBytes = false;
    final factory = _ReadHookDatabaseFactory(
      databaseFactoryFfi,
      onRead: () async => didReadDatabaseBytes = true,
    );
    final snapshotter = DatabaseSnapshotter(
      connection: db,
      databasePath: databasePath,
      factory: factory,
      files: const _LengthReportingBackupFiles(maxLibraryBackupBytes + 1),
      validateCandidate: ({required candidatePath, required manifestSchemaVersion}) async {},
      createCandidatePath: () => candidatePath,
    );

    await expectLater(
      snapshotter.create(),
      throwsA(
        isA<LibraryBackupException>().having(
          (error) => error.kind,
          'kind',
          LibraryBackupFailureKind.backupTooLarge,
        ),
      ),
    );

    expect(didReadDatabaseBytes, isFalse);
    expect(db.isOpen, isTrue);
    expect(File(candidatePath).existsSync(), isFalse);
  });
}

final class _LengthReportingBackupFiles implements BackupFiles {
  const _LengthReportingBackupFiles(this.reportedLength);

  final int reportedLength;
  static const _delegate = IoBackupFiles();

  @override
  Future<int> length(String path) async => reportedLength;

  @override
  Future<int?> lengthIfExists(String path) async => 0;

  @override
  Future<Uint8List> readBytes(String path) => _delegate.readBytes(path);

  @override
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    required bool flush,
  }) => _delegate.writeBytes(path, bytes, flush: flush);

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

final class _ReadHookDatabaseFactory implements DatabaseFactory {
  _ReadHookDatabaseFactory(this._delegate, {required this.onRead});

  final DatabaseFactory _delegate;
  final Future<void> Function() onRead;

  @override
  Future<Uint8List> readDatabaseBytes(String path) async {
    await onRead();
    return await _delegate.readDatabaseBytes(path);
  }

  @override
  Future<void> writeDatabaseBytes(String path, Uint8List bytes) => _delegate.writeDatabaseBytes(path, bytes);

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) =>
      _delegate.openDatabase(path, options: options);

  @override
  Future<bool> databaseExists(String path) => _delegate.databaseExists(path);

  @override
  Future<void> deleteDatabase(String path) => _delegate.deleteDatabase(path);

  @override
  Future<String> getDatabasesPath() => _delegate.getDatabasesPath();

  @override
  Future<void> setDatabasesPath(String path) => _delegate.setDatabasesPath(path);
}

final class _CheckpointHookDatabase implements Database {
  _CheckpointHookDatabase(this._delegate, {required this.afterCheckpoint});

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
