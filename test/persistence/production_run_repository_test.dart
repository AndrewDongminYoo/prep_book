import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/production_run_repository.dart';
import 'package:prep_book/persistence/sqflite/recipe_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A one-component recipe, scaled 1:1 by default — enough for a plain
/// save/load round trip. Built independently of
/// `recipe_repository_test.dart`'s own `buildRecipe`, matching this suite's
/// existing convention of keeping each test file's fixtures self-contained.
Recipe buildRecipe({
  required String id,
  required int revision,
  String name = 'Test recipe',
}) => Recipe(
  id: id,
  revision: revision,
  name: name,
  baseYield: Quantity.parse('1000', Unit.gram),
  modifiedAt: DateTime.utc(2026, 9, 7),
  components: [
    RecipeComponent(
      id: 'flour',
      target: const IngredientRef('flour'),
      baseQuantity: Quantity.parse('500', Unit.gram),
      behavior: ScalingBehavior.proportional,
      displayOrder: 0,
    ),
  ],
);

/// A run computed from [buildRecipe], scaled 1:1 so its result carries no
/// warnings.
ProductionRun buildRun({
  required String id,
  String recipeId = 'r',
  int recipeRevision = 1,
  DateTime? createdAt,
}) {
  final recipe = buildRecipe(id: recipeId, revision: recipeRevision);
  final targetYield = recipe.baseYield;
  final result = const ProductionCalculator().calculate(
    recipe: recipe,
    targetYield: targetYield,
  );
  return ProductionRun(
    id: id,
    createdAt: createdAt ?? DateTime.utc(2026, 9, 7),
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: targetYield,
    result: result,
  );
}

/// A recipe whose calculated result carries one warning of each of the
/// three kinds. Mirrors `test/persistence/result_codec_test.dart`'s
/// `buildRunWithAllWarningKinds`, built independently here for the same
/// self-containment reason as [buildRecipe] above.
Recipe _buildRecipeWithAllWarningKinds({required String id}) => Recipe(
  id: id,
  revision: 1,
  name: 'Cake',
  baseYield: Quantity.parse('2', Unit.kilogram),
  modifiedAt: DateTime.utc(2026, 9, 7),
  isArchived: true,
  components: [
    RecipeComponent(
      id: 'eggs',
      target: const IngredientRef('egg'),
      baseQuantity: null,
      behavior: ScalingBehavior.manual,
      displayOrder: 0,
    ),
    RecipeComponent(
      id: 'sugar',
      target: const IngredientRef('sugar'),
      baseQuantity: Quantity.parse('333', Unit.gram),
      behavior: ScalingBehavior.proportional,
      displayOrder: 1,
      rounding: RoundingRule.upToIncrement(Decimal.parse('50')),
    ),
  ],
);

/// A run with all three of its warnings acknowledged, so saving it exercises
/// every `_acknowledgementRow`/`_warningFromRow` kind in one round trip.
ProductionRun buildRunWithAcknowledgement({required String id}) {
  final recipe = _buildRecipeWithAllWarningKinds(id: 'cake');
  final targetYield = recipe.baseYield;
  final result = const ProductionCalculator().calculate(
    recipe: recipe,
    targetYield: targetYield,
  );
  var run = ProductionRun(
    id: id,
    createdAt: DateTime.utc(2026, 9, 7),
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: targetYield,
    result: result,
  );
  for (final warning in result.warnings) {
    run = run.acknowledge(warning);
  }
  return run;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late SqfliteProductionRunRepository repository;
  late SqfliteRecipeRepository recipes;

  setUp(() async {
    db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repository = SqfliteProductionRunRepository(db);
    recipes = SqfliteRecipeRepository(db);
  });

  tearDown(() => db.close());

  // `Recipe` and `ProductionResult` have no `operator ==` (see
  // `result_codec_test.dart`), so `expect(loaded!.result, run.result)` and
  // `expect(loaded.recipe, run.recipe)`, taken literally from the brief,
  // would always fail on identity against a freshly decoded object. The
  // codec's own round trip is already exhaustively verified field by field
  // in `result_codec_test.dart`; this test instead checks the fields that
  // matter for "did save-then-load wire the row and the payload together
  // correctly" without re-deriving that suite.
  test('a saved run round-trips', () async {
    final run = buildRun(id: 'run-1');
    await repository.save(run);

    final loaded = await repository.findById('run-1');
    expect(loaded, isNotNull);
    expect(loaded!.id, run.id);
    expect(loaded.createdAt, run.createdAt);
    expect(loaded.recipe.id, run.recipe.id);
    expect(loaded.recipe.revision, run.recipe.revision);
    expect(loaded.recipe.name, run.recipe.name);
    expect(loaded.targetYield, run.targetYield);
    expect(loaded.result.scaleRatio, run.result.scaleRatio);
    expect(loaded.result.warnings, run.result.warnings);
    expect(loaded.acknowledgedWarnings, run.acknowledgedWarnings);
    expect(loaded.overrides, run.overrides);
  });

  // A run must not seed the `recipes` table for this test to mean anything:
  // if revision 1 of 'r' never existed there, `saveRevision(revision: 2,
  // name: 'Changed')` mutates nothing the run could accidentally read
  // through, and the assertion below would pass even against an
  // implementation that re-read the recipe live. Seeding revision 1 first,
  // and asserting the edit really landed in `recipes`, closes that gap.
  test(
    'editing the recipe afterwards does not change the stored run',
    () async {
      await recipes.saveRevision(buildRecipe(id: 'r', revision: 1));
      final run = buildRun(id: 'run-1');
      await repository.save(run);

      await recipes.saveRevision(
        buildRecipe(id: 'r', revision: 2, name: 'Changed'),
      );
      expect((await recipes.findLatest('r'))!.name, 'Changed');

      final loaded = await repository.findById('run-1');
      expect(loaded!.recipe.name, run.recipe.name);
      expect(loaded.recipe.revision, 1);
    },
  );

  // Same fixture-can-produce-the-state concern as the edit test above:
  // `setArchived` on a nonexistent row updates nothing, so this seeds
  // revision 1 first and confirms the archive actually took effect in
  // `recipes` before checking the stored run never saw it.
  test('archiving the recipe does not change the stored run', () async {
    await recipes.saveRevision(buildRecipe(id: 'r', revision: 1));
    final run = buildRun(id: 'run-1');
    await repository.save(run);

    await recipes.setArchived('r', isArchived: true);
    expect((await recipes.findLatest('r'))!.isArchived, isTrue);

    expect((await repository.findById('run-1'))!.recipe.isArchived, isFalse);
  });

  // `RecipeRepository` exposes no delete method — the design document only
  // asks that editing, archiving, *or deleting* the source recipe never
  // change a stored run, so this reaches the table directly to cover the
  // third case.
  test('deleting the recipe does not change the stored run', () async {
    await recipes.saveRevision(buildRecipe(id: 'r', revision: 1));
    final run = buildRun(id: 'run-1');
    await repository.save(run);

    await db.delete('recipes', where: 'id = ?', whereArgs: ['r']);
    expect(await recipes.findLatest('r'), isNull);

    final loaded = await repository.findById('run-1');
    expect(loaded!.recipe.name, run.recipe.name);
    expect(loaded.recipe.revision, run.recipe.revision);
  });

  test('summaries come back newest first without loading results', () async {
    await repository.save(buildRun(id: 'old', createdAt: DateTime.utc(2026)));
    await repository.save(
      buildRun(id: 'new', createdAt: DateTime.utc(2026, 6)),
    );

    final summaries = await repository.listSummaries();
    expect(summaries.map((s) => s.id), ['new', 'old']);
  });

  // Proves `listSummaries` never reaches `result_json`: `decodeRunPayload`
  // would throw `CorruptDatabaseError` on this row (see
  // `result_codec_test.dart`'s own "malformed json" case), so a passing
  // `listSummaries` here — while `findById`, which does decode the payload,
  // fails on the very same row — shows the summary query only ever touched
  // the metadata columns.
  test('listSummaries does not decode a corrupt result_json', () async {
    await repository.save(buildRun(id: 'run-1'));
    await db.update(
      'production_runs',
      {'result_json': '{not valid json'},
      where: 'id = ?',
      whereArgs: ['run-1'],
    );

    final summaries = await repository.listSummaries();
    expect(summaries.single.id, 'run-1');

    await expectLater(
      repository.findById('run-1'),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test(
    'saving a run commits its acknowledgements in the same transaction',
    () async {
      final run = buildRunWithAcknowledgement(id: 'run-1');
      await repository.save(run);

      final loaded = await repository.findById('run-1');
      expect(loaded!.acknowledgedWarnings, run.acknowledgedWarnings);
      expect(loaded.acknowledgedWarnings, hasLength(3));
    },
  );

  // The test above only proves the acknowledgements come back — it would
  // pass identically against a `save` that ran three untransacted writes.
  // This proves the "one transaction" half of the guarantee: a colliding
  // acknowledgement plant (same shape `recipe_repository_test.dart:91` uses
  // for a colliding component) makes the acknowledgement insert abort on
  // `run_acknowledgements`'s partial unique index, and the whole `save` —
  // including the `production_runs` row already inserted earlier in the
  // same transaction — must roll back with it.
  test(
    'a colliding acknowledgement rolls back the whole save',
    () async {
      await db.execute('PRAGMA foreign_keys = OFF');
      await db.insert('run_acknowledgements', <String, Object?>{
        'run_id': 'run-1',
        'warning_kind': 'manual_component',
        'recipe_id': 'cake',
        'component_id': 'eggs',
      });
      await db.execute('PRAGMA foreign_keys = ON');

      final run = buildRunWithAcknowledgement(id: 'run-1');
      await expectLater(repository.save(run), throwsA(anything));

      expect(await repository.findById('run-1'), isNull);
    },
  );

  // `Unit.count('egg')` is not one of the eight fixed units, so this is the
  // only test that would notice `_overrideRow` regressing from
  // `unitToStorage` back to `Quantity.unit.symbol` — a fixed unit such as
  // grams stores identically either way and would not catch it.
  test('a run with a dynamic-unit override round-trips', () async {
    final value = Quantity.parse('4', Unit.count('egg'));
    final run = buildRun(
      id: 'run-1',
    ).override(recipeId: 'r', componentId: 'flour', value: value);
    await repository.save(run);

    final loaded = await repository.findById('run-1');
    expect(loaded!.overrides, run.overrides);
    expect(loaded.overrides[('r', 'flour')]!.unit, Unit.count('egg'));
  });

  // `Unit.namedYield` is not one of the eight fixed units `unitToStorage`
  // special-cases; writing `unit.symbol` directly instead of going through
  // `unitToStorage` would store the bare `tray` string, which
  // `unitFromStorage` rejects as corrupt.
  test('a run whose target yield uses a dynamic unit round-trips', () async {
    final recipe = Recipe(
      id: 'tray-bake',
      revision: 1,
      name: 'Tray bake',
      baseYield: Quantity.parse('10', Unit.namedYield('tray')),
      modifiedAt: DateTime.utc(2026, 9, 7),
      components: [
        RecipeComponent(
          id: 'eggs',
          target: const IngredientRef('egg'),
          baseQuantity: Quantity.parse('12', Unit.count('egg')),
          behavior: ScalingBehavior.proportional,
          displayOrder: 0,
        ),
      ],
    );
    final targetYield = Quantity.parse('20', Unit.namedYield('tray'));
    final result = const ProductionCalculator().calculate(
      recipe: recipe,
      targetYield: targetYield,
    );
    final run = ProductionRun(
      id: 'run-dynamic',
      createdAt: DateTime.utc(2026, 9, 7),
      recipe: recipe,
      dependencySnapshot: const {},
      targetYield: targetYield,
      result: result,
    );

    await repository.save(run);
    final loaded = await repository.findById('run-dynamic');

    expect(loaded!.targetYield, targetYield);
    expect(loaded.targetYield.unit, Unit.namedYield('tray'));
    expect(loaded.targetYield.unit.dimension, UnitDimension.yieldOnly);

    final summary = (await repository.listSummaries()).single;
    expect(summary.targetYield, targetYield);
  });

  test('a missing run reads as null', () async {
    expect(await repository.findById('absent'), isNull);
  });

  test('recordAcknowledgement adds an acknowledgement outside save', () async {
    await repository.save(buildRun(id: 'run-1'));

    const warning = ArchivedDependencyWarning('r');
    await repository.recordAcknowledgement('run-1', warning);

    expect(
      (await repository.findById('run-1'))!.acknowledgedWarnings,
      {warning},
    );
  });

  test('recordOverride adds an override outside save', () async {
    await repository.save(buildRun(id: 'run-1'));

    final value = Quantity.parse('42', Unit.gram);
    await repository.recordOverride('run-1', ('r', 'flour'), value);

    expect(
      (await repository.findById('run-1'))!.overrides,
      {('r', 'flour'): value},
    );
  });

  test(
    'an unrecognised acknowledgement warning kind is a corrupt database',
    () async {
      await repository.save(buildRun(id: 'run-1'));
      await db.insert('run_acknowledgements', <String, Object?>{
        'run_id': 'run-1',
        'warning_kind': 'invented',
        'recipe_id': 'r',
        'component_id': null,
      });

      await expectLater(
        repository.findById('run-1'),
        throwsA(isA<CorruptDatabaseError>()),
      );
    },
  );
}
