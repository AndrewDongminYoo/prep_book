import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('a new database opens at the current schema version', () async {
    final db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    expect(await db.getVersion(), currentSchemaVersion);
  });

  test('every version 1 table exists', () async {
    final db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ?',
      whereArgs: ['table'],
    );
    final names = rows.map((row) => row['name']! as String).toSet();

    expect(
      names,
      containsAll(<String>[
        'ingredients',
        'recipes',
        'recipe_components',
        'production_runs',
        'run_acknowledgements',
        'run_overrides',
      ]),
    );
  });

  test('falls back to the global factory when none is provided', () async {
    databaseFactory = databaseFactoryFfi;

    final db = await openPrepBookDatabase(path: inMemoryDatabasePath);
    addTearDown(db.close);

    expect(await db.getVersion(), currentSchemaVersion);
  });

  test('foreign key enforcement is on', () async {
    final db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final rows = await db.rawQuery('PRAGMA foreign_keys');

    expect(rows.single.values.single, 1);
  });
}
