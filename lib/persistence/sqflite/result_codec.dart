import 'dart:convert';

import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';

/// The immutable part of a stored production run: the recipe revision it was
/// computed from, every recipe it depended on, and the calculated result.
///
/// Acknowledgements and overrides are excluded on purpose. They live in
/// their own tables because `ProductionRun._copyWith` is the only thing
/// that ever replaces them — see `encodeRunPayload`.
final class RunPayload {
  /// Creates a payload from its three immutable parts.
  const RunPayload({
    required this.recipe,
    required this.dependencySnapshot,
    required this.result,
  });

  /// The recipe revision the run was computed from.
  final Recipe recipe;

  /// Every recipe the calculation depended on, as it was at that moment.
  final Map<String, Recipe> dependencySnapshot;

  /// The calculated result.
  final ProductionResult result;
}

/// Encodes the immutable part of [run] — its recipe, dependency snapshot,
/// and calculated result — as JSON.
///
/// `run.id`, `run.createdAt`, and `run.targetYield` are not part of this
/// payload; they are stored in their own columns. `run.overrides` and
/// `run.acknowledgedWarnings` are not part of it either, because those are
/// the only fields a run's `acknowledge` and `override` methods ever
/// replace — they live in their own tables instead.
String encodeRunPayload(ProductionRun run) => jsonEncode(<String, Object?>{
  'recipe': _recipeToJson(run.recipe),
  'dependencySnapshot': <String, Object?>{
    for (final entry in run.dependencySnapshot.entries)
      entry.key: _recipeToJson(entry.value),
  },
  'result': _resultToJson(run.result),
});

/// Rebuilds a [RunPayload] from [json], as produced by [encodeRunPayload].
///
/// Throws [CorruptDatabaseError] when [json] is not valid JSON, does not
/// have the shape a run payload has, or names a warning kind, component
/// target kind, or scaling behavior this decoder does not recognize. An
/// unrecognized warning kind is never dropped — a silently dropped blocking
/// warning would make a run that must not be finalized look finalizable.
RunPayload decodeRunPayload(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (error) {
    throw CorruptDatabaseError('run payload is not valid JSON: $error');
  }
  try {
    final map = decoded! as Map<String, Object?>;
    final snapshotJson = map['dependencySnapshot']! as Map<String, Object?>;
    return RunPayload(
      recipe: _recipeFromJson(map['recipe']! as Map<String, Object?>),
      dependencySnapshot: <String, Recipe>{
        for (final entry in snapshotJson.entries)
          entry.key: _recipeFromJson(entry.value! as Map<String, Object?>),
      },
      result: _resultFromJson(map['result']! as Map<String, Object?>),
    );
    // A cast failure here is Dart's `TypeError`, thrown for a `Map` whose
    // shape does not match, a missing key forced non-null by `!`, or a
    // `null` payload. The brief calls for exactly this: any cast failure
    // from decoded JSON is a corrupt row, not a programmer bug.
    // ignore: avoid_catching_errors
  } on TypeError catch (error) {
    throw CorruptDatabaseError('run payload has an unexpected shape: $error');
  }
}

// --- Quantity and Rational ---------------------------------------------

/// Encodes [quantity] as `{"n": ..., "d": ..., "u": ...}`. The numerator and
/// denominator are decimal strings, never a decimal amount, so a value such
/// as one third survives without truncation. The unit goes through
/// [unitToStorage], not [Unit.symbol] directly, so a dynamic unit (a count
/// or named-yield unit) round-trips its kind along with its symbol.
Map<String, Object?> _quantityToJson(Quantity quantity) => <String, Object?>{
  'n': quantity.amount.numerator.toString(),
  'd': quantity.amount.denominator.toString(),
  'u': unitToStorage(quantity.unit),
};

Quantity _quantityFromJson(Map<String, Object?> json) => Quantity.fromRational(
  parseStoredRational(
    json['n']! as String,
    json['d']! as String,
    location: 'a run payload quantity',
  ),
  unitFromStorage(json['u']! as String),
);

Map<String, Object?> _rationalToJson(Rational value) => <String, Object?>{
  'n': value.numerator.toString(),
  'd': value.denominator.toString(),
};

Rational _rationalFromJson(Map<String, Object?> json) => parseStoredRational(
  json['n']! as String,
  json['d']! as String,
  location: "a run payload's scale ratio",
);

// --- ScaledQuantity ------------------------------------------------------

/// Encodes [quantity] as `{"exact": ..., "displayed": ...}`.
Map<String, Object?> _scaledQuantityToJson(ScaledQuantity quantity) =>
    <String, Object?>{
      'exact': _quantityToJson(quantity.exact),
      'displayed': _quantityToJson(quantity.displayed),
    };

/// Rebuilds a [ScaledQuantity] from its exact and displayed quantities.
///
/// `ScaledQuantity` has no public constructor that accepts both values
/// directly — only [ScaledQuantity.unrounded] (which forces them equal) and
/// [ScaledQuantity.rounded] (which derives displayed from a [RoundingRule]).
/// When the two differ, this rebuilds a rule whose increment is exactly the
/// stored displayed amount: since the domain guarantees `displayed >=
/// exact` and `0 < exact < displayed` is checked below, rounding `exact` up
/// to a multiple of `displayed` always takes exactly one step, landing back
/// on `displayed` exactly. The precondition also catches a corrupt row
/// where that guarantee does not hold — a displayed amount that is not an
/// exact decimal, an exact amount that is zero or negative, or an exact
/// amount that is not strictly less than displayed — before it could
/// silently reconstruct the wrong value.
ScaledQuantity _scaledQuantityFromJson(Map<String, Object?> json) {
  final exact = _quantityFromJson(json['exact']! as Map<String, Object?>);
  final displayed = _quantityFromJson(
    json['displayed']! as Map<String, Object?>,
  );
  if (exact == displayed) return ScaledQuantity.unrounded(exact);

  if (exact.unit != displayed.unit ||
      exact.amount <= Rational.zero ||
      exact.amount >= displayed.amount ||
      !displayed.isExactDecimal) {
    throw CorruptDatabaseError(
      'scaled quantity cannot be rebuilt: exact $exact, displayed $displayed',
    );
  }
  return ScaledQuantity.rounded(
    exact: exact,
    rule: RoundingRule.upToIncrement(displayed.toDecimal()),
  );
}

// --- BatchPlan -------------------------------------------------------------

Map<String, Object?> _batchPlanToJson(BatchPlan plan) => <String, Object?>{
  'fullBatchCount': plan.fullBatchCount,
  'fullBatchYield': _quantityToJson(plan.fullBatchYield),
  'remainderYield': plan.remainderYield == null
      ? null
      : _quantityToJson(plan.remainderYield!),
};

/// Rebuilds a [BatchPlan] from its own stored fields.
///
/// `BatchPlan` has no public constructor besides [BatchPlan.decompose],
/// which recomputes from a target yield and a maximum batch yield rather
/// than accepting the three fields directly. A `target` that decomposes
/// back to the stored triple is reconstructed as
/// `fullBatchYield * fullBatchCount + (remainderYield ?? 0)`, using
/// `fullBatchYield` itself as the maximum: decomposing that target against
/// that maximum always yields exactly `fullBatchCount` full batches and the
/// stored remainder, for any non-negative count and any remainder strictly
/// less than a full batch. The stored triple is verified against the
/// result afterward rather than checked in advance, because a row that
/// does not satisfy that "remainder is smaller than a full batch"
/// assumption fails in several unrelated ways that are simpler to catch by
/// comparing outcomes than by enumerating causes.
BatchPlan _batchPlanFromJson(Map<String, Object?> json) {
  final fullBatchCount = json['fullBatchCount']! as int;
  final fullBatchYield = _quantityFromJson(
    json['fullBatchYield']! as Map<String, Object?>,
  );
  final remainderJson = json['remainderYield'];
  final remainderYield = remainderJson == null
      ? null
      : _quantityFromJson(remainderJson as Map<String, Object?>);

  final remainderOrZero =
      remainderYield ??
      Quantity.fromRational(Rational.zero, fullBatchYield.unit);
  final target =
      fullBatchYield.scaleBy(Rational.fromInt(fullBatchCount)) +
      remainderOrZero;
  final plan = BatchPlan.decompose(
    target: target,
    maxBatchYield: fullBatchYield,
  );

  if (plan.fullBatchCount != fullBatchCount ||
      plan.fullBatchYield != fullBatchYield ||
      plan.remainderYield != remainderYield) {
    throw CorruptDatabaseError(
      'batch plan does not reconstruct: stored $fullBatchCount batches of '
      '$fullBatchYield with remainder $remainderYield',
    );
  }
  return plan;
}

// --- RecipeComponent and its target ---------------------------------------

Map<String, Object?> _componentTargetToJson(ComponentTarget target) =>
    switch (target) {
      IngredientRef(:final ingredientId) => <String, Object?>{
        'kind': 'ingredient',
        'id': ingredientId,
      },
      SubRecipeRef(:final recipeId) => <String, Object?>{
        'kind': 'recipe',
        'id': recipeId,
      },
    };

ComponentTarget _componentTargetFromJson(Map<String, Object?> json) {
  final kind = json['kind'];
  final id = json['id']! as String;
  return switch (kind) {
    'ingredient' => IngredientRef(id),
    'recipe' => SubRecipeRef(id),
    _ => throw CorruptDatabaseError('unknown component target kind: $kind'),
  };
}

/// Encodes [component], mirroring `SqfliteRecipeRepository._componentToRow`
/// field for field. Duplicated rather than shared — see the task report.
Map<String, Object?> _recipeComponentToJson(RecipeComponent component) =>
    <String, Object?>{
      'id': component.id,
      'target': _componentTargetToJson(component.target),
      'baseQuantity': component.baseQuantity == null
          ? null
          : _quantityToJson(component.baseQuantity!),
      'behavior': component.behavior.name,
      'displayOrder': component.displayOrder,
      'roundingIncrement': component.rounding?.increment.toString(),
      'note': component.note,
    };

RecipeComponent _recipeComponentFromJson(Map<String, Object?> json) {
  final behaviorName = json['behavior'];
  final behavior = ScalingBehavior.values.asNameMap()[behaviorName];
  if (behavior == null) {
    throw CorruptDatabaseError('unknown component behavior: $behaviorName');
  }
  final baseQuantityJson = json['baseQuantity'];
  final roundingIncrement = json['roundingIncrement'];
  return RecipeComponent(
    id: json['id']! as String,
    target: _componentTargetFromJson(json['target']! as Map<String, Object?>),
    baseQuantity: baseQuantityJson == null
        ? null
        : _quantityFromJson(baseQuantityJson as Map<String, Object?>),
    behavior: behavior,
    displayOrder: json['displayOrder']! as int,
    rounding: roundingIncrement == null
        ? null
        : RoundingRule.upToIncrement(
            Decimal.parse(roundingIncrement as String),
          ),
    note: json['note'] as String?,
  );
}

// --- Recipe ------------------------------------------------------------

/// Encodes [recipe], mirroring `SqfliteRecipeRepository._recipeFromRow`'s
/// column set as JSON fields. Duplicated rather than shared — see the task
/// report.
Map<String, Object?> _recipeToJson(Recipe recipe) => <String, Object?>{
  'id': recipe.id,
  'revision': recipe.revision,
  'name': recipe.name,
  'category': recipe.category,
  'baseYield': _quantityToJson(recipe.baseYield),
  'maxBatchYield': recipe.maxBatchYield == null
      ? null
      : _quantityToJson(recipe.maxBatchYield!),
  'components': [for (final c in recipe.components) _recipeComponentToJson(c)],
  'preparationNotes': recipe.preparationNotes,
  'modifiedAt': recipe.modifiedAt.toIso8601String(),
  'isArchived': recipe.isArchived,
};

Recipe _recipeFromJson(Map<String, Object?> json) {
  final maxBatchYieldJson = json['maxBatchYield'];
  return Recipe(
    id: json['id']! as String,
    revision: json['revision']! as int,
    name: json['name']! as String,
    category: json['category'] as String?,
    baseYield: _quantityFromJson(json['baseYield']! as Map<String, Object?>),
    maxBatchYield: maxBatchYieldJson == null
        ? null
        : _quantityFromJson(maxBatchYieldJson as Map<String, Object?>),
    components: [
      for (final c in json['components']! as List<Object?>)
        _recipeComponentFromJson(c! as Map<String, Object?>),
    ],
    preparationNotes: [
      for (final note in json['preparationNotes']! as List<Object?>)
        note! as String,
    ],
    modifiedAt: DateTime.parse(json['modifiedAt']! as String),
    isArchived: json['isArchived']! as bool,
  );
}

// --- ScaledComponent and ProductionResult ---------------------------------

Map<String, Object?> _scaledComponentToJson(ScaledComponent component) =>
    <String, Object?>{
      'source': _recipeComponentToJson(component.source),
      'total': component.total == null
          ? null
          : _scaledQuantityToJson(component.total!),
      'perBatch': [
        for (final quantity in component.perBatch)
          if (quantity == null) null else _scaledQuantityToJson(quantity),
      ],
      'subRecipe': component.subRecipe == null
          ? null
          : _resultToJson(component.subRecipe!),
    };

ScaledComponent _scaledComponentFromJson(Map<String, Object?> json) {
  final totalJson = json['total'];
  final subRecipeJson = json['subRecipe'];
  return ScaledComponent(
    source: _recipeComponentFromJson(json['source']! as Map<String, Object?>),
    total: totalJson == null
        ? null
        : _scaledQuantityFromJson(totalJson as Map<String, Object?>),
    perBatch: [
      for (final quantity in json['perBatch']! as List<Object?>)
        if (quantity == null)
          null
        else
          _scaledQuantityFromJson(quantity as Map<String, Object?>),
    ],
    subRecipe: subRecipeJson == null
        ? null
        : _resultFromJson(subRecipeJson as Map<String, Object?>),
  );
}

Map<String, Object?> _resultToJson(
  ProductionResult result,
) => <String, Object?>{
  'scaleRatio': _rationalToJson(result.scaleRatio),
  'batchPlan': _batchPlanToJson(result.batchPlan),
  'components': [for (final c in result.components) _scaledComponentToJson(c)],
  'warnings': [for (final w in result.warnings) _warningToJson(w)],
};

/// Rebuilds a [ProductionResult].
///
/// `batchPlan.fullBatchCount` alone is not enough to catch every corrupt
/// row: [_batchPlanFromJson] reconstructs `target` from the stored count
/// and remainder, so a count mutated together with a still-valid remainder
/// reconstructs a self-consistent (but wrong) plan. Each component's
/// `perBatch` is an independent witness of how many batches the run
/// actually has — the calculator always sizes it to
/// `batchPlan.batchCount` — so comparing the two here catches what
/// [_batchPlanFromJson]'s own check cannot.
ProductionResult _resultFromJson(Map<String, Object?> json) {
  final batchPlan = _batchPlanFromJson(
    json['batchPlan']! as Map<String, Object?>,
  );
  final components = [
    for (final c in json['components']! as List<Object?>)
      _scaledComponentFromJson(c! as Map<String, Object?>),
  ];
  for (final component in components) {
    if (component.perBatch.length != batchPlan.batchCount) {
      throw CorruptDatabaseError(
        'batch plan reports ${batchPlan.batchCount} batches but component '
        '${component.source.id} has ${component.perBatch.length}',
      );
    }
  }
  _checkFullBatchYieldWitness(batchPlan, components);
  return ProductionResult(
    scaleRatio: _rationalFromJson(json['scaleRatio']! as Map<String, Object?>),
    batchPlan: batchPlan,
    components: components,
    warnings: [
      for (final w in json['warnings']! as List<Object?>)
        _warningFromJson(w! as Map<String, Object?>),
    ],
  );
}

/// Cross-checks [batchPlan]'s `fullBatchYield` against an independent
/// witness in [components], when one exists.
///
/// `_batchPlanFromJson` cannot catch a `fullBatchYield` corrupted on its
/// own: it reconstructs `target` from `fullBatchYield` and
/// `fullBatchCount`, so `BatchPlan.decompose` echoes an altered
/// `fullBatchYield` straight back whenever the stored `remainderYield`
/// still satisfies `0 <= remainder < fullBatchYield`. This checks a
/// second, independent source instead: a proportional component's own
/// stored per-batch quantities.
///
/// Per `ProductionCalculator._scale` / `_batchRatios`
/// (`lib/domain/scaling/production_calculator.dart:110-113,199-212`), a
/// proportional component's per-batch exact quantity is
/// `base.scaleBy(ratio * batchRatio)`, where every full batch shares
/// `batchRatio == fullBatchYield.amount / total.amount` and the remainder
/// batch (when there is one) gets `remainderYield.amount / total.amount`,
/// for the same `total = fullBatchYield * fullBatchCount + remainderYield`.
/// Dividing a full batch's quantity by the remainder batch's quantity
/// cancels `base`, the run's scale ratio, and `total`, leaving exactly
/// `fullBatchYield.amount / remainderYield.amount` — a ratio that depends
/// on `fullBatchYield` but was computed from data stored entirely inside
/// the component, not read back from [batchPlan]. Checked here as a
/// cross-multiplication (`full * remainderYield == remainder *
/// fullBatchYield`) so no division or zero-amount special case is needed.
///
/// No witness exists, and this is a deliberate no-op, when there is no
/// remainder batch — every full batch then shares one ratio regardless of
/// `fullBatchYield`'s actual magnitude, so nothing distinguishes a doubled
/// yield from the real one — or when every component is manual, per-batch,
/// or fixed-once, none of which route the batch ratio into their stored
/// quantity at all (`ProductionCalculator._scale`'s other two branches).
/// A run with no such witness is not made to fail a check it cannot
/// possibly satisfy.
void _checkFullBatchYieldWitness(
  BatchPlan batchPlan,
  List<ScaledComponent> components,
) {
  final remainderYield = batchPlan.remainderYield;
  if (remainderYield == null || batchPlan.fullBatchCount < 1) return;

  for (final component in components) {
    if (component.source.behavior != ScalingBehavior.proportional) continue;
    final fullBatch = component.perBatch.first;
    final remainderBatch = component.perBatch.last;
    if (fullBatch == null || remainderBatch == null) continue;

    final lhs = fullBatch.exact.amount * remainderYield.amount;
    final rhs = remainderBatch.exact.amount * batchPlan.fullBatchYield.amount;
    if (lhs != rhs) {
      throw CorruptDatabaseError(
        'batch plan full-batch yield ${batchPlan.fullBatchYield} is '
        "inconsistent with component ${component.source.id}'s per-batch "
        'quantities',
      );
    }
  }
}

// --- ProductionWarning -----------------------------------------------------

/// Encodes [warning] with an explicit `kind` discriminator. `sealed` makes
/// this switch exhaustive: adding a fourth [ProductionWarning] subtype
/// fails `flutter analyze` here until this switch names it.
Map<String, Object?> _warningToJson(ProductionWarning warning) =>
    switch (warning) {
      ManualComponentWarning(:final recipeId, :final componentId) =>
        <String, Object?>{
          'kind': 'manual_component',
          'recipeId': recipeId,
          'componentId': componentId,
        },
      RoundingAdjustedWarning(:final recipeId, :final componentId) =>
        <String, Object?>{
          'kind': 'rounding_adjusted',
          'recipeId': recipeId,
          'componentId': componentId,
        },
      ArchivedDependencyWarning(:final recipeId) => <String, Object?>{
        'kind': 'archived_dependency',
        'recipeId': recipeId,
      },
    };

/// Decodes a warning by its `kind`. An unrecognized kind throws rather than
/// being dropped: a silently dropped blocking warning would make a run
/// that must not be finalized look finalizable, which is the worst failure
/// this layer can produce.
ProductionWarning _warningFromJson(Map<String, Object?> json) {
  final kind = json['kind'];
  return switch (kind) {
    'manual_component' => ManualComponentWarning(
      json['recipeId']! as String,
      json['componentId']! as String,
    ),
    'rounding_adjusted' => RoundingAdjustedWarning(
      json['recipeId']! as String,
      json['componentId']! as String,
    ),
    'archived_dependency' => ArchivedDependencyWarning(
      json['recipeId']! as String,
    ),
    _ => throw CorruptDatabaseError('unknown warning kind: $kind'),
  };
}
