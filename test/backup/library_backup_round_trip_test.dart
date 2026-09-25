import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _tableOrder = <String, String>{
  'ingredients': 'id',
  'recipes': 'id, revision',
  'recipe_components': 'recipe_id, recipe_revision, component_id',
  'production_runs': 'id',
  'run_acknowledgements': 'run_id, warning_kind, recipe_id, component_id',
  'run_overrides': 'run_id, recipe_id, component_id',
};

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'exports and restores every persisted object from a live WAL database',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'prep-book-round-trip-',
      );
      final sourcePath = '${directory.path}/source.db';
      final targetPath = '${directory.path}/target.db';
      final source = await _open(sourcePath);
      var target = await _open(targetPath);
      addTearDown(() async {
        if (source.isOpen) await source.close();
        if (target.isOpen) await target.close();
        await directory.delete(recursive: true);
      });

      await source.rawQuery('PRAGMA journal_mode = WAL');
      await _seedCompleteLibrary(source);
      expect(await File('$sourcePath-wal').length(), greaterThan(0));
      await _seedSentinelLibrary(target);
      final initialTarget = target;
      const files = IoBackupFiles();
      final validator = BackupDatabaseValidator(factory: databaseFactoryFfi);
      const codec = BackupArchiveCodec();
      final sourceGateway = DatabaseLibraryBackupGateway(
        createSnapshot: (destinationPath) => DatabaseSnapshotter(
          connection: source,
          databasePath: sourcePath,
          files: files,
          validateCandidate: validator.validate,
        ).create(destinationPath: destinationPath),
        encodeArchive: codec.encodeFile,
        decodeArchive: codec.decodeFile,
        restoreDatabase: (_) => throw UnimplementedError(),
        files: files,
        now: () => DateTime(2026, 9, 13, 12, 34, 56),
      );

      final backup = await sourceGateway.create();
      addTearDown(backup.archive.discard);

      expect(source.isOpen, isTrue);
      expect(backup.suggestedName, 'prepbook-backup-20260913-123456.prepbook');

      late DatabaseSession session;
      Database? activated;
      session = DatabaseSession(
        connection: target,
        databasePath: targetPath,
        factory: databaseFactoryFfi,
        files: files,
        validateCandidate: validator.validate,
        activate: (connection, {required restored}) async {
          expect(restored, isTrue);
          activated = connection;
          await SqfliteIngredientRepository(connection).listAll();
          await SqfliteRecipeRepository(connection).listLatestRevisions();
          await SqfliteProductionRunRepository(connection).listSummaries();
        },
        mountRecoveryFailure: () => fail('recovery must not fail'),
      );
      final targetGateway = DatabaseLibraryBackupGateway(
        createSnapshot: (_) => throw UnimplementedError(),
        encodeArchive: codec.encodeFile,
        decodeArchive: codec.decodeFile,
        restoreDatabase: session.restore,
        files: files,
        now: DateTime.now,
      );

      await targetGateway.restore(backup.archive);
      target = session.connection;

      expect(initialTarget.isOpen, isFalse);
      expect(activated, same(target));
      expect(source.isOpen, isTrue);
      await _expectTablesEqual(source, target);
      await _expectRepositoriesEqual(source, target);

      await target.delete('ingredients', where: 'id = ?', whereArgs: ['egg']);
      await expectLater(
        _expectTablesEqual(source, target),
        throwsA(
          isA<TestFailure>().having(
            (error) => error.message,
            'message',
            contains('ingredients'),
          ),
        ),
      );

      await targetGateway.restore(backup.archive);
      target = session.connection;
      await _expectTablesEqual(source, target);
      await _expectRepositoriesEqual(source, target);
    },
  );
}

Future<Database> _open(String path) => openPrepBookDatabase(
  path: path,
  factory: databaseFactoryFfi,
  singleInstance: false,
);

Future<void> _seedCompleteLibrary(Database db) async {
  final ingredients = SqfliteIngredientRepository(db);
  final recipes = SqfliteRecipeRepository(db);
  final runs = SqfliteProductionRunRepository(db);
  final egg = Ingredient(
    id: 'egg',
    name: 'Egg',
    defaultUnit: Unit.count('egg'),
    category: 'Fresh',
  );
  final sugar = Ingredient(
    id: 'sugar',
    name: 'Sugar',
    defaultUnit: Unit.gram,
    category: 'Dry',
  );
  await ingredients.upsert(egg);
  await ingredients.upsert(sugar);

  final first = Recipe(
    id: 'cake',
    revision: 1,
    name: 'Historical cake',
    category: 'Cake',
    baseYield: Quantity.fromRational(
      Rational(BigInt.one, BigInt.from(3)),
      Unit.gram,
    ),
    preparationNotes: const ['Keep this revision'],
    modifiedAt: DateTime.utc(2026, 8, 31),
    components: [
      RecipeComponent(
        id: 'sugar',
        target: const IngredientRef('sugar'),
        baseQuantity: Quantity.parse('1', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
  );
  final current = Recipe(
    id: 'cake',
    revision: 2,
    name: 'Archived cake',
    category: 'Cake',
    baseYield: Quantity.fromRational(
      Rational(BigInt.one, BigInt.from(3)),
      Unit.gram,
    ),
    maxBatchYield: Quantity.fromRational(
      Rational(BigInt.one, BigInt.from(6)),
      Unit.gram,
    ),
    preparationNotes: const ['Mix', 'Bake'],
    modifiedAt: DateTime.utc(2026, 9),
    isArchived: true,
    components: [
      RecipeComponent(
        id: 'egg',
        target: const IngredientRef('egg'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 0,
        note: 'Adjust by hand',
      ),
      RecipeComponent(
        id: 'sugar',
        target: const IngredientRef('sugar'),
        baseQuantity: Quantity.fromRational(
          Rational(BigInt.one, BigInt.from(3)),
          Unit.gram,
        ),
        behavior: ScalingBehavior.proportional,
        rounding: RoundingRule.upToIncrement(Decimal.parse('0.1')),
        displayOrder: 1,
      ),
    ],
  );
  await recipes.saveRevision(first);
  await recipes.saveRevision(current);

  final result = const ProductionCalculator().calculate(
    recipe: current,
    targetYield: current.baseYield,
  );
  var run = ProductionRun(
    id: 'historical-run',
    createdAt: DateTime.utc(2026, 9, 2, 3, 4, 5),
    recipe: current,
    dependencySnapshot: const {},
    ingredientSnapshot: {'egg': egg, 'sugar': sugar},
    targetYield: current.baseYield,
    result: result,
  );
  for (final warning in result.warnings) {
    run = run.acknowledge(warning);
  }
  run = run.override(
    recipeId: current.id,
    componentId: 'egg',
    value: Quantity.parse('2', Unit.count('egg')),
  );
  await runs.save(run);
}

Future<void> _seedSentinelLibrary(Database db) async {
  await SqfliteIngredientRepository(db).upsert(
    Ingredient(id: 'sentinel', name: 'Sentinel', defaultUnit: Unit.gram),
  );
  await SqfliteRecipeRepository(db).saveRevision(
    Recipe(
      id: 'sentinel',
      revision: 1,
      name: 'Sentinel',
      baseYield: Quantity.parse('1', Unit.gram),
      modifiedAt: DateTime.utc(2026, 9, 13),
      components: const [],
    ),
  );
}

Future<void> _expectTablesEqual(Database source, Database restored) async {
  for (final entry in _tableOrder.entries) {
    final expected = await source.query(entry.key, orderBy: entry.value);
    final actual = await restored.query(entry.key, orderBy: entry.value);
    expect(actual, expected, reason: '${entry.key} differs after restore');
  }
}

Future<void> _expectRepositoriesEqual(
  Database source,
  Database restored,
) async {
  final sourceIngredients = SqfliteIngredientRepository(source);
  final restoredIngredients = SqfliteIngredientRepository(restored);
  expect(
    (await restoredIngredients.listAll()).map(_ingredientValue),
    (await sourceIngredients.listAll()).map(_ingredientValue),
  );

  final recipeKeys = await source.query(
    'recipes',
    columns: ['id', 'revision'],
    orderBy: 'id, revision',
  );
  final sourceRecipes = SqfliteRecipeRepository(source);
  final restoredRecipes = SqfliteRecipeRepository(restored);
  for (final key in recipeKeys) {
    final id = key['id']! as String;
    final revision = key['revision']! as int;
    expect(
      _recipeValue((await restoredRecipes.findRevision(id, revision))!),
      _recipeValue((await sourceRecipes.findRevision(id, revision))!),
      reason: 'recipe $id revision $revision differs after restore',
    );
  }

  final runIds = await source.query(
    'production_runs',
    columns: ['id'],
    orderBy: 'id',
  );
  final sourceRuns = SqfliteProductionRunRepository(source);
  final restoredRuns = SqfliteProductionRunRepository(restored);
  for (final row in runIds) {
    final id = row['id']! as String;
    expect(
      _runValue((await restoredRuns.findById(id))!),
      _runValue((await sourceRuns.findById(id))!),
      reason: 'production run $id differs after restore',
    );
  }
}

Object _ingredientValue(Ingredient value) => <String, Object?>{
  'id': value.id,
  'name': value.name,
  'defaultUnit': value.defaultUnit,
  'category': value.category,
};

Object _recipeValue(Recipe value) => <String, Object?>{
  'id': value.id,
  'revision': value.revision,
  'name': value.name,
  'category': value.category,
  'baseYield': value.baseYield,
  'maxBatchYield': value.maxBatchYield,
  'preparationNotes': value.preparationNotes,
  'modifiedAt': value.modifiedAt,
  'isArchived': value.isArchived,
  'components': [
    for (final component in value.components) _componentValue(component),
  ],
};

Object _componentValue(RecipeComponent value) => <String, Object?>{
  'id': value.id,
  'target': value.target,
  'baseQuantity': value.baseQuantity,
  'behavior': value.behavior,
  'rounding': value.rounding?.increment.toString(),
  'note': value.note,
  'displayOrder': value.displayOrder,
};

Object _runValue(ProductionRun value) => <String, Object?>{
  'id': value.id,
  'createdAt': value.createdAt,
  'recipe': _recipeValue(value.recipe),
  'dependencies': {
    for (final entry in value.dependencySnapshot.entries) entry.key: _recipeValue(entry.value),
  },
  'ingredients': {
    for (final entry in value.ingredientSnapshot.entries) entry.key: _ingredientValue(entry.value),
  },
  'targetYield': value.targetYield,
  'result': _resultValue(value.result),
  'overrides': {
    for (final entry in value.overrides.entries) '${entry.key.$1}/${entry.key.$2}': entry.value,
  },
  'acknowledgedWarnings': value.acknowledgedWarnings.map(_warningValue).toList()..sort(),
};

Object _resultValue(ProductionResult value) => <String, Object?>{
  'scaleRatio': value.scaleRatio,
  'fullBatchCount': value.batchPlan.fullBatchCount,
  'fullBatchYield': value.batchPlan.fullBatchYield,
  'remainderYield': value.batchPlan.remainderYield,
  'components': [
    for (final component in value.components) _scaledValue(component),
  ],
  'warnings': value.warnings.map(_warningValue).toList(),
};

Object _scaledValue(ScaledComponent value) => <String, Object?>{
  'source': _componentValue(value.source),
  'total': _scaledQuantityValue(value.total),
  'perBatch': value.perBatch.map(_scaledQuantityValue).toList(),
  'subRecipe': value.subRecipe == null ? null : _resultValue(value.subRecipe!),
};

Object? _scaledQuantityValue(ScaledQuantity? value) =>
    value == null ? null : <String, Object?>{'exact': value.exact, 'displayed': value.displayed};

String _warningValue(ProductionWarning value) => switch (value) {
  ManualComponentWarning(:final recipeId, :final componentId) => 'manual:$recipeId:$componentId',
  RoundingAdjustedWarning(:final recipeId, :final componentId) => 'rounding:$recipeId:$componentId',
  ArchivedDependencyWarning(:final recipeId) => 'archived:$recipeId',
};
