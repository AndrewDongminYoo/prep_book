import 'dart:io';

import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite/sqflite.dart';

/// The generated database fixture used by backup memory profiling.
final class BackupMemoryFixture {
  /// Creates a completed fixture report.
  const BackupMemoryFixture({
    required this.path,
    required this.databaseBytes,
    required this.ingredientCount,
  });

  /// The absolute SQLite database path.
  final String path;

  /// The final main-database file length after checkpointing.
  final int databaseBytes;

  /// The number of valid ingredient rows used to reach [databaseBytes].
  final int ingredientCount;
}

/// Generates and validates one current-schema profiling fixture.
Future<BackupMemoryFixture> generateBackupMemoryFixture({
  required DatabaseFactory factory,
  required String path,
  required int targetBytes,
  int maxBytes = maxLibraryBackupBytes,
  int payloadBytes = 64 * 1024,
}) async {
  if (targetBytes <= 0) {
    throw ArgumentError.value(targetBytes, 'targetBytes', 'must be positive');
  }
  if (maxBytes <= 0) {
    throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
  }
  if (payloadBytes <= 0) {
    throw ArgumentError.value(payloadBytes, 'payloadBytes', 'must be positive');
  }
  final requiredHeadroom = payloadBytes * 8;
  if (targetBytes > maxBytes - requiredHeadroom) {
    throw ArgumentError.value(
      targetBytes,
      'targetBytes',
      'must leave at least $requiredHeadroom bytes below maxBytes',
    );
  }
  if (await factory.databaseExists(path) || File(path).existsSync()) {
    throw StateError('The profiling fixture path already exists: $path');
  }

  Database? database;
  var ingredientCount = 0;
  try {
    database = await openPrepBookDatabase(
      path: path,
      factory: factory,
      singleInstance: false,
    );
    await database.execute('PRAGMA auto_vacuum = NONE');
    await database.execute('VACUUM');
    await database.rawQuery('PRAGMA journal_mode = WAL');
    await database.rawQuery('PRAGMA secure_delete = OFF');
    await database.insert('ingredients', {
      'id': 'profile-ingredient',
      'name': 'Profiling ingredient',
      'default_unit': 'g',
      'category': null,
    });
    ingredientCount = 1;
    await database.execute('''
CREATE TABLE _backup_memory_profile_payload (
  payload BLOB NOT NULL
)
''');

    var databaseBytes = await _checkpointAndMeasure(database, path);
    while (databaseBytes < targetBytes) {
      await database.transaction((transaction) async {
        for (var offset = 0; offset < 8; offset++) {
          await transaction.rawInsert(
            'INSERT INTO _backup_memory_profile_payload (payload) '
            'VALUES (randomblob(?))',
            [payloadBytes],
          );
        }
      });
      databaseBytes = await _checkpointAndMeasure(database, path);
      if (databaseBytes > maxBytes) {
        throw StateError(
          'The profiling fixture exceeded maxBytes: '
          '$databaseBytes > $maxBytes',
        );
      }
    }
    await database.execute('DROP TABLE _backup_memory_profile_payload');
    databaseBytes = await _checkpointAndMeasure(database, path);
    if (databaseBytes > maxBytes) {
      throw StateError(
        'The finalized profiling fixture exceeded maxBytes: '
        '$databaseBytes > $maxBytes',
      );
    }

    await database.close();
    database = null;
    await BackupDatabaseValidator(factory: factory).validate(
      candidatePath: path,
      manifestSchemaVersion: currentSchemaVersion,
    );
    databaseBytes = await File(path).length();
    if (databaseBytes < targetBytes) {
      throw StateError(
        'The finalized profiling fixture fell below targetBytes: '
        '$databaseBytes < $targetBytes',
      );
    }
    if (databaseBytes > maxBytes) {
      throw StateError(
        'Validation changed the profiling fixture beyond maxBytes: '
        '$databaseBytes > $maxBytes',
      );
    }
    return BackupMemoryFixture(
      path: path,
      databaseBytes: databaseBytes,
      ingredientCount: ingredientCount,
    );
  } on Object {
    if (database?.isOpen ?? false) await database!.close();
    await factory.deleteDatabase(path);
    rethrow;
  }
}

Future<int> _checkpointAndMeasure(Database database, String path) async {
  await database.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  return await File(path).length();
}
