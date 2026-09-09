import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/result_codec.dart';
import 'package:prep_book/persistence/sqflite/timestamps.dart';

/// Stands in for the row label a repository threads into the codec. These
/// tests drive [decodeRunPayload] with hand-built payloads that belong to no
/// stored row, so the label only has to be present. The test that proves a
/// real row's id reaches the message lives in `failure_paths_test.dart`.
const _rowLabel = 'production_runs row test';

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

/// A minimal run whose recipe carries [modifiedAt] verbatim, so the
/// payload's own timestamp encoding can be asserted on a value that is not
/// already UTC.
ProductionRun buildRunModifiedAt(DateTime modifiedAt) {
  final recipe = Recipe(
    id: 'scone',
    revision: 1,
    name: 'Scone',
    baseYield: Quantity.parse('1', Unit.kilogram),
    modifiedAt: modifiedAt,
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
  final targetYield = recipe.baseYield;
  return ProductionRun(
    id: 'run-5',
    createdAt: DateTime.utc(2026, 9, 7),
    recipe: recipe,
    dependencySnapshot: {'scone': recipe},
    targetYield: targetYield,
    result: const ProductionCalculator().calculate(
      recipe: recipe,
      targetYield: targetYield,
    ),
  );
}

/// A run carrying an ingredient snapshot: one ingredient in a fixed unit
/// with a category, one counted in a unit no fixed table holds and with no
/// category.
///
/// The second is what makes the payload's unit encoding assertable. A count
/// unit and a named-yield unit print the same symbol, so an encoder writing
/// `Unit.symbol` instead of the storage form would round-trip `sheet` into
/// the wrong kind and nothing about the printed value would say so.
ProductionRun buildRunWithSnapshottedIngredients() {
  final recipe = Recipe(
    id: 'tart',
    revision: 1,
    name: 'Tart',
    baseYield: Quantity.parse('1', Unit.kilogram),
    modifiedAt: DateTime.utc(2026, 9, 7),
    components: [
      RecipeComponent(
        id: 'flour-line',
        target: const IngredientRef('bread-flour'),
        baseQuantity: Quantity.parse('500', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'gelatin-line',
        target: const IngredientRef('gelatin'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 1,
      ),
    ],
  );
  final targetYield = recipe.baseYield;
  return ProductionRun(
    id: 'run-6',
    createdAt: DateTime.utc(2026, 9, 7),
    recipe: recipe,
    dependencySnapshot: const {},
    ingredientSnapshot: {
      'bread-flour': Ingredient(
        id: 'bread-flour',
        name: 'Bread flour',
        defaultUnit: Unit.gram,
        category: 'Dry goods',
      ),
      'gelatin': Ingredient(
        id: 'gelatin',
        name: 'Leaf gelatin',
        defaultUnit: Unit.count('sheet'),
      ),
    },
    targetYield: targetYield,
    result: const ProductionCalculator().calculate(
      recipe: recipe,
      targetYield: targetYield,
    ),
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
    final decoded = decodeRunPayload(
      encodeRunPayload(run),
      rowLabel: _rowLabel,
    );

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
      Quantity.parse(
        '1',
        Unit.kilogram,
      ).scaleBy(Rational(BigInt.one, BigInt.from(3))),
    );
    expect(flour.total!.exact, flour.total!.displayed);
  });

  test('every warning kind survives the round trip', () {
    final run = buildRunWithAllWarningKinds();
    final decoded = decodeRunPayload(
      encodeRunPayload(run),
      rowLabel: _rowLabel,
    );

    expect(decoded.result.warnings, run.result.warnings);
    expect(decoded.result.warnings, hasLength(3));
    expect(decoded.result.warnings.map((w) => w.runtimeType).toSet(), {
      ManualComponentWarning,
      RoundingAdjustedWarning,
      ArchivedDependencyWarning,
    });
  });

  test('a run with a sub-recipe and multiple batches round-trips', () {
    final run = buildRunWithSubRecipeAndBatches();
    final decoded = decodeRunPayload(
      encodeRunPayload(run),
      rowLabel: _rowLabel,
    );

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
  });

  test('a run with dynamic count and named-yield units round-trips', () {
    final run = buildRunWithDynamicUnits();
    final decoded = decodeRunPayload(
      encodeRunPayload(run),
      rowLabel: _rowLabel,
    );

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

  // Every other fixture in this file builds `modifiedAt` with `DateTime.utc`,
  // for which `toUtc()` is identity, so the suite exercised only the form
  // that already serializes with a `Z`. The application will hand this layer
  // `DateTime.now()`, which is local. The two column writers were normalized
  // earlier; this is the third writer of the same value, and leaving it naive
  // made the same recipe read back through `findRevision` and through a run
  // payload compare unequal — `DateTime`'s `==` includes the `isUtc` flag —
  // while denoting the same instant, and left the payload copy a wall clock
  // that re-anchors wherever it is next read.
  //
  // `toIso8601String` emits the `Z` from the `isUtc` flag rather than from
  // the zone offset, so a runner whose local zone is UTC still fails this
  // without the normalization: `local` is not a UTC `DateTime` there either.
  test('a local modifiedAt is normalized to UTC in the payload', () {
    final local = DateTime(2026, 9, 7, 21, 30);
    expect(local.isUtc, isFalse);

    final json = encodeRunPayload(buildRunModifiedAt(local));
    final encoded = jsonDecode(json) as Map<String, Object?>;

    expect(
      (encoded['recipe']! as Map<String, Object?>)['modifiedAt'],
      endsWith('Z'),
    );
    // Not only UTC, but the exact text the one shared writer produces, so
    // this payload field cannot drift away from the two columns that store
    // the same value by going back to a bare `toIso8601String` — which
    // would drop the microsecond triplet and still end with a `Z`.
    expect(
      (encoded['recipe']! as Map<String, Object?>)['modifiedAt'],
      timestampToStorage(local),
    );
    // The dependency snapshot goes through the same encoder, and a run's
    // dependencies carry timestamps of their own.
    final snapshot = encoded['dependencySnapshot']! as Map<String, Object?>;
    expect(
      (snapshot['scone']! as Map<String, Object?>)['modifiedAt'],
      endsWith('Z'),
    );

    final decoded = decodeRunPayload(json, rowLabel: _rowLabel);
    expect(decoded.recipe.modifiedAt.isUtc, isTrue);
    expect(decoded.recipe.modifiedAt.isAtSameMomentAs(local), isTrue);
  });

  test('the ingredient snapshot round-trips, dynamic units included', () {
    final run = buildRunWithSnapshottedIngredients();

    final decoded = decodeRunPayload(
      encodeRunPayload(run),
      rowLabel: _rowLabel,
    );

    // `Ingredient` does not override `==`, so each field is read
    // separately — the same reason the helpers above walk a `Recipe`.
    expect(decoded.ingredientSnapshot.keys, ['bread-flour', 'gelatin']);
    final flour = decoded.ingredientSnapshot['bread-flour']!;
    expect(flour.id, 'bread-flour');
    // A name no identifier spells, so a decoder that fell back to the key
    // would not read the same as one that stored the name.
    expect(flour.name, 'Bread flour');
    expect(flour.defaultUnit, Unit.gram);
    expect(flour.category, 'Dry goods');
    final gelatin = decoded.ingredientSnapshot['gelatin']!;
    // The unit goes through the storage form rather than through
    // `Unit.symbol`, so a count unit comes back counted rather than as a
    // named yield that happens to print the same word.
    expect(gelatin.defaultUnit, Unit.count('sheet'));
    expect(gelatin.defaultUnit, isNot(Unit.namedYield('sheet')));
    // An optional field left unset stays unset rather than becoming the
    // empty string.
    expect(gelatin.category, isNull);
  });

  test('a payload stored before the ingredient snapshot decodes', () {
    // The exact shape of a `result_json` written before this key existed:
    // the key is absent, not null. The schema version did not move for it
    // — `result_json` is an opaque payload column — so this decode is the
    // only thing standing between an older stored run and a screen that
    // cannot open it.
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithSnapshottedIngredients()))
            as Map<String, Object?>;
    expect(
      (encoded..remove('ingredientSnapshot')).containsKey('ingredientSnapshot'),
      isFalse,
    );

    final decoded = decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel);

    // Nothing is fabricated for it: an older run held no ingredient data,
    // and reads as holding none.
    expect(decoded.ingredientSnapshot, isEmpty);
    // And the rest of the payload still arrives, so the tolerance is one
    // absent key rather than a decoder that gave up on the run.
    expect(decoded.recipe.id, 'tart');
    expect(decoded.result.components, hasLength(2));
  });

  test('an ingredient snapshot that is not a map is a corrupt row', () {
    // Tolerating an absent key is not tolerating a damaged one. A present
    // value of the wrong shape is corruption, and it has to be named as
    // such rather than read as "this run had no ingredients".
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithSnapshottedIngredients()))
            as Map<String, Object?>;
    encoded['ingredientSnapshot'] = 'not a map';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          contains(_rowLabel),
        ),
      ),
    );
  });

  test("an ingredient's stored unit is checked, and names the row", () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithSnapshottedIngredients()))
            as Map<String, Object?>;
    final snapshot = encoded['ingredientSnapshot']! as Map<String, Object?>;
    (snapshot['gelatin']! as Map<String, Object?>)['defaultUnit'] = 'nonsense';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          allOf(contains(_rowLabel), contains('gelatin')),
        ),
      ),
    );
  });

  // Both of the codec's row-naming failures are asserted on their message,
  // not only their type: they are the two the specification requires to name
  // the row, and a message that named only the bad value would satisfy
  // `isA<CorruptDatabaseError>()` just as well.
  test('malformed json is a corrupt database naming the row', () {
    expect(
      () => decodeRunPayload('{not json', rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          allOf(
            contains(_rowLabel),
            contains('run payload of'),
            contains('is not valid JSON'),
          ),
        ),
      ),
    );
  });

  test('a json value that is not a run payload is a corrupt database', () {
    expect(
      () => decodeRunPayload(
        '{"warnings":[{"kind":"invented"}]}',
        rowLabel: _rowLabel,
      ),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  // --- how each message reaches the row label -----------------------------
  //
  // Every message `decodeRunPayload` can raise names the row, but they get
  // there two different ways, and the difference is a real structural
  // property rather than a formatting detail.
  //
  // A failure raised in the try *body* is labelled by the sibling
  // `on CorruptDatabaseError` clause, which prefixes the row: `<row>: <what
  // went wrong>`. The three messages the `on TypeError`, `on
  // FormatException`, and `on DomainError` clauses build cannot be labelled
  // that way at all — a throw from inside a catch clause leaves the whole
  // try statement rather than reaching a sibling — so those interpolate the
  // label themselves, reading `run payload of <row> …`.
  //
  // The two tests below assert that second form with `startsWith`, and
  // `failure_paths_test.dart` reaches the third through a stored row.
  // Nesting
  // the clause instead of leaving it a sibling would prefix these messages a
  // second time and push `run payload of` off the front, so `startsWith`
  // still discriminates sibling from nested. `contains` would not: it passes
  // under either structure.

  test('a shape failure names the row in its own message', () {
    expect(
      () => decodeRunPayload('{"warnings":[]}', rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          startsWith('run payload of $_rowLabel has an unexpected shape'),
        ),
      ),
    );
  });

  test('an unparseable payload value names the row in its own message', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunScaledByOneThird()))
            as Map<String, Object?>;
    (encoded['recipe']! as Map<String, Object?>)['modifiedAt'] = 'yesterday';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          startsWith('run payload of $_rowLabel holds an unparseable value'),
        ),
      ),
    );
  });

  // The other side of the same boundary: a failure raised in the try body,
  // by a helper that names only its position inside the payload, comes back
  // carrying the row.
  test('a payload-internal failure is labelled with the row', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunScaledByOneThird()))
            as Map<String, Object?>;
    final recipe = encoded['recipe']! as Map<String, Object?>;
    (recipe['baseYield']! as Map<String, Object?>)['u'] = 'parsec';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          startsWith('$_rowLabel: unknown unit symbol'),
        ),
      ),
    );
  });

  test('an unrecognized warning kind is a corrupt database naming the row', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithAllWarningKinds()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final warnings = result['warnings']! as List<Object?>;
    (warnings.first! as Map<String, Object?>)['kind'] = 'invented';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          allOf(contains(_rowLabel), contains('unknown warning kind')),
        ),
      ),
    );
  });

  // A warning inside an expanded sub-recipe is decoded through a second,
  // nested `_resultFromJson`, so it reaches `_warningFromJson` down a path
  // the test above never walks. It must still name the row, which is the
  // whole reason the label is threaded through `_scaledComponentFromJson`
  // rather than only used at the top level.
  test("an unrecognized warning kind inside a sub-recipe's result names the "
      'row too', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithSubRecipeAndBatches()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final components = result['components']! as List<Object?>;
    final syrup = components.last! as Map<String, Object?>;
    final subResult = syrup['subRecipe']! as Map<String, Object?>;
    // The sub-recipe's own result carries no warnings of its own, so one
    // is planted rather than mutated — the decoder must reject it wherever
    // in the tree it appears.
    subResult['warnings'] = <Object?>[
      <String, Object?>{'kind': 'invented'},
    ];

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          allOf(contains(_rowLabel), contains('unknown warning kind')),
        ),
      ),
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
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
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
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
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
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
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
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test('a batch count that disagrees with a component perBatch length '
      'is a corrupt database', () {
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
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test("a full-batch yield that disagrees with a proportional component's "
      'per-batch ratio is a corrupt database', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithSubRecipeAndBatches()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final batchPlan = result['batchPlan']! as Map<String, Object?>;
    final fullBatchYield = batchPlan['fullBatchYield']! as Map<String, Object?>;
    // fullBatchYield changes alone (400g -> 500g); remainderYield (200g)
    // is left untouched. BatchPlan.decompose still reconstructs a
    // self-consistent triple from these two numbers alone (2 full
    // batches of 500g plus a 200g remainder), so only 'butter' — a
    // proportional component whose stored per-batch quantities were
    // scaled against the real 400g yield — still remembers the truth.
    fullBatchYield['n'] = '500';
    fullBatchYield['d'] = '1';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  // The four cases below damage a component's total, its per-batch list, or
  // the run's scale ratio — each one a value the decoder rebuilds from its
  // own stored fields and would otherwise hand back as a valid production
  // quantity. Each leaves the witness the codec checks it against intact.
  test('a total that disagrees with its per-batch sum is corrupt', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithSubRecipeAndBatches()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final butter =
        (result['components']! as List<Object?>).first! as Map<String, Object?>;
    // 'butter' is 200g over three batches of 80g, 80g and 40g. Replacing
    // the total with the first batch leaves every per-batch quantity
    // untouched, so the sum still remembers the real total.
    butter['total'] = (butter['perBatch']! as List<Object?>).first;

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          contains('component butter stores a total of'),
        ),
      ),
    );
  });

  test('a numeric component missing one per-batch quantity is corrupt', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithSubRecipeAndBatches()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final butter =
        (result['components']! as List<Object?>).first! as Map<String, Object?>;
    // Only a manual component may carry an absent batch, and this one is
    // proportional, so the total it still stores has nothing left to
    // witness it.
    (butter['perBatch']! as List<Object?>)[0] = null;

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          contains('2 of 3 are present'),
        ),
      ),
    );
  });

  test('a manual component carrying a per-batch quantity is corrupt', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithAllWarningKinds()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final components = result['components']! as List<Object?>;
    final eggs = components.first! as Map<String, Object?>;
    final sugar = components.last! as Map<String, Object?>;
    // 'eggs' is manual, so it stores a null total and an all-null batch
    // list. A quantity appearing in one of those batches is a total that
    // went missing, or a batch that never belonged to this component.
    (eggs['perBatch']! as List<Object?>)[0] = sugar['total'];

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          contains('component eggs has no total but carries 1'),
        ),
      ),
    );
  });

  test('a displayed total altered on its own is corrupt', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithAllWarningKinds()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final sugar =
        (result['components']! as List<Object?>).last! as Map<String, Object?>;
    final total = sugar['total']! as Map<String, Object?>;
    // 'sugar' rounds 333g up to 350g, so exact and displayed differ.
    // Flattening displayed onto exact leaves the exact half of the
    // invariant satisfied and breaks only the displayed one — the case a
    // check that compared exact amounts alone would let through.
    total['displayed'] = total['exact'];

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          contains('component sugar stores a total of'),
        ),
      ),
    );
  });

  test("a scale ratio that disagrees with a component's total is corrupt", () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRunWithSubRecipeAndBatches()))
            as Map<String, Object?>;
    final result = encoded['result']! as Map<String, Object?>;
    final scaleRatio = result['scaleRatio']! as Map<String, Object?>;
    // The run scales 1:1. Doubling the ratio alone still decodes to a
    // perfectly ordinary rational, and no other stored field is derived
    // from it — only 'butter', whose 200g total was computed against the
    // real ratio, disagrees.
    scaleRatio['n'] = '2';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _rowLabel),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.message,
          'message',
          contains("component butter's exact total"),
        ),
      ),
    );
  });
}
