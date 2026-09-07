import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/result_codec.dart';

/// A run scaled by a ratio that has no finite decimal form (`1 kg` against
/// a `3 kg` base yield), with one unrounded component and one rounded one.
ProductionRun buildRunScaledByOneThird() {
  final recipe = Recipe(
    id: 'bread',
    revision: 1,
    name: 'Bread',
    baseYield: Quantity.parse('3', Unit.kilogram),
    modifiedAt: DateTime.utc(2026, 9, 7),
    preparationNotes: const ['Proof the dough for 12 hours'],
    components: [
      RecipeComponent(
        id: 'flour',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'salt',
        target: const IngredientRef('salt'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 1,
        rounding: RoundingRule.upToIncrement(Decimal.parse('0.05')),
      ),
    ],
  );
  final targetYield = Quantity.parse('1', Unit.kilogram);
  final result = const ProductionCalculator().calculate(
    recipe: recipe,
    targetYield: targetYield,
  );
  return ProductionRun(
    id: 'run-1',
    createdAt: DateTime.utc(2026, 9, 7),
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: targetYield,
    result: result,
  );
}

/// A run whose result carries exactly one warning of each kind: a manual
/// component, a component whose displayed total was rounded away from its
/// exact value, and a reference to an archived recipe — the recipe itself.
ProductionRun buildRunWithAllWarningKinds() {
  final recipe = Recipe(
    id: 'cake',
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
  final targetYield = Quantity.parse('2', Unit.kilogram);
  final result = const ProductionCalculator().calculate(
    recipe: recipe,
    targetYield: targetYield,
  );
  return ProductionRun(
    id: 'run-2',
    createdAt: DateTime.utc(2026, 9, 7),
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: targetYield,
    result: result,
  );
}

/// A run that expands a sub-recipe (exercising `ScaledComponent.subRecipe`
/// and a non-empty dependency snapshot) and splits into more than one batch
/// with a remainder (exercising `BatchPlan.remainderYield`).
ProductionRun buildRunWithSubRecipeAndBatches() {
  final syrup = Recipe(
    id: 'syrup',
    revision: 1,
    name: 'Syrup',
    baseYield: Quantity.parse('500', Unit.gram),
    modifiedAt: DateTime.utc(2026, 9, 7),
    components: [
      RecipeComponent(
        id: 'sugar-base',
        target: const IngredientRef('sugar'),
        baseQuantity: Quantity.parse('500', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
  );
  final cookies = Recipe(
    id: 'cookies',
    revision: 1,
    name: 'Cookies',
    baseYield: Quantity.parse('1', Unit.kilogram),
    maxBatchYield: Quantity.parse('400', Unit.gram),
    modifiedAt: DateTime.utc(2026, 9, 7),
    components: [
      RecipeComponent(
        id: 'butter',
        target: const IngredientRef('butter'),
        baseQuantity: Quantity.parse('200', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'syrup-ref',
        target: const SubRecipeRef('syrup'),
        baseQuantity: Quantity.parse('500', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 1,
      ),
    ],
  );
  final targetYield = Quantity.parse('1', Unit.kilogram);
  final result = const ProductionCalculator().calculate(
    recipe: cookies,
    targetYield: targetYield,
    recipeIndex: {'syrup': syrup},
  );
  return ProductionRun(
    id: 'run-3',
    createdAt: DateTime.utc(2026, 9, 7),
    recipe: cookies,
    dependencySnapshot: {'syrup': syrup},
    targetYield: targetYield,
    result: result,
  );
}

/// A run whose yield is a dynamic named-yield unit (`Unit.namedYield`) and
/// whose one component is a dynamic count unit (`Unit.count`) — neither is
/// one of the eight fixed units `unitToStorage`/`unitFromStorage` special-
/// case, so this is the only fixture that would notice a regression from
/// `unitToStorage(quantity.unit)` back to the bare `quantity.unit.symbol`.
ProductionRun buildRunWithDynamicUnits() {
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
  final targetYield = Quantity.parse('10', Unit.namedYield('tray'));
  final result = const ProductionCalculator().calculate(
    recipe: recipe,
    targetYield: targetYield,
  );
  return ProductionRun(
    id: 'run-4',
    createdAt: DateTime.utc(2026, 9, 7),
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: targetYield,
    result: result,
  );
}

// None of Recipe, RecipeComponent, BatchPlan, ScaledComponent,
// ProductionResult, or ScaledQuantity override `==`, so `expect(a, b)` on
// any of them falls back to identity — always false for a freshly decoded
// object. These helpers walk each one field by field instead, the same way
// `test/persistence/recipe_repository_test.dart` verifies a round trip.

void expectQuantityOrNull(Quantity? actual, Quantity? expected) {
  expect(actual, expected);
}

void expectScaledQuantity(ScaledQuantity? actual, ScaledQuantity? expected) {
  if (expected == null) {
    expect(actual, isNull);
    return;
  }
  expect(actual, isNotNull);
  expect(actual!.exact, expected.exact);
  expect(actual.displayed, expected.displayed);
}

void expectComponent(RecipeComponent actual, RecipeComponent expected) {
  expect(actual.id, expected.id);
  expect(actual.target, expected.target);
  expectQuantityOrNull(actual.baseQuantity, expected.baseQuantity);
  expect(actual.behavior, expected.behavior);
  expect(actual.displayOrder, expected.displayOrder);
  expect(actual.rounding?.increment, expected.rounding?.increment);
  expect(actual.note, expected.note);
}

void expectRecipe(Recipe actual, Recipe expected) {
  expect(actual.id, expected.id);
  expect(actual.revision, expected.revision);
  expect(actual.name, expected.name);
  expect(actual.category, expected.category);
  expect(actual.baseYield, expected.baseYield);
  expectQuantityOrNull(actual.maxBatchYield, expected.maxBatchYield);
  expect(actual.preparationNotes, expected.preparationNotes);
  expect(actual.modifiedAt, expected.modifiedAt);
  expect(actual.isArchived, expected.isArchived);
  expect(actual.components, hasLength(expected.components.length));
  for (var i = 0; i < expected.components.length; i++) {
    expectComponent(actual.components[i], expected.components[i]);
  }
}

void expectBatchPlan(BatchPlan actual, BatchPlan expected) {
  expect(actual.fullBatchCount, expected.fullBatchCount);
  expect(actual.fullBatchYield, expected.fullBatchYield);
  expectQuantityOrNull(actual.remainderYield, expected.remainderYield);
}

void expectScaledComponent(ScaledComponent actual, ScaledComponent expected) {
  expectComponent(actual.source, expected.source);
  expectScaledQuantity(actual.total, expected.total);
  expect(actual.perBatch, hasLength(expected.perBatch.length));
  for (var i = 0; i < expected.perBatch.length; i++) {
    expectScaledQuantity(actual.perBatch[i], expected.perBatch[i]);
  }
  if (expected.subRecipe == null) {
    expect(actual.subRecipe, isNull);
  } else {
    expect(actual.subRecipe, isNotNull);
    expectResult(actual.subRecipe!, expected.subRecipe!);
  }
}

void expectResult(ProductionResult actual, ProductionResult expected) {
  expect(actual.scaleRatio, expected.scaleRatio);
  expectBatchPlan(actual.batchPlan, expected.batchPlan);
  expect(actual.warnings, expected.warnings);
  expect(actual.components, hasLength(expected.components.length));
  for (var i = 0; i < expected.components.length; i++) {
    expectScaledComponent(actual.components[i], expected.components[i]);
  }
}

void expectDependencySnapshot(
  Map<String, Recipe> actual,
  Map<String, Recipe> expected,
) {
  expect(actual.keys, expected.keys);
  for (final id in expected.keys) {
    expectRecipe(actual[id]!, expected[id]!);
  }
}

void main() {
  test('a run payload round-trips including a non-terminating quantity', () {
    final run = buildRunScaledByOneThird();
    final decoded = decodeRunPayload(encodeRunPayload(run));

    expectRecipe(decoded.recipe, run.recipe);
    expectDependencySnapshot(
      decoded.dependencySnapshot,
      run.dependencySnapshot,
    );
    expectResult(decoded.result, run.result);

    // The exact clause this test is named for: a component with no
    // rounding rule, scaled by 1/3, must survive without truncation.
    final flour = decoded.result.components.first;
    expect(
      flour.total!.exact,
      Quantity.parse('1', Unit.kilogram).scaleBy(
        Rational(BigInt.one, BigInt.from(3)),
      ),
    );
    expect(flour.total!.exact, flour.total!.displayed);
  });

  test('every warning kind survives the round trip', () {
    final run = buildRunWithAllWarningKinds();
    final decoded = decodeRunPayload(encodeRunPayload(run));

    expect(decoded.result.warnings, run.result.warnings);
    expect(decoded.result.warnings, hasLength(3));
    expect(
      decoded.result.warnings.map((w) => w.runtimeType).toSet(),
      {
        ManualComponentWarning,
        RoundingAdjustedWarning,
        ArchivedDependencyWarning,
      },
    );
  });

  test(
    'a run with a sub-recipe and multiple batches round-trips',
    () {
      final run = buildRunWithSubRecipeAndBatches();
      final decoded = decodeRunPayload(encodeRunPayload(run));

      expectRecipe(decoded.recipe, run.recipe);
      expectDependencySnapshot(
        decoded.dependencySnapshot,
        run.dependencySnapshot,
      );
      expectResult(decoded.result, run.result);

      expect(decoded.result.batchPlan.fullBatchCount, 2);
      expect(decoded.result.batchPlan.remainderYield, isNotNull);
      final syrupRef = decoded.result.components.last;
      expect(syrupRef.subRecipe, isNotNull);
      expect(syrupRef.subRecipe!.components, hasLength(1));
    },
  );

  test('a run with dynamic count and named-yield units round-trips', () {
    final run = buildRunWithDynamicUnits();
    final decoded = decodeRunPayload(encodeRunPayload(run));

    expectRecipe(decoded.recipe, run.recipe);
    expectResult(decoded.result, run.result);

    // Neither unit is one of the eight fixed units, so a regression from
    // unitToStorage back to the bare symbol would either throw decoding
    // (no ':' separator, no fixed-table match) or silently collide two
    // dynamic units that happen to share a symbol. Assert the actual
    // dynamic Unit instances survive, not just their symbols.
    expect(decoded.recipe.baseYield.unit, Unit.namedYield('tray'));
    expect(decoded.recipe.baseYield.unit.dimension, UnitDimension.yieldOnly);
    final eggs = decoded.result.components.single;
    expect(eggs.source.baseQuantity!.unit, Unit.count('egg'));
    expect(eggs.source.baseQuantity!.unit.dimension, UnitDimension.count);
  });

  test('malformed json is a corrupt database', () {
    expect(
      () => decodeRunPayload('{not json'),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test('a json value that is not a run payload is a corrupt database', () {
    expect(
      () => decodeRunPayload('{"warnings":[{"kind":"invented"}]}'),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test('an unrecognized warning kind is a corrupt database', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithAllWarningKinds()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final warnings = result['warnings']! as List<Object?>;
    (warnings.first! as Map<String, Object?>)['kind'] = 'invented';

    expect(
      () => decodeRunPayload(jsonEncode(encoded)),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test('an unrecognized component target kind is a corrupt database', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunScaledByOneThird()))
            as Map<String, Object?>;
    final recipe = encoded['recipe']! as Map<String, Object?>;
    final components = recipe['components']! as List<Object?>;
    final target =
        (components.first! as Map<String, Object?>)['target']!
            as Map<String, Object?>;
    target['kind'] = 'invented';

    expect(
      () => decodeRunPayload(jsonEncode(encoded)),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test('an unrecognized component behavior is a corrupt database', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunScaledByOneThird()))
            as Map<String, Object?>;
    final recipe = encoded['recipe']! as Map<String, Object?>;
    final components = recipe['components']! as List<Object?>;
    (components.first! as Map<String, Object?>)['behavior'] = 'invented';

    expect(
      () => decodeRunPayload(jsonEncode(encoded)),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test('an inconsistent scaled quantity is a corrupt database', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunScaledByOneThird()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final components = result['components']! as List<Object?>;
    // Index 1 is 'salt', the rounded component: exact != displayed.
    final salt = components[1]! as Map<String, Object?>;
    final total = salt['total']! as Map<String, Object?>;
    final exact = total['exact'];
    total['exact'] = total['displayed'];
    total['displayed'] = exact;

    expect(
      () => decodeRunPayload(jsonEncode(encoded)),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test('an inconsistent batch plan is a corrupt database', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithSubRecipeAndBatches()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final batchPlan = result['batchPlan']! as Map<String, Object?>;
    // A remainder equal to a full batch is not a valid remainder — it
    // forces the reconstructed plan to disagree with the stored triple.
    batchPlan['remainderYield'] = batchPlan['fullBatchYield'];

    expect(
      () => decodeRunPayload(jsonEncode(encoded)),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test(
    'a batch count that disagrees with a component perBatch length '
    'is a corrupt database',
    () {
      final encoded =
          jsonDecode(encodeRunPayload(buildRunWithSubRecipeAndBatches()))
              as Map<String, Object?>;
      final result = encoded['result']! as Map<String, Object?>;
      final batchPlan = result['batchPlan']! as Map<String, Object?>;
      // fullBatchCount changes, but remainderYield is left alone, so
      // BatchPlan.decompose still reconstructs a self-consistent triple —
      // only the components' perBatch length still remembers the truth.
      batchPlan['fullBatchCount'] = (batchPlan['fullBatchCount']! as int) + 3;

      expect(
        () => decodeRunPayload(jsonEncode(encoded)),
        throwsA(isA<CorruptDatabaseError>()),
      );
    },
  );

  test(
    "a full-batch yield that disagrees with a proportional component's "
    'per-batch ratio is a corrupt database',
    () {
      final encoded =
          jsonDecode(encodeRunPayload(buildRunWithSubRecipeAndBatches()))
              as Map<String, Object?>;
      final result = encoded['result']! as Map<String, Object?>;
      final batchPlan = result['batchPlan']! as Map<String, Object?>;
      final fullBatchYield =
          batchPlan['fullBatchYield']! as Map<String, Object?>;
      // fullBatchYield changes alone (400g -> 500g); remainderYield (200g)
      // is left untouched. BatchPlan.decompose still reconstructs a
      // self-consistent triple from these two numbers alone (2 full
      // batches of 500g plus a 200g remainder), so only 'butter' — a
      // proportional component whose stored per-batch quantities were
      // scaled against the real 400g yield — still remembers the truth.
      fullBatchYield['n'] = '500';
      fullBatchYield['d'] = '1';

      expect(
        () => decodeRunPayload(jsonEncode(encoded)),
        throwsA(isA<CorruptDatabaseError>()),
      );
    },
  );
}
