import 'dart:math';

import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite/sqflite.dart';

/// Validates a staged database snapshot.
typedef ValidateBackupCandidate = Future<void> Function({
  required String candidatePath,
  required int manifestSchemaVersion,
});

/// Captures a consistent copy of an owned live database connection.
final class DatabaseSnapshotter {
  /// Creates a snapshotter for [connection] at [databasePath].
  new({
    required Database connection,
    required String databasePath,
    required BackupFiles files,
    required ValidateBackupCandidate validateCandidate,
    String Function()? createCandidatePath,
  }) : this._(
         connection,
         databasePath,
         files,
         validateCandidate,
         createCandidatePath ?? (() => '$databasePath.backup-candidate-${_randomToken()}'),
       );

  new _(
    this._connection,
    this._databasePath,
    this._files,
    this._validateCandidate,
    this._createCandidatePath,
  );

  final Database _connection;
  final String _databasePath;
  final BackupFiles _files;
  final ValidateBackupCandidate _validateCandidate;
  final String Function() _createCandidatePath;

  /// Copies one complete live-database state to [destinationPath] and
  /// validates it.
  ///
  /// The copy streams file to file while the exclusive transaction holds
  /// the connection, so no write lands between the checkpoint and the last
  /// byte, and no full-size copy of the database is held in memory. The
  /// copy validated is a second, identical file rather than
  /// [destinationPath] itself, because opening a database to validate it
  /// may touch the file, and what gets archived has to be the exact state
  /// the live connection held. On failure [destinationPath] is removed.
  Future<void> create({required String destinationPath}) async {
    try {
      var captured = false;
      while (!captured) {
        await _connection.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
        captured = await _connection.transaction((txn) async {
          await txn.rawQuery('SELECT 1');
          final walLength = await _files.lengthIfExists('$_databasePath-wal');
          if ((walLength ?? 0) > 0) return false;
          if (await _files.length(_databasePath) > maxLibraryBackupBytes) {
            throw LibraryBackupException(
              LibraryBackupFailureKind.backupTooLarge,
              cause: const FormatException(
                'The database exceeds the supported backup size.',
              ),
              stackTrace: StackTrace.current,
            );
          }
          await _files.copy(_databasePath, destinationPath, flush: true);
          return true;
        }, exclusive: true);
      }

      final candidatePath = _createCandidatePath();
      try {
        await _files.copy(destinationPath, candidatePath, flush: true);
        await _validateCandidate(
          candidatePath: candidatePath,
          manifestSchemaVersion: currentSchemaVersion,
        );
      } finally {
        await _files.deleteDatabaseSidecars(candidatePath);
        await _files.deleteIfExists(candidatePath);
      }
    } on Object {
      await _files.deleteIfExists(destinationPath);
      rethrow;
    }
  }
}

String _randomToken() {
  final random = Random.secure();
  final high = random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  final low = random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  return '$high$low';
}
