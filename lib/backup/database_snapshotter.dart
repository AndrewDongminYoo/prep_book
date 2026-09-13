import 'dart:math';
import 'dart:typed_data';

import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite/sqflite.dart';

/// Validates a staged database snapshot.
typedef ValidateBackupCandidate =
    Future<void> Function({
      required String candidatePath,
      required int manifestSchemaVersion,
    });

/// Captures a consistent copy of an owned live database connection.
final class DatabaseSnapshotter {
  /// Creates a snapshotter for [connection] at [databasePath].
  DatabaseSnapshotter({
    required Database connection,
    required String databasePath,
    required DatabaseFactory factory,
    required BackupFiles files,
    required ValidateBackupCandidate validateCandidate,
    String Function()? createCandidatePath,
  }) : this._(
         connection,
         databasePath,
         factory,
         files,
         validateCandidate,
         createCandidatePath ??
             (() => '$databasePath.backup-candidate-${_randomToken()}'),
       );

  DatabaseSnapshotter._(
    this._connection,
    this._databasePath,
    this._factory,
    this._files,
    this._validateCandidate,
    this._createCandidatePath,
  );

  final Database _connection;
  final String _databasePath;
  final DatabaseFactory _factory;
  final BackupFiles _files;
  final ValidateBackupCandidate _validateCandidate;
  final String Function() _createCandidatePath;

  /// Returns validated bytes from one complete live-database state.
  Future<Uint8List> create() async {
    Uint8List? bytes;
    while (bytes == null) {
      await _connection.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
      bytes = await _connection.transaction((txn) async {
        await txn.rawQuery('SELECT 1');
        final walLength = await _files.lengthIfExists('$_databasePath-wal');
        if ((walLength ?? 0) > 0) return null;
        if (await _files.length(_databasePath) > maxLibraryBackupBytes) {
          throw LibraryBackupException(
            LibraryBackupFailureKind.backupTooLarge,
            cause: const FormatException(
              'The database exceeds the supported backup size.',
            ),
            stackTrace: StackTrace.current,
          );
        }
        return await _factory.readDatabaseBytes(_databasePath);
      }, exclusive: true);
    }

    final candidatePath = _createCandidatePath();
    try {
      await _files.writeBytes(candidatePath, bytes, flush: true);
      await _validateCandidate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      );
      return bytes;
    } finally {
      await _files.deleteDatabaseSidecars(candidatePath);
      await _files.deleteIfExists(candidatePath);
    }
  }
}

String _randomToken() {
  final random = Random.secure();
  final high = random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  final low = random.nextInt(1 << 32).toRadixString(16).padLeft(8, '0');
  return '$high$low';
}
