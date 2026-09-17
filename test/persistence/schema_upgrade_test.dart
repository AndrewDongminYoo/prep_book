import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/schema/v1.dart';
import 'package:prep_book/persistence/schema/v2.dart';
import 'package:prep_book/persistence/sqflite/production_run_repository.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';
import 'package:prep_book/persistence/sqflite/result_codec.dart';
import 'package:prep_book/persistence/sqflite/timestamps.dart';
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

  Future<Database> createVersionOne(String path) => databaseFactoryFfi.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        for (final statement in schemaV1Statements) {
          await db.execute(statement);
        }
      },
    ),
  );

  ProductionRun legacyDraft() {
    final recipe = Recipe(
      id: 'legacy-recipe',
      revision: 3,
      name: 'Legacy morning rolls',
      baseYield: Quantity.parse('12', Unit.count('roll')),
      modifiedAt: DateTime.utc(2026, 9),
      components: [
        RecipeComponent(
          id: 'finish',
          target: const IngredientRef('finish'),
          baseQuantity: null,
          behavior: ScalingBehavior.manual,
          displayOrder: 0,
        ),
      ],
    );
    return ProductionRun(
      id: 'legacy-run',
      createdAt: DateTime.utc(2026, 9, 15, 23),
      recipe: recipe,
      dependencySnapshot: const {},
      targetYield: recipe.baseYield,
      result: const ProductionCalculator().calculate(
        recipe: recipe,
        targetYield: recipe.baseYield,
      ),
    );
  }

  Future<void> insertVersionOneRun(Database db, ProductionRun run) => db.insert('production_runs', <String, Object?>{
    'id': run.id,
    'recipe_id': run.recipeId,
    'recipe_revision': run.recipeRevision,
    ...quantityToColumns(run.targetYield, 'target'),
    'created_at': timestampToStorage(run.createdAt),
    'result_json': encodeRunPayload(run),
  });

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

  // The count prevents `everyElement` from passing vacuously over an empty map.
  // `schemaUpgrades` must hold one entry per version above 1, so at version N it must hold N - 1 entries.
  test('every registered upgrade is reachable from version 1', () {
    expect(
      schemaUpgrades.keys,
      everyElement(
        allOf(greaterThan(1), lessThanOrEqualTo(currentSchemaVersion)),
      ),
    );
    expect(schemaUpgrades, hasLength(currentSchemaVersion - 1));
  });

  // An injected upgrade isolates the generic upgrade runner from the production schema change.
  // The test covers the resulting shape and the survival of existing rows.
  test('an upgrade changes the shape and keeps the existing rows', () async {
    final db = await openAtVersionOne();
    expect(await columnsOfIngredients(db), isNot(contains('storage_location')));

    await applySchemaUpgrades(
      db,
      1,
      2,
      upgrades: _fakeUpgradeToTwo,
      backfills: const {},
    );

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

    await applySchemaUpgrades(
      db,
      1,
      3,
      upgrades: _fakeUpgradeToThree,
      backfills: const {},
    );

    final columns = await columnsOfIngredients(db);
    expect(columns, contains('shelf'));
    expect(columns, isNot(contains('storage_location')));
    expect((await db.query('ingredients')).single['id'], 'flour');
  });

  test('a version with no registered statements is stepped over', () async {
    final db = await openAtVersionOne();

    await applySchemaUpgrades(
      db,
      1,
      3,
      upgrades: _fakeUpgradeWithAGap,
      backfills: const {},
    );

    expect(await columnsOfIngredients(db), contains('shelf'));
  });

  // The create path, at a version it cannot be driven to through
  // [openPrepBookDatabase], which hardcodes `version: currentSchemaVersion`.
  //
  // sqflite calls `onCreate` — not `onUpgrade` — for a brand-new database,
  // then stamps it at the version the open asked for. `upgradeRan` asserts
  // that directly rather than taking it on trust: a create path that stopped
  // at the version 1 statements would leave this database holding only the
  // version 1 tables while `getVersion` reports 2, and every later open
  // would find it current. The fake upgrade adds a column, so the assertion
  // is on something version 1 alone cannot produce.
  test('a create above version 1 applies the upgrades too', () async {
    var upgradeRan = false;
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, version) => createPrepBookSchema(
          db,
          version,
          upgrades: _fakeUpgradeToTwo,
          backfills: const {},
        ),
        onUpgrade: (db, from, to) {
          upgradeRan = true;
          return applySchemaUpgrades(
            db,
            from,
            to,
            upgrades: _fakeUpgradeToTwo,
            backfills: const {},
          );
        },
      ),
    );
    addTearDown(db.close);

    expect(upgradeRan, isFalse);
    expect(await db.getVersion(), 2);
    expect(await columnsOfIngredients(db), contains('storage_location'));
  });

  test('an upgrade path that spans no versions changes nothing', () async {
    final db = await openAtVersionOne();
    final before = await columnsOfIngredients(db);

    await applySchemaUpgrades(
      db,
      1,
      1,
      upgrades: _fakeUpgradeToTwo,
      backfills: const {},
    );

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

  test(
    'the real version 1 upgrade backfills production history metadata',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'prep-book-schema-upgrade-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/library.db';
      final versionOne = await createVersionOne(path);
      await insertVersionOneRun(versionOne, legacyDraft());
      await versionOne.insert('run_acknowledgements', <String, Object?>{
        'run_id': 'legacy-run',
        'warning_kind': 'manual_component',
        'recipe_id': 'legacy-recipe',
        'component_id': 'finish',
      });
      await versionOne.close();

      final upgraded = await openPrepBookDatabase(
        path: path,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      addTearDown(upgraded.close);

      expect(await upgraded.getVersion(), 2);
      final columns = await upgraded.rawQuery(
        'PRAGMA table_info(production_runs)',
      );
      expect(columns.map((row) => row['name']), contains('recipe_name'));
      expect(
        columns.map((row) => row['name']),
        contains('blocking_warning_count'),
      );
      final summary = (await SqfliteProductionRunRepository(
        upgraded,
      ).listSummaries()).single;
      expect(summary.recipeName, 'Legacy morning rolls');
      expect(summary.isDraft, isFalse);
    },
  );

  for (final acknowledgement in <({String kind, String recipeId, String? componentId})>[
    (
      kind: 'manual_component',
      recipeId: 'legacy-recipe',
      componentId: 'not-a-stored-warning',
    ),
    (
      kind: 'archived_dependency',
      recipeId: 'not-a-stored-warning',
      componentId: null,
    ),
  ]) {
    test('a version 1 ${acknowledgement.kind} acknowledgement absent from its '
        'run aborts the upgrade', () async {
      final directory = await Directory.systemTemp.createTemp(
        'prep-book-schema-acknowledgement-upgrade-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final path = '${directory.path}/library.db';
      final versionOne = await createVersionOne(path);
      await insertVersionOneRun(versionOne, legacyDraft());
      await versionOne.insert('run_acknowledgements', <String, Object?>{
        'run_id': 'legacy-run',
        'warning_kind': acknowledgement.kind,
        'recipe_id': acknowledgement.recipeId,
        'component_id': acknowledgement.componentId,
      });
      await versionOne.close();

      await expectLater(
        openPrepBookDatabase(
          path: path,
          factory: databaseFactoryFfi,
          singleInstance: false,
        ),
        throwsA(isA<CorruptDatabaseError>()),
      );

      final unchanged = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      addTearDown(unchanged.close);
      expect(await unchanged.getVersion(), 1);
      expect(await unchanged.query('run_acknowledgements'), hasLength(1));
    });
  }

  test('metadata backfill reports a run removed during its update', () async {
    final db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);
    await SqfliteProductionRunRepository(db).save(legacyDraft());
    await db.execute('''
CREATE TRIGGER delete_run_before_metadata_update
BEFORE UPDATE OF recipe_name ON production_runs
BEGIN
  DELETE FROM production_runs WHERE id = OLD.id;
END
''');

    await expectLater(
      backfillProductionRunSummaryMetadata(db),
      throwsStateError,
    );
  });

  test('a corrupt version 1 payload rolls back the whole upgrade', () async {
    final directory = await Directory.systemTemp.createTemp(
      'prep-book-schema-corrupt-upgrade-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/library.db';
    final versionOne = await createVersionOne(path);
    await insertVersionOneRun(versionOne, legacyDraft());
    final validRow = (await versionOne.query('production_runs')).single;
    await versionOne.insert('production_runs', <String, Object?>{
      ...validRow,
      'id': 'zz-corrupt-run',
      'result_json': '{not valid json',
    });
    await versionOne.close();

    await expectLater(
      openPrepBookDatabase(
        path: path,
        factory: databaseFactoryFfi,
        singleInstance: false,
      ),
      throwsA(isA<CorruptDatabaseError>()),
    );

    final unchanged = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    addTearDown(unchanged.close);
    expect(await unchanged.getVersion(), 1);
    final columns = await unchanged.rawQuery(
      'PRAGMA table_info(production_runs)',
    );
    expect(columns.map((row) => row['name']), isNot(contains('recipe_name')));
    expect(
      columns.map((row) => row['name']),
      isNot(contains('blocking_warning_count')),
    );
    expect(await unchanged.query('production_runs'), hasLength(2));
  });

  test(
    'fresh and upgraded databases have the same application catalog',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'prep-book-schema-catalog-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final upgradedPath = '${directory.path}/upgraded.db';
      final versionOne = await createVersionOne(upgradedPath);
      await versionOne.close();
      final upgraded = await openPrepBookDatabase(
        path: upgradedPath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      addTearDown(upgraded.close);
      final fresh = await openPrepBookDatabase(
        path: '${directory.path}/fresh.db',
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      addTearDown(fresh.close);

      Future<Map<String, String>> catalog(Database db) async => {
        for (final row in await db.query(
          'sqlite_master',
          columns: ['name', 'sql'],
          where: "name NOT LIKE 'sqlite_%'",
        ))
          row['name']! as String: (row['sql']! as String).trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase(),
      };

      final upgradedCatalog = await catalog(upgraded);
      final freshCatalog = await catalog(fresh);
      expect(upgradedCatalog, freshCatalog);
      expect(
        upgradedCatalog['production_runs'],
        allOf(contains('recipe_name'), contains('blocking_warning_count')),
      );
      await validatePrepBookSchema(upgraded);
      await validatePrepBookSchema(fresh);
    },
  );
}
