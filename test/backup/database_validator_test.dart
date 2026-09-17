import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:prep_book/persistence/schema/v1.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory directory;
  late BackupDatabaseValidator validator;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prep-book-validator-');
    validator = BackupDatabaseValidator(factory: databaseFactoryFfi);
  });

  tearDown(() => directory.delete(recursive: true));

  test('rejects schema zero without creating or upgrading tables', () async {
    final candidatePath = await _createRawDatabase(directory, userVersion: 0);

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: 1,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );

    final db = await databaseFactoryFfi.openDatabase(
      candidatePath,
      options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
    );
    addTearDown(db.close);
    expect(await db.getVersion(), 0);
    expect(
      await db.query('sqlite_master', where: 'type = ?', whereArgs: ['table']),
      isEmpty,
    );
  });

  test(
    'rejects a schema newer than this build before opening normally',
    () async {
      final candidatePath = await _createRawDatabase(
        directory,
        userVersion: currentSchemaVersion + 1,
      );

      await expectLater(
        validator.validate(
          candidatePath: candidatePath,
          manifestSchemaVersion: currentSchemaVersion + 1,
        ),
        throwsA(_failureKind(LibraryBackupFailureKind.incompatibleSchema)),
      );

      final db = await databaseFactoryFfi.openDatabase(
        candidatePath,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      addTearDown(db.close);
      expect(await db.getVersion(), currentSchemaVersion + 1);
    },
  );

  test('rejects a manifest and database schema mismatch', () async {
    final candidatePath = await _createRawDatabase(directory, userVersion: 0);

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('accepts an empty database at the current schema', () async {
    final candidatePath = '${directory.path}/valid.db';
    final db = await openPrepBookDatabase(
      path: candidatePath,
      factory: databaseFactoryFfi,
      singleInstance: false,
    );
    await db.close();

    await validator.validate(
      candidatePath: candidatePath,
      manifestSchemaVersion: currentSchemaVersion,
    );
  });

  test('upgrades and validates a version 1 backup candidate', () async {
    final candidatePath = await _createRawDatabase(directory, userVersion: 1);
    final db = await databaseFactoryFfi.openDatabase(
      candidatePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    for (final statement in schemaV1Statements) {
      await db.execute(statement);
    }
    await db.close();

    await validator.validate(
      candidatePath: candidatePath,
      manifestSchemaVersion: 1,
    );

    final upgraded = await databaseFactoryFfi.openDatabase(
      candidatePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    addTearDown(upgraded.close);
    expect(await upgraded.getVersion(), currentSchemaVersion);
    await validatePrepBookSchema(upgraded);
  });

  test('rejects a current-version catalog missing migrated columns', () async {
    final candidatePath = await _createRawDatabase(
      directory,
      userVersion: currentSchemaVersion,
    );
    final db = await databaseFactoryFfi.openDatabase(
      candidatePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    for (final statement in schemaV1Statements) {
      await db.execute(statement);
    }
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('rejects an altered migrated column', () async {
    final candidatePath = '${directory.path}/altered-v2.db';
    final db = await _openCandidate(candidatePath);
    await db.execute(
      'ALTER TABLE production_runs RENAME COLUMN recipe_name TO old_name',
    );
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('rejects an incomplete database at the current schema', () async {
    final candidatePath = await _createRawDatabase(
      directory,
      userVersion: currentSchemaVersion,
    );
    final db = await databaseFactoryFfi.openDatabase(
      candidatePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    for (final statement in const [
      'CREATE TABLE ingredients (id TEXT PRIMARY KEY)',
      'CREATE TABLE recipes (id TEXT, revision INTEGER)',
      'CREATE TABLE production_runs (id TEXT PRIMARY KEY)',
    ]) {
      await db.execute(statement);
    }
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('rejects an unexpected schema object', () async {
    final candidatePath = '${directory.path}/unexpected-trigger.db';
    final db = await _openCandidate(candidatePath);
    await db.execute('''
CREATE TRIGGER unexpected_ingredient_trigger
AFTER INSERT ON ingredients
BEGIN
  SELECT 1;
END
''');
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('allows the Android-maintained locale metadata table', () async {
    final candidatePath = '${directory.path}/android-metadata.db';
    final db = await _openCandidate(candidatePath);
    await db.execute('CREATE TABLE android_metadata (locale TEXT)');
    await db.insert('android_metadata', {'locale': 'en_US'});
    await db.close();

    await validator.validate(
      candidatePath: candidatePath,
      manifestSchemaVersion: currentSchemaVersion,
    );
  });

  test('rejects a trigger named like the Android metadata table', () async {
    final candidatePath = '${directory.path}/metadata-trigger.db';
    final db = await _openCandidate(candidatePath);
    await db.execute('''
CREATE TRIGGER android_metadata
AFTER INSERT ON ingredients
BEGIN
  DELETE FROM ingredients;
END
''');
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('rejects a malformed Android metadata table', () async {
    final candidatePath = '${directory.path}/malformed-metadata.db';
    final db = await _openCandidate(candidatePath);
    await db.execute(
      'CREATE TABLE android_metadata (locale TEXT, payload TEXT)',
    );
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('accepts every stored object kind through real repositories', () async {
    final candidatePath = '${directory.path}/complete.db';
    final db = await _openCandidate(candidatePath);
    final ingredients = SqfliteIngredientRepository(db);
    final recipes = SqfliteRecipeRepository(db);
    final runs = SqfliteProductionRunRepository(db);
    await ingredients.upsert(
      Ingredient(id: 'egg', name: 'Egg', defaultUnit: Unit.count('egg')),
    );
    await recipes.saveRevision(
      _recipe(
        id: 'cake',
        revision: 1,
        baseYield: Quantity.fromRational(
          Rational(BigInt.one, BigInt.from(3)),
          Unit.gram,
        ),
      ),
    );
    final current = _recipe(
      id: 'cake',
      revision: 2,
      isArchived: true,
      components: [
        RecipeComponent(
          id: 'garnish',
          target: const IngredientRef('egg'),
          baseQuantity: null,
          behavior: ScalingBehavior.manual,
          displayOrder: 0,
        ),
      ],
    );
    await recipes.saveRevision(current);
    final result = const ProductionCalculator().calculate(
      recipe: current,
      targetYield: current.baseYield,
    );
    var run = ProductionRun(
      id: 'run-1',
      createdAt: DateTime.utc(2026, 9, 13),
      recipe: current,
      dependencySnapshot: const {},
      ingredientSnapshot: {
        'egg': Ingredient(
          id: 'egg',
          name: 'Egg',
          defaultUnit: Unit.count('egg'),
        ),
      },
      targetYield: current.baseYield,
      result: result,
    );
    for (final warning in result.warnings) {
      run = run.acknowledge(warning);
    }
    run = run.override(
      recipeId: 'cake',
      componentId: 'garnish',
      value: Quantity.parse('2', Unit.count('egg')),
    );
    await runs.save(run);
    await db.close();

    await validator.validate(
      candidatePath: candidatePath,
      manifestSchemaVersion: currentSchemaVersion,
    );
  });

  test('rejects a corrupt ingredient row', () async {
    final candidatePath = '${directory.path}/bad-ingredient.db';
    final db = await _openCandidate(candidatePath);
    final ingredients = SqfliteIngredientRepository(db);
    await ingredients.upsert(
      Ingredient(id: 'good', name: 'Good', defaultUnit: Unit.gram),
    );
    await ingredients.upsert(
      Ingredient(id: 'bad', name: 'Bad', defaultUnit: Unit.gram),
    );
    await db.update(
      'ingredients',
      {'default_unit': 'not-a-unit'},
      where: 'id = ?',
      whereArgs: ['bad'],
    );
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('rejects corruption in an old recipe revision', () async {
    final candidatePath = '${directory.path}/bad-recipe.db';
    final db = await _openCandidate(candidatePath);
    final recipes = SqfliteRecipeRepository(db);
    await recipes.saveRevision(_recipe(id: 'cake', revision: 1));
    await recipes.saveRevision(_recipe(id: 'cake', revision: 2));
    await db.update(
      'recipes',
      {'base_yield_unit': 'not-a-unit'},
      where: 'id = ? AND revision = ?',
      whereArgs: ['cake', 1],
    );
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('rejects corruption in an old production run', () async {
    final candidatePath = '${directory.path}/bad-run.db';
    final db = await _openCandidate(candidatePath);
    final runs = SqfliteProductionRunRepository(db);
    await runs.save(_run(id: 'old', createdAt: DateTime.utc(2026, 9, 12)));
    await runs.save(_run(id: 'new', createdAt: DateTime.utc(2026, 9, 13)));
    await db.update(
      'production_runs',
      {'result_json': '{'},
      where: 'id = ?',
      whereArgs: ['old'],
    );
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('rejects a foreign key violation', () async {
    final candidatePath = '${directory.path}/bad-foreign-key.db';
    final db = await _openCandidate(candidatePath);
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('run_acknowledgements', {
      'run_id': 'missing-run',
      'warning_kind': 'manualComponent',
      'recipe_id': 'cake',
      'component_id': 'garnish',
    });
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('rejects a database whose SQLite integrity check is not ok', () async {
    final candidatePath = '${directory.path}/bad-integrity.db';
    final db = await _openCandidate(candidatePath);
    await db.execute('PRAGMA writable_schema = ON');
    await db.update(
      'sqlite_master',
      {'rootpage': 999999},
      where: 'type = ? AND name = ?',
      whereArgs: ['table', 'ingredients'],
    );
    await db.execute('PRAGMA writable_schema = OFF');
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(
        isA<LibraryBackupException>()
            .having(
              (error) => error.kind,
              'kind',
              LibraryBackupFailureKind.invalidDatabase,
            )
            .having(
              (error) => error.cause.toString(),
              'diagnostic cause',
              contains('PRAGMA integrity_check'),
            ),
      ),
    );
  });

  test('rejects a cycle between latest recipe revisions', () async {
    final candidatePath = '${directory.path}/cycle.db';
    final db = await _openCandidate(candidatePath);
    final recipes = SqfliteRecipeRepository(db);
    await recipes.saveRevision(_recipe(id: 'a', revision: 1, subRecipeId: 'b'));
    await recipes.saveRevision(_recipe(id: 'b', revision: 1, subRecipeId: 'a'));
    await db.close();

    await expectLater(
      validator.validate(
        candidatePath: candidatePath,
        manifestSchemaVersion: currentSchemaVersion,
      ),
      throwsA(_failureKind(LibraryBackupFailureKind.invalidDatabase)),
    );
  });

  test('accepts missing ingredient and sub-recipe references', () async {
    final candidatePath = '${directory.path}/dangling.db';
    final db = await _openCandidate(candidatePath);
    final recipes = SqfliteRecipeRepository(db);
    await recipes.saveRevision(
      _recipe(
        id: 'cake',
        revision: 1,
        components: [
          RecipeComponent(
            id: 'missing-ingredient',
            target: const IngredientRef('missing-ingredient'),
            baseQuantity: Quantity.parse('1', Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
          RecipeComponent(
            id: 'missing-recipe',
            target: const SubRecipeRef('missing-recipe'),
            baseQuantity: Quantity.parse('1', Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 1,
          ),
        ],
      ),
    );
    await db.close();

    await validator.validate(
      candidatePath: candidatePath,
      manifestSchemaVersion: currentSchemaVersion,
    );
  });
}

Future<Database> _openCandidate(String candidatePath) => openPrepBookDatabase(
  path: candidatePath,
  factory: databaseFactoryFfi,
  singleInstance: false,
);

Recipe _recipe({
  required String id,
  required int revision,
  Quantity? baseYield,
  List<RecipeComponent>? components,
  String? subRecipeId,
  bool isArchived = false,
}) => Recipe(
  id: id,
  revision: revision,
  name: 'Recipe $id revision $revision',
  baseYield: baseYield ?? Quantity.parse('100', Unit.gram),
  modifiedAt: DateTime.utc(2026, 9, 13),
  isArchived: isArchived,
  components:
      components ??
      [
        RecipeComponent(
          id: subRecipeId == null ? 'flour' : 'sub-$subRecipeId',
          target: subRecipeId == null ? const IngredientRef('flour') : SubRecipeRef(subRecipeId),
          baseQuantity: Quantity.parse('1', Unit.gram),
          behavior: ScalingBehavior.proportional,
          displayOrder: 0,
        ),
      ],
);

ProductionRun _run({required String id, required DateTime createdAt}) {
  final recipe = _recipe(id: 'run-recipe', revision: 1);
  final result = const ProductionCalculator().calculate(
    recipe: recipe,
    targetYield: recipe.baseYield,
  );
  return ProductionRun(
    id: id,
    createdAt: createdAt,
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: recipe.baseYield,
    result: result,
  );
}

Future<String> _createRawDatabase(
  Directory directory, {
  required int userVersion,
}) async {
  final candidatePath = '${directory.path}/raw-$userVersion.db';
  final db = await databaseFactoryFfi.openDatabase(
    candidatePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute('PRAGMA user_version = $userVersion');
  await db.close();
  return candidatePath;
}

Matcher _failureKind(LibraryBackupFailureKind kind) =>
    isA<LibraryBackupException>().having((error) => error.kind, 'kind', kind);
