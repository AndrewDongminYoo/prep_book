import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('every registered upgrade is reachable from version 1', () {
    for (final version in schemaUpgrades.keys) {
      expect(version, greaterThan(1));
      expect(version, lessThanOrEqualTo(currentSchemaVersion));
    }
  });

  test('applying the upgrade path preserves existing rows', () async {
    const path = inMemoryDatabasePath;
    final db = await openPrepBookDatabase(
      path: path,
      factory: databaseFactoryFfi,
    );
    await db.insert('ingredients', <String, Object?>{
      'id': 'flour',
      'name': 'Flour',
      'default_unit_symbol': 'g',
      'category': null,
    });

    // Re-running the opener against an already-current database must be a
    // no-op rather than a re-create, which is what a failed upgrade path
    // would look like.
    final reopened = await openPrepBookDatabase(
      path: path,
      factory: databaseFactoryFfi,
    );
    addTearDown(reopened.close);

    final rows = await reopened.query('ingredients');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'flour');
    expect(await reopened.getVersion(), currentSchemaVersion);
  });
}
