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
  late String livePath;
  late String candidatePath;
  late String rollbackPath;
  late String rollbackInstallPath;
  late String failedPath;
  late Database live;
  late Uint8List restoredBytes;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prep-book-session-');
    livePath = '${directory.path}/library.db';
    candidatePath = '${directory.path}/candidate.db';
    rollbackPath = '${directory.path}/rollback.db';
    rollbackInstallPath = '$rollbackPath.install';
    failedPath = '${directory.path}/failed.db';
    live = await _open(livePath);
    await _storeIngredient(live, 'previous');
    restoredBytes = await _databaseBytes(
      '${directory.path}/restored-source.db',
      'restored',
    );
  });

  tearDown(() async {
    if (live.isOpen) await live.close();
    await directory.delete(recursive: true);
  });

  DatabaseSession buildSession({
    _FaultPoint? fault,
    ValidateBackupCandidate? validateCandidate,
    ActivateDatabase? onActivate,
    void Function()? onMountRecoveryFailure,
    ReportDatabaseSessionError? onReportError,
  }) {
    var openCalls = 0;
    return DatabaseSession(
      connection: live,
      databasePath: livePath,
      factory: databaseFactoryFfi,
      files: _FaultingBackupFiles(
        const IoBackupFiles(),
        fault: fault,
        candidatePath: candidatePath,
        rollbackPath: rollbackPath,
        failedPath: failedPath,
      ),
      validateCandidate: validateCandidate ?? BackupDatabaseValidator(factory: databaseFactoryFfi).validate,
      activate:
          onActivate ??
          (connection, {required restored}) async {
            await _ids(connection);
          },
      mountRecoveryFailure: onMountRecoveryFailure ?? () {},
      reportError: onReportError,
      createCandidatePath: () => candidatePath,
      createRollbackPath: () => rollbackPath,
      createFailedPath: () => failedPath,
      openDatabase: (path) async {
        openCalls++;
        final replacementMustFail = switch (fault) {
          _FaultPoint.replacementReopen ||
          _FaultPoint.diagnosticCopy ||
          _FaultPoint.rollbackInstall ||
          _FaultPoint.rollbackReopen => openCalls == 1,
          _ => false,
        };
        if (replacementMustFail) {
          throw StateError('replacement reopen failed');
        }
        if (fault == _FaultPoint.rollbackReopen && openCalls == 2) {
          throw StateError('rollback reopen failed');
        }
        final opened = await _open(path);
        if (fault == _FaultPoint.replacementClose && openCalls == 1) {
          return _CloseFailingDatabase(opened);
        }
        return opened;
      },
    );
  }

  Future<List<bool>> temporaryPaths() => Future.value([
    for (final path in [
      candidatePath,
      rollbackPath,
      rollbackInstallPath,
      failedPath,
    ])
      File(path).existsSync(),
  ]);

  test('validates, replaces, activates, and cleans a candidate', () async {
    final activations = <({bool restored, List<String> ids})>[];
    final session = buildSession(
      onActivate: (connection, {required restored}) async {
        activations.add((restored: restored, ids: await _ids(connection)));
      },
    );

    await session.restore(
      restoredBytes,
      manifestSchemaVersion: currentSchemaVersion,
    );
    live = session.connection;

    expect(activations, hasLength(1));
    expect(activations.single.restored, isTrue);
    expect(activations.single.ids, ['restored']);
    expect(await _ids(live), ['restored']);
    expect(await temporaryPaths(), everyElement(isFalse));
  });

  test('validation failure leaves live bytes and objects unchanged', () async {
    await live.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
    final beforeBytes = await File(livePath).readAsBytes();
    final beforeIds = await _ids(live);
    final failure = LibraryBackupException(
      LibraryBackupFailureKind.invalidDatabase,
      cause: StateError('candidate rejected'),
      stackTrace: StackTrace.current,
    );
    final session = buildSession(
      validateCandidate: ({required candidatePath, required manifestSchemaVersion}) async {
        expect(File(candidatePath).existsSync(), isTrue);
        throw failure;
      },
    );

    await expectLater(
      session.restore(
        restoredBytes,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(same(failure)),
    );

    expect(live.isOpen, isTrue);
    expect(await File(livePath).readAsBytes(), beforeBytes);
    expect(await _ids(live), beforeIds);
    expect(await temporaryPaths(), everyElement(isFalse));
  });

  test('an untyped pre-close failure is mapped without closing live', () async {
    final error = StateError('candidate validation crashed');
    final session = buildSession(
      validateCandidate: ({required candidatePath, required manifestSchemaVersion}) async {
        throw error;
      },
    );

    await expectLater(
      session.restore(
        restoredBytes,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(
        isA<LibraryBackupException>()
            .having(
              (failure) => failure.kind,
              'kind',
              LibraryBackupFailureKind.restoreFailed,
            )
            .having((failure) => failure.cause, 'cause', same(error)),
      ),
    );

    expect(live.isOpen, isTrue);
    expect(await _ids(live), ['previous']);
  });

  test('cleanup failures are reported without undoing activation', () async {
    final reports = <Object>[];
    final session = buildSession(
      fault: _FaultPoint.cleanupDelete,
      onReportError: (error, stackTrace) => reports.add(error),
    );

    await session.restore(
      restoredBytes,
      manifestSchemaVersion: currentSchemaVersion,
    );
    live = session.connection;

    expect(await _ids(live), ['restored']);
    expect(reports, hasLength(4));
    expect(reports, everyElement(isA<StateError>()));
  });

  for (final fault in const [
    _FaultPoint.rollbackCopy,
    _FaultPoint.candidateRename,
    _FaultPoint.replacementReopen,
    _FaultPoint.replacementActivation,
    _FaultPoint.replacementClose,
    _FaultPoint.diagnosticCopy,
  ]) {
    test('$fault restores and activates the previous library', () async {
      final activations = <({bool restored, List<String> ids})>[];
      final session = buildSession(
        fault: fault,
        onActivate: (connection, {required restored}) async {
          if ((fault == _FaultPoint.replacementActivation || fault == _FaultPoint.replacementClose) && restored) {
            throw StateError('replacement activation failed');
          }
          activations.add((restored: restored, ids: await _ids(connection)));
        },
      );

      await expectLater(
        session.restore(
          restoredBytes,
          manifestSchemaVersion: currentSchemaVersion,
        ),
        throwsA(
          isA<LibraryBackupException>().having(
            (error) => error.kind,
            'kind',
            LibraryBackupFailureKind.restoreFailed,
          ),
        ),
      );
      live = session.connection;

      expect(live.isOpen, isTrue);
      expect(await _ids(live), ['previous']);
      expect(activations.last.restored, isFalse);
      expect(activations.last.ids, ['previous']);
      expect(await temporaryPaths(), everyElement(isFalse));
    });
  }

  for (final fault in const [
    _FaultPoint.rollbackInstall,
    _FaultPoint.rollbackReopen,
  ]) {
    test('$fault mounts failure and preserves readable diagnostics', () async {
      var failureMounts = 0;
      final reports = <({Object error, StackTrace stackTrace})>[];
      final session = buildSession(
        fault: fault,
        onMountRecoveryFailure: () => failureMounts++,
        onReportError: (error, stackTrace) {
          reports.add((error: error, stackTrace: stackTrace));
        },
      );

      await expectLater(
        session.restore(
          restoredBytes,
          manifestSchemaVersion: currentSchemaVersion,
        ),
        throwsA(
          isA<LibraryBackupException>().having(
            (error) => error.kind,
            'kind',
            LibraryBackupFailureKind.recoveryFailed,
          ),
        ),
      );

      expect(failureMounts, 1);
      expect(reports, hasLength(2));
      final retryDatabase = await _open(livePath);
      try {
        expect(
          await _ids(retryDatabase),
          fault == _FaultPoint.rollbackInstall ? ['restored'] : ['previous'],
        );
      } finally {
        await retryDatabase.close();
      }
      final readable = <String>[];
      for (final path in [livePath, rollbackPath, failedPath]) {
        final file = File(path);
        if (file.existsSync() && await file.length() > 0) readable.add(path);
      }
      expect(readable, hasLength(greaterThanOrEqualTo(2)));
    });
  }

  test('mount failure preserves the recoveryFailed contract', () async {
    final mountError = StateError('failure root did not mount');
    final reports = <Object>[];
    final session = buildSession(
      fault: _FaultPoint.rollbackReopen,
      onMountRecoveryFailure: () => throw mountError,
      onReportError: (error, stackTrace) => reports.add(error),
    );

    await expectLater(
      session.restore(
        restoredBytes,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(
        isA<LibraryBackupException>().having(
          (error) => error.kind,
          'kind',
          LibraryBackupFailureKind.recoveryFailed,
        ),
      ),
    );

    expect(reports, hasLength(3));
    expect(reports.last, same(mountError));
  });
}

enum _FaultPoint {
  rollbackCopy,
  candidateRename,
  replacementReopen,
  replacementActivation,
  replacementClose,
  diagnosticCopy,
  rollbackInstall,
  rollbackReopen,
  cleanupDelete,
}

final class _FaultingBackupFiles implements BackupFiles {
  const _FaultingBackupFiles(
    this._delegate, {
    required this.fault,
    required this.candidatePath,
    required this.rollbackPath,
    required this.failedPath,
  });

  final BackupFiles _delegate;
  final _FaultPoint? fault;
  final String candidatePath;
  final String rollbackPath;
  final String failedPath;

  @override
  Future<void> copy(String source, String destination, {required bool flush}) {
    if (fault == _FaultPoint.rollbackCopy) {
      throw StateError('rollback copy failed');
    }
    if (fault == _FaultPoint.diagnosticCopy && destination == failedPath) {
      throw StateError('diagnostic copy failed');
    }
    return _delegate.copy(source, destination, flush: flush);
  }

  @override
  Future<void> renameReplacing(String source, String destination) {
    if (fault == _FaultPoint.candidateRename && source == candidatePath) {
      throw StateError('candidate rename failed');
    }
    if (fault == _FaultPoint.rollbackInstall && source == '$rollbackPath.install') {
      throw StateError('rollback rename failed');
    }
    return _delegate.renameReplacing(source, destination);
  }

  @override
  Future<void> deleteDatabaseSidecars(String databasePath) => _delegate.deleteDatabaseSidecars(databasePath);

  @override
  Future<void> deleteIfExists(String path) {
    if (fault == _FaultPoint.cleanupDelete) {
      throw StateError('cleanup delete failed');
    }
    return _delegate.deleteIfExists(path);
  }

  @override
  Future<int> length(String path) => _delegate.length(path);

  @override
  Future<int?> lengthIfExists(String path) => _delegate.lengthIfExists(path);

  @override
  Future<Uint8List> readBytes(String path) => _delegate.readBytes(path);

  @override
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    required bool flush,
  }) => _delegate.writeBytes(path, bytes, flush: flush);
}

final class _CloseFailingDatabase implements Database {
  const _CloseFailingDatabase(this._delegate);

  final Database _delegate;

  @override
  bool get isOpen => _delegate.isOpen;

  @override
  Future<void> close() => Future<void>.error(StateError('replacement close failed'));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<Database> _open(String path) => openPrepBookDatabase(
  path: path,
  factory: databaseFactoryFfi,
  singleInstance: false,
);

Future<void> _storeIngredient(Database db, String id) => SqfliteIngredientRepository(
  db,
).upsert(Ingredient(id: id, name: id, defaultUnit: Unit.gram));

Future<Uint8List> _databaseBytes(String path, String ingredientId) async {
  final db = await _open(path);
  await _storeIngredient(db, ingredientId);
  await db.close();
  return await File(path).readAsBytes();
}

Future<List<String>> _ids(Database db) async => [
  for (final row in await db.query('ingredients', orderBy: 'id')) row['id']! as String,
];
