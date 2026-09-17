import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' show Random;
import 'dart:typed_data';

import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/backup/database_snapshotter.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite/sqflite.dart';

/// Rebuilds and mounts the application over [connection].
typedef ActivateDatabase = FutureOr<void> Function(Database connection, {required bool restored});

/// Records one internal restore error without exposing it to presentation.
typedef ReportDatabaseSessionError = void Function(Object error, StackTrace stackTrace);

/// Opens the database at [path] as the session's next owned connection.
typedef OpenSessionDatabase = Future<Database> Function(String path);

/// Owns the live connection and performs recoverable database replacement.
final class DatabaseSession {
  /// Creates a session over an already-open [connection].
  DatabaseSession({
    required Database connection,
    required String databasePath,
    required DatabaseFactory factory,
    required BackupFiles files,
    required ValidateBackupCandidate validateCandidate,
    required ActivateDatabase activate,
    required FutureOr<void> Function() mountRecoveryFailure,
    String Function()? createCandidatePath,
    String Function()? createRollbackPath,
    String Function()? createFailedPath,
    OpenSessionDatabase? openDatabase,
    ReportDatabaseSessionError? reportError,
  }) : this._(
         connection,
         databasePath,
         files,
         validateCandidate,
         activate,
         mountRecoveryFailure,
         createCandidatePath ?? (() => '$databasePath.restore-candidate-${_randomToken()}'),
         createRollbackPath ?? (() => '$databasePath.restore-rollback-${_randomToken()}'),
         createFailedPath ?? (() => '$databasePath.restore-failed-${_randomToken()}'),
         openDatabase ?? ((path) => openPrepBookDatabase(path: path, factory: factory)),
         reportError ?? _logDatabaseSessionError,
       );

  DatabaseSession._(
    this._connection,
    this._databasePath,
    this._files,
    this._validateCandidate,
    this._activate,
    this._mountRecoveryFailure,
    this._createCandidatePath,
    this._createRollbackPath,
    this._createFailedPath,
    this._openDatabase,
    this._reportError,
  );

  Database _connection;
  final String _databasePath;
  final BackupFiles _files;
  final ValidateBackupCandidate _validateCandidate;
  final ActivateDatabase _activate;
  final FutureOr<void> Function() _mountRecoveryFailure;
  final String Function() _createCandidatePath;
  final String Function() _createRollbackPath;
  final String Function() _createFailedPath;
  final OpenSessionDatabase _openDatabase;
  final ReportDatabaseSessionError _reportError;

  /// The currently owned live connection.
  Database get connection => _connection;

  /// Validates and activates [databaseBytes] at the live database path.
  Future<void> restore(
    Uint8List databaseBytes, {
    required int manifestSchemaVersion,
  }) async {
    final candidatePath = _createCandidatePath();
    final rollbackPath = _createRollbackPath();
    final rollbackInstallPath = '$rollbackPath.install';
    final failedPath = _createFailedPath();
    var liveCloseStarted = false;
    var rollbackReady = false;
    var replacementMayBeInstalled = false;
    Database? replacement;

    try {
      await _files.writeBytes(candidatePath, databaseBytes, flush: true);
      await _validateCandidate(
        candidatePath: candidatePath,
        manifestSchemaVersion: manifestSchemaVersion,
      );

      liveCloseStarted = true;
      await _connection.close();
      await _files.deleteDatabaseSidecars(_databasePath);
      await _files.deleteDatabaseSidecars(candidatePath);
      await _files.copy(_databasePath, rollbackPath, flush: true);
      rollbackReady = true;
      replacementMayBeInstalled = true;
      await _files.renameReplacing(candidatePath, _databasePath);

      replacement = await _openDatabase(_databasePath);
      await _activate(replacement, restored: true);
      _connection = replacement;
      replacement = null;
      await _cleanupDisposable(
        candidatePath,
        rollbackPath,
        rollbackInstallPath,
        failedPath,
      );
      return;
    } on Object catch (error, stackTrace) {
      if (!liveCloseStarted) {
        await _cleanupDisposable(
          candidatePath,
          rollbackPath,
          rollbackInstallPath,
          failedPath,
        );
        if (error is LibraryBackupException) rethrow;
        throw LibraryBackupException(
          LibraryBackupFailureKind.restoreFailed,
          cause: error,
          stackTrace: stackTrace,
        );
      }

      _reportError(error, stackTrace);
      try {
        if (replacement != null && replacement.isOpen) {
          try {
            await replacement.close();
          } on Object catch (error, stackTrace) {
            _reportError(error, stackTrace);
          }
        }
        if (rollbackReady) {
          await _files.copy(rollbackPath, rollbackInstallPath, flush: true);
          if (replacementMayBeInstalled) {
            try {
              await _files.copy(_databasePath, failedPath, flush: true);
            } on Object catch (error, stackTrace) {
              _reportError(error, stackTrace);
            }
          }
          await _files.renameReplacing(rollbackInstallPath, _databasePath);
        }

        final recovered = await _openDatabase(_databasePath);
        try {
          await _activate(recovered, restored: false);
        } on Object {
          await recovered.close();
          rethrow;
        }
        _connection = recovered;
        await _cleanupDisposable(
          candidatePath,
          rollbackPath,
          rollbackInstallPath,
          failedPath,
        );
      } on Object catch (recoveryError, recoveryStackTrace) {
        _reportError(recoveryError, recoveryStackTrace);
        Object? mountError;
        try {
          await _mountRecoveryFailure();
        } on Object catch (error, stackTrace) {
          mountError = error;
          _reportError(error, stackTrace);
        }
        throw LibraryBackupException(
          LibraryBackupFailureKind.recoveryFailed,
          cause: (
            restoreError: error,
            recoveryError: recoveryError,
            mountError: mountError,
          ),
          stackTrace: recoveryStackTrace,
        );
      }

      throw LibraryBackupException(
        LibraryBackupFailureKind.restoreFailed,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _cleanupDisposable(
    String candidatePath,
    String rollbackPath,
    String rollbackInstallPath,
    String failedPath,
  ) async {
    for (final path in [
      candidatePath,
      rollbackPath,
      rollbackInstallPath,
      failedPath,
    ]) {
      try {
        await _files.deleteDatabaseSidecars(path);
        await _files.deleteIfExists(path);
      } on Object catch (error, stackTrace) {
        _reportError(error, stackTrace);
      }
    }
  }
}

String _randomToken() {
  final random = Random.secure();
  final high = random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  final low = random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  return '$high$low';
}

void _logDatabaseSessionError(Object error, StackTrace stackTrace) {
  developer.log(
    'library database replacement failed',
    error: error,
    stackTrace: stackTrace,
  );
}
