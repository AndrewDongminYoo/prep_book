import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A stand-in for the first real upgrade: it adds a column to an existing
/// table, which is the shape almost every schema upgrade takes and the one
/// that can lose rows if applied wrongly.
const _fakeUpgradeToTwo = <int, List<String>>{
  2: ['ALTER TABLE ingredients ADD COLUMN storage_location TEXT'],
};

/// Two registered versions, so the harness can prove they run in ascending
/// order rather than in map order.
const _fakeUpgradeToThree = <int, List<String>>{
  2: ['ALTER TABLE ingredients ADD COLUMN storage_location TEXT'],
  3: ['ALTER TABLE ingredients RENAME COLUMN storage_location TO shelf'],
};

/// A registered version 3 with no version 2, which is not a shape the real
/// map may ever have — it exists to reach the empty-statement-list fallback
/// that carries the loop past an unregistered version.
const _fakeUpgradeWithAGap = <int, List<String>>{
  3: ['ALTER TABLE ingredients ADD COLUMN shelf TEXT'],
};

void main() {
  setUpAll(sqfliteFfiInit);

  Future<Database> openAtVersionOne() async {
    final db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);
    await db.insert('ingredients', <String, Object?>{
      'id': 'flour',
      'name': 'Flour',
      'default_unit': 'g',
      'category': null,
    });
    return db;
  }

  Future<Set<String>> columnsOfIngredients(Database db) async {
    final rows = await db.rawQuery('PRAGMA table_info(ingredients)');
    return rows.map((row) => row['name']! as String).toSet();
  }

  // The count is the half of this that is not vacuous. `everyElement` over
  // an empty map passes without reading anything, which is exactly how the
  // previous version of this test managed to assert nothing at all: its
  // loop body never ran. `schemaUpgrades` must hold one entry per version
  // above 1, so at version 1 it must be empty and at version N it must hold
  // N - 1 entries — a claim that fails if an upgrade is registered without
  // bumping the version, or the version is bumped without an upgrade.
  test('every registered upgrade is reachable from version 1', () {
    expect(
      schemaUpgrades.keys,
      everyElement(
        allOf(greaterThan(1), lessThanOrEqualTo(currentSchemaVersion)),
      ),
    );
    expect(schemaUpgrades, hasLength(currentSchemaVersion - 1));
  });

  // The harness the specification asks for: a database at an older version,
  // the upgrade path applied over it, and both the resulting shape and the
  // survival of the existing rows asserted. It runs against an injected
  // upgrade map because the real one is empty until schema version 2 —
  // building it now is the point, so that the session which writes the first
  // upgrade does not have to write its means of verification at the same
  // time.
  test('an upgrade changes the shape and keeps the existing rows', () async {
    final db = await openAtVersionOne();
    expect(await columnsOfIngredients(db), isNot(contains('storage_location')));

    await applySchemaUpgrades(db, 1, 2, upgrades: _fakeUpgradeToTwo);

    expect(await columnsOfIngredients(db), contains('storage_location'));
    final rows = await db.query('ingredients');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'flour');
    expect(rows.single['name'], 'Flour');
    expect(rows.single['storage_location'], isNull);
  });

  // Ordering, not just application: version 3 renames the column version 2
  // adds, so running them in the wrong order fails on a column that does
  // not exist yet rather than quietly producing the same result.
  test('two upgrades apply in ascending version order', () async {
    final db = await openAtVersionOne();

    await applySchemaUpgrades(db, 1, 3, upgrades: _fakeUpgradeToThree);

    final columns = await columnsOfIngredients(db);
    expect(columns, contains('shelf'));
    expect(columns, isNot(contains('storage_location')));
    expect((await db.query('ingredients')).single['id'], 'flour');
  });

  test('a version with no registered statements is stepped over', () async {
    final db = await openAtVersionOne();

    await applySchemaUpgrades(db, 1, 3, upgrades: _fakeUpgradeWithAGap);

    expect(await columnsOfIngredients(db), contains('shelf'));
  });

  test('an upgrade path that spans no versions changes nothing', () async {
    final db = await openAtVersionOne();
    final before = await columnsOfIngredients(db);

    await applySchemaUpgrades(db, 1, 1, upgrades: _fakeUpgradeToTwo);

    expect(await columnsOfIngredients(db), before);
  });

  test('applying the real upgrade path preserves existing rows', () async {
    const path = inMemoryDatabasePath;
    final db = await openPrepBookDatabase(
      path: path,
      factory: databaseFactoryFfi,
    );
    await db.insert('ingredients', <String, Object?>{
      'id': 'flour',
      'name': 'Flour',
      'default_unit': 'g',
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
