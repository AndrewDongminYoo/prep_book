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
    final previousFactory = databaseFactoryOrNull;
    addTearDown(() => databaseFactoryOrNull = previousFactory);
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

  test(
    'a repeated acknowledgement is rejected, with and without a component',
    () async {
      final db = await openPrepBookDatabase(
        path: inMemoryDatabasePath,
        factory: databaseFactoryFfi,
      );
      addTearDown(db.close);

      await db.insert('production_runs', <String, Object?>{
        'id': 'run-1',
        'recipe_id': 'recipe-1',
        'recipe_revision': 1,
        'target_numerator': '1',
        'target_denominator': '1',
        'target_unit': 'g',
        'created_at': '2026-09-07T00:00:00Z',
        'result_json': '{}',
      });

      Map<String, Object?> ack({String? componentId}) => <String, Object?>{
        'run_id': 'run-1',
        'warning_kind': 'archivedDependency',
        'recipe_id': 'recipe-1',
        'component_id': componentId,
      };

      // No component_id: the two rows would collide under a plain unique
      // index, but NOT under one scoped to non-NULL values, so this alone
      // would pass even if idx_ack_with_component were the only guard.
      await db.insert('run_acknowledgements', ack());
      await expectLater(
        db.insert('run_acknowledgements', ack()),
        throwsA(isA<DatabaseException>()),
      );

      // With a component_id: covered by idx_ack_with_component instead.
      await db.insert(
        'run_acknowledgements',
        ack(componentId: 'flour'),
      );
      await expectLater(
        db.insert('run_acknowledgements', ack(componentId: 'flour')),
        throwsA(isA<DatabaseException>()),
      );

      final rows = await db.query('run_acknowledgements');
      expect(rows, hasLength(2));
    },
  );
}
