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

/// A recipe with a single manual-entry component, so its calculated result
/// carries exactly one warning: a blocking [ManualComponentWarning]. Built
/// independently of [_buildRecipeWithAllWarningKinds], which mixes a
/// blocking and a non-blocking warning together and is the wrong base for a
/// test whose premise is exactly one blocking warning.
Recipe _buildRecipeWithOneBlockingWarning({required String id}) => Recipe(
  id: id,
  revision: 1,
  name: 'Needs a manual line',
  baseYield: Quantity.parse('1000', Unit.gram),
  modifiedAt: DateTime.utc(2026, 9, 7),
  components: [
    RecipeComponent(
      id: 'garnish',
      target: const IngredientRef('garnish'),
      baseQuantity: null,
      behavior: ScalingBehavior.manual,
      displayOrder: 0,
    ),
  ],
);

/// A run computed from [_buildRecipeWithOneBlockingWarning].
ProductionRun buildRunWithOneBlockingWarning({required String id}) {
  final recipe = _buildRecipeWithOneBlockingWarning(id: 'needs-manual');
  final targetYield = recipe.baseYield;
  final result = const ProductionCalculator().calculate(
    recipe: recipe,
    targetYield: targetYield,
  );
  return ProductionRun(
    id: id,
    createdAt: DateTime.utc(2026, 9, 7),
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: targetYield,
    result: result,
  );
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
  //
  // The row count is the stronger half of that claim. `findById` returning
  // null only shows the `production_runs` row went away; the count shows
  // every write `save` made did. It is not vacuous because the plant
  // collides with the *second* acknowledgement `save` writes: the fixture's
  // warnings are ordered archived_dependency, manual_component,
  // rounding_adjusted, so the archived_dependency row is already inserted
  // when the collision aborts the transaction. Without the transaction the
  // table would be left holding two rows, not one.
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
      expect(await db.query('run_acknowledgements'), hasLength(1));
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

  // Subsumes the former "recordAcknowledgement adds an acknowledgement
  // outside save" test: the outside-save round trip is still exercised
  // here, together with the finalizability transition it exists to enable.
  test(
    'recordAcknowledgement adds an acknowledgement outside save and can '
    'make the run finalizable',
    () async {
      final run = buildRunWithOneBlockingWarning(id: 'run-1');
      expect(run.result.warnings.where((w) => w.isBlocking), hasLength(1));
      await repository.save(run);
      expect((await repository.findById('run-1'))!.isFinalizable, isFalse);

      final warning = run.result.warnings.first;
      await repository.recordAcknowledgement('run-1', warning);

      final loaded = await repository.findById('run-1');
      expect(loaded!.acknowledgedWarnings, {warning});
      expect(loaded.isFinalizable, isTrue);
    },
  );

  // `_acknowledgementsFor` reconstructs rows into a `Set`, and the
  // `ProductionWarning` family defines value equality, so two identical
  // stored rows would collapse into a one-element `Set` regardless of
  // whether the table holds one row or two. The query against
  // `run_acknowledgements` directly is what actually proves no duplicate
  // was written.
  test('acknowledging the same warning twice does not duplicate', () async {
    final run = buildRunWithOneBlockingWarning(id: 'run-1');
    await repository.save(run);
    final warning = run.result.warnings.first;

    await repository.recordAcknowledgement('run-1', warning);
    await repository.recordAcknowledgement('run-1', warning);

    expect(
      (await repository.findById('run-1'))!.acknowledgedWarnings,
      hasLength(1),
    );
    final rows = await db.query(
      'run_acknowledgements',
      where: 'run_id = ?',
      whereArgs: ['run-1'],
    );
    expect(rows, hasLength(1));
  });

  // Subsumes the former "recordOverride adds an override outside save"
  // test: the outside-save round trip is still exercised here, together
  // with the recipe-and-component-together key it exists to prove — a
  // sub-recipe referenced twice can carry the same component id as its
  // parent, so the key must be the pair, not the component id alone.
  test(
    'recordOverride adds an override outside save, keyed by recipe and '
    'component together',
    () async {
      await repository.save(buildRun(id: 'run-1'));

      final parentValue = Quantity.parse('5', Unit.gram);
      final childValue = Quantity.parse('7', Unit.gram);
      await repository.recordOverride(
        'run-1',
        ('parent', 'salt'),
        parentValue,
      );
      await repository.recordOverride('run-1', ('child', 'salt'), childValue);

      final loaded = await repository.findById('run-1');
      expect(loaded!.overrides, hasLength(2));
      expect(loaded.overrides[('parent', 'salt')], parentValue);
      expect(loaded.overrides[('child', 'salt')], childValue);
    },
  );

  // `_overridesFor` builds a Dart map literal, which silently last-wins on
  // a duplicate key — the same blindness `_acknowledgementsFor`'s `.toSet()`
  // has above. The query against `run_overrides` directly is what actually
  // proves the old row was replaced rather than duplicated.
  test(
    'recording an override replaces the previous value for that key',
    () async {
      await repository.save(buildRun(id: 'run-1'));
      final firstValue = Quantity.parse('10', Unit.gram);
      final secondValue = Quantity.parse('20', Unit.gram);

      await repository.recordOverride('run-1', ('r', 'salt'), firstValue);
      await repository.recordOverride('run-1', ('r', 'salt'), secondValue);

      final loaded = await repository.findById('run-1');
      expect(loaded!.overrides, hasLength(1));
      expect(loaded.overrides[('r', 'salt')], secondValue);

      final rows = await db.query(
        'run_overrides',
        where: 'run_id = ? AND recipe_id = ? AND component_id = ?',
        whereArgs: ['run-1', 'r', 'salt'],
      );
      expect(rows, hasLength(1));
    },
  );

  // `created_at` is what `listSummaries` orders on, and lexicographic order
  // is chronological only while every writer emits one form: a local
  // `DateTime` serializes without a `Z` and a UTC one with, and
  // '…T21:00:00.000Z' sorts after '…T21:00:00.000'. Every other fixture in
  // this suite is `DateTime.utc`, so the suite exercised only the suffixed
  // form while the application will pass `DateTime.now()`. Normalizing on
  // write is the last moment the offset is known.
  test('a local createdAt is stored normalized to UTC', () async {
    final local = DateTime(2026, 9, 7, 21, 30);
    expect(local.isUtc, isFalse);

    await repository.save(buildRun(id: 'run-1', createdAt: local));

    final stored =
        (await db.query(
              'production_runs',
              columns: ['created_at'],
            )).single['created_at']!
            as String;
    expect(stored, endsWith('Z'));

    final loaded = await repository.findById('run-1');
    expect(loaded!.createdAt.isUtc, isTrue);
    expect(loaded.createdAt.isAtSameMomentAs(local), isTrue);

    final summary = (await repository.listSummaries()).single;
    expect(summary.createdAt.isUtc, isTrue);
    expect(summary.createdAt.isAtSameMomentAs(local), isTrue);
  });

  // The message must name the run, not only the kind and component that
  // were not recognised: both of those repeat across every run in the
  // table, so on their own they identify no row to repair. `findById` is
  // the only reader of this table, but it is reached from a history screen
  // where the operator has many runs to choose between.
  test(
    'an unrecognised acknowledgement warning kind is a corrupt database '
    'naming the run',
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
        throwsA(
          isA<CorruptDatabaseError>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('run_acknowledgements row for run run-1'),
              contains('unrecognised acknowledgement'),
              contains('warning_kind=invented'),
            ),
          ),
        ),
      );
    },
  );
}
