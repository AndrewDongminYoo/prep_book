import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../integration_test/support/backup_memory_fixture.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('generates a bounded current-schema database that validates', () async {
    final directory = await Directory.systemTemp.createTemp(
      'prep-book-memory-fixture-',
    );
    final path = '${directory.path}/profile.db';
    addTearDown(() => directory.delete(recursive: true));

    const targetBytes = 1024 * 1024;
    const maxBytes = 2 * 1024 * 1024;
    final fixture = await generateBackupMemoryFixture(
      factory: databaseFactoryFfi,
      path: path,
      targetBytes: targetBytes,
      maxBytes: maxBytes,
      payloadBytes: 16 * 1024,
    );

    expect(fixture.path, path);
    expect(fixture.databaseBytes, greaterThanOrEqualTo(targetBytes));
    expect(fixture.databaseBytes, lessThanOrEqualTo(maxBytes));
    expect(fixture.ingredientCount, greaterThan(0));
    expect(await File(path).length(), fixture.databaseBytes);

    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    addTearDown(db.close);
    expect(await db.getVersion(), currentSchemaVersion);
    expect(
      Sqflite.firstIntValue(
        await db.rawQuery('SELECT COUNT(*) FROM ingredients'),
      ),
      fixture.ingredientCount,
    );

    final archivePath = '${directory.path}/profile.prepbook';
    await const BackupArchiveCodec().encodeFile(
      databasePath: path,
      archivePath: archivePath,
      databaseSchemaVersion: currentSchemaVersion,
      createdAtUtc: DateTime.utc(2026),
    );
    expect(
      await File(archivePath).length(),
      greaterThanOrEqualTo((fixture.databaseBytes * 0.9).floor()),
      reason: 'the profiling fixture must remain near-limit after ZIP',
    );

    await BackupDatabaseValidator(factory: databaseFactoryFfi).validate(
      candidatePath: path,
      manifestSchemaVersion: currentSchemaVersion,
    );
  });
}
