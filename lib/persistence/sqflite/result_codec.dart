import 'dart:convert';

import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';
import 'package:prep_book/persistence/sqflite/timestamps.dart';

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

/// Rebuilds a [RunPayload] from [json], as produced by [encodeRunPayload],
/// naming the row it was read from as [rowLabel] if it cannot.
///
/// Throws [CorruptDatabaseError] when [json] is not valid JSON, does not
/// have the shape a run payload has, or names a warning kind, component
/// target kind, or scaling behavior this decoder does not recognize. An
/// unrecognized warning kind is never dropped — a silently dropped blocking
/// warning would make a run that must not be finalized look finalizable.
///
/// [rowLabel] is required because nothing below this function knows which
/// stored run it is decoding. The helpers it calls are handed a fragment of
/// JSON and can name only a position inside the payload, so every
/// [CorruptDatabaseError] raised while decoding the payload is labelled with
/// the row here. Every value decoded inside this function came out of one
/// `production_runs` row, so that label is always the right one — this is
/// not one row's failure being relabelled as another's.
///
/// Every message this function can raise names the row, which is what
/// [CorruptDatabaseError]'s own "always names the row" contract requires
/// without qualification. Five of them do not get there through the clause:
/// `result_json` that does not parse at all is raised before the labelling
/// block starts, an unrecognized warning kind is named at its own level, and
/// the three messages the `on TypeError`, `on FormatException`, and
/// `on DomainError` clauses build interpolate [rowLabel] themselves — a
/// throw from inside a catch clause leaves the whole try statement rather
/// than reaching the sibling clause beside it, so the clause could never
/// have labelled those three. The clause skips any message that already
/// carries the label, so none of the five is named twice.
RunPayload decodeRunPayload(String json, {required String rowLabel}) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (error) {
    throw CorruptDatabaseError(
      'run payload of $rowLabel is not valid JSON: $error',
    );
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
      result: _resultFromJson(
        map['result']! as Map<String, Object?>,
        rowLabel: rowLabel,
      ),
    );
    // A cast failure here is Dart's `TypeError`, thrown for a `Map` whose
    // shape does not match, a missing key forced non-null by `!`, or a
    // `null` payload. The brief calls for exactly this: any cast failure
    // from decoded JSON is a corrupt row, not a programmer bug.
    // ignore: avoid_catching_errors
  } on TypeError catch (error) {
    throw CorruptDatabaseError(
      'run payload of $rowLabel has an unexpected shape: $error',
    );
  } on FormatException catch (error) {
    // Reached by `Decimal.parse` on a component's rounding increment and by
    // `DateTime.parse` on a recipe's `modifiedAt` — the two payload values
    // stored as text and parsed back. Neither failure is a `TypeError`, so
    // neither is caught above. `jsonDecode`'s own `FormatException` cannot
    // arrive here: it is raised and handled in the separate block above,
    // which completes before this one starts.
    throw CorruptDatabaseError(
      'run payload of $rowLabel holds an unparseable value: $error',
    );
  } on DomainError catch (error) {
    // A stored value that is well-typed and parses cleanly, and that the
    // domain still refuses. Every domain factory this decoder calls is
    // inside this one try block — `Quantity`, `Recipe`, `RecipeComponent`,
    // `RoundingRule`, `ScaledQuantity`, and `BatchPlan.decompose` — so one
    // clause labels whatever any of them rejects, rather than each site
    // needing a guard of its own. `failure_paths_test.dart` reaches it with
    // a negative amount on a payload's base yield.
    //
    // `DomainError` is `sealed class DomainError implements Exception`, so
    // it is neither a `TypeError` nor a `FormatException` and needs no
    // `avoid_catching_errors` ignore, unlike the clause above.
    throw CorruptDatabaseError(
      'run payload of $rowLabel holds a value the domain rejects: $error',
    );
  } on CorruptDatabaseError catch (error) {
    // The labelling clause described in this function's doc comment. It sees
    // only what the try body raised: the three clauses above throw from
    // inside a catch clause, which leaves the try statement instead of
    // reaching a sibling, so they carry the row in their own text rather
    // than through here — `result_codec_test.dart` pins that with
    // `startsWith` on the label-plus-message form, which a re-labelled
    // message would fail.
    //
    // It is also why the clause above names `DomainError` and not
    // `Exception`: a [CorruptDatabaseError] is an `Exception` too, so a
    // clause one word wider would catch the failures the payload's own
    // helpers already labelled and prefix the row a second time.
    //
    // The row is added only when the message does not already carry it, so a
    // failure that names the row at its own level (an unrecognized warning
    // kind) is not made to name it twice — a message naming two rows reads
    // as a failure spanning two rows.
    if (error.message.contains(rowLabel)) rethrow;
    throw CorruptDatabaseError('$rowLabel: ${error.message}');
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
  unitFromStorage(json['u']! as String, location: 'a run payload quantity'),
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

/// Encodes [target] with the same two `kind` strings
/// `SqfliteRecipeRepository._componentToRow` writes into `target_kind`,
/// which that method's comment explains and which the two must keep
/// identical.
Map<String, Object?> _componentTargetToJson(ComponentTarget target) =>
    switch (target) {
      IngredientRef(:final ingredientId) => <String, Object?>{
        'kind': 'ingredient',
        'id': ingredientId,
      },
      SubRecipeRef(:final recipeId) => <String, Object?>{
        'kind': 'sub_recipe',
        'id': recipeId,
      },
    };

ComponentTarget _componentTargetFromJson(Map<String, Object?> json) {
  final kind = json['kind'];
  final id = json['id']! as String;
  return switch (kind) {
    'ingredient' => IngredientRef(id),
    'sub_recipe' => SubRecipeRef(id),
    _ => throw CorruptDatabaseError('unknown component target kind: $kind'),
  };
}

/// Encodes [component], mirroring `SqfliteRecipeRepository._componentToRow`
/// field for field.
///
/// The two are deliberately separate, and a field added to
/// `RecipeComponent` has to be added to both. Sharing them was ruled
/// deferrable rather than wrong: this one writes a value frozen inside a
/// run snapshot while the other writes the columns of a `recipe_components`
/// row that later revisions keep rewriting, so a change to the row shape
/// must not be able to reach a payload already stored. This comment is the
/// mitigation for the duplication until a shared encoder earns its own
/// change.
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

/// Encodes [recipe], mirroring the column set `SqfliteRecipeRepository`
/// writes in `saveRevision` and reads back in `_recipeFromRow`.
///
/// Deliberately separate from that mapping, for the reason given on
/// [_recipeComponentToJson]: a field added to `Recipe` has to be added
/// here and there, and the pairing is stated in both places so neither can
/// be changed alone without the other being visible.
///
/// `modifiedAt` goes through [timestampToStorage], the one writer the
/// `recipes.modified_at` and `production_runs.created_at` columns also use,
/// so the three stored forms cannot drift apart. A caller supplies whatever
/// `DateTime` it holds and `DateTime.now()` is local, so leaving it alone
/// would store a wall clock that re-anchors when read in another zone — and
/// would make the same recipe read back through
/// `SqfliteRecipeRepository.findRevision` and through a run payload compare
/// unequal, since `DateTime`'s `==` includes the `isUtc` flag, while both
/// denote the same instant.
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
  'modifiedAt': timestampToStorage(recipe.modifiedAt),
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

/// Rebuilds a [ScaledComponent], including the nested result of an expanded
/// sub-recipe when the component has one.
///
/// [rowLabel] is carried only so that nested result's own warnings can still
/// name the stored run they came out of; nothing else here uses it.
ScaledComponent _scaledComponentFromJson(
  Map<String, Object?> json, {
  required String rowLabel,
}) {
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
        : _resultFromJson(
            subRecipeJson as Map<String, Object?>,
            rowLabel: rowLabel,
          ),
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
///
/// [rowLabel] is threaded through only to reach [_warningFromJson], whose
/// failure names no position inside the payload and so needs the row.
ProductionResult _resultFromJson(
  Map<String, Object?> json, {
  required String rowLabel,
}) {
  final batchPlan = _batchPlanFromJson(
    json['batchPlan']! as Map<String, Object?>,
  );
  final components = [
    for (final c in json['components']! as List<Object?>)
      _scaledComponentFromJson(c! as Map<String, Object?>, rowLabel: rowLabel),
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
  _checkComponentTotalWitness(components);

  final scaleRatio = _rationalFromJson(
    json['scaleRatio']! as Map<String, Object?>,
  );
  _checkScaleRatioWitness(scaleRatio, components);

  return ProductionResult(
    scaleRatio: scaleRatio,
    batchPlan: batchPlan,
    components: components,
    warnings: [
      for (final w in json['warnings']! as List<Object?>)
        _warningFromJson(w! as Map<String, Object?>, rowLabel: rowLabel),
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

/// Cross-checks every component's `total` against its own per-batch
/// quantities.
///
/// [_scaledComponentFromJson] decodes `total` independently of `perBatch`,
/// so a `total` altered on its own decodes cleanly and is handed back as a
/// valid production quantity — the same blind spot
/// [_checkFullBatchYieldWitness] exists for, with the per-batch list as the
/// independent witness this time.
///
/// Per `ProductionCalculator._presentTotal`
/// (`lib/domain/scaling/production_calculator.dart:221-242`), a component
/// with no rounding rule takes the exact sum of its per-batch amounts and
/// displays that sum unchanged, while one with a rule takes
/// `ScaledQuantity.summing(perBatch)`, which sums the exact and the
/// displayed amounts independently. Either way the total is the sum of the
/// per-batch values on both sides, for all three numeric behaviors: every
/// branch of `_scale` builds its per-batch list out of the same `base`, so
/// the parts always share one unit and the sum needs no conversion.
///
/// A manual component has no total and no witness — `_scale` returns it
/// with a null total and an all-null per-batch list — so absence is checked
/// for agreeing with absence instead.
void _checkComponentTotalWitness(List<ScaledComponent> components) {
  for (final component in components) {
    final total = component.total;
    final batches = component.perBatch;
    final resolved = batches.whereType<ScaledQuantity>().toList();

    if (total == null) {
      if (resolved.isNotEmpty) {
        throw CorruptDatabaseError(
          'component ${component.source.id} has no total but carries '
          '${resolved.length} per-batch quantities',
        );
      }
      continue;
    }

    // `isEmpty` is what keeps `summing` — which rejects an empty iterable
    // with an `ArgumentError` rather than a [CorruptDatabaseError] — off a
    // batch plan corrupted down to zero batches.
    if (resolved.length != batches.length || batches.isEmpty) {
      throw CorruptDatabaseError(
        'component ${component.source.id} has a total, but its per-batch '
        'quantities do not witness it: ${resolved.length} of '
        '${batches.length} are present',
      );
    }

    final witness = ScaledQuantity.summing(resolved);
    if (witness.exact != total.exact || witness.displayed != total.displayed) {
      throw CorruptDatabaseError(
        'component ${component.source.id} stores a total of ${total.exact} '
        'exact and ${total.displayed} displayed, but its per-batch '
        'quantities sum to ${witness.exact} and ${witness.displayed}',
      );
    }
  }
}

/// Cross-checks [scaleRatio] against the components it scaled.
///
/// [_rationalFromJson] rebuilds the ratio from its own numerator and
/// denominator, so an altered ratio decodes cleanly and nothing else
/// decoded from the payload contradicts it — the third instance of the
/// blind spot the two witnesses above cover.
///
/// A proportional component's own stored total is the witness. Per
/// `ProductionCalculator.calculate` and `_scale`
/// (`lib/domain/scaling/production_calculator.dart:47-62,110-115`), such a
/// component's per-batch exact quantities are `base.scaleBy(ratio *
/// batchRatio)` and its exact total is their sum, while `_batchRatios`
/// yields ratios summing to exactly one — every full batch contributes
/// `fullBatchYield / target` and the remainder `remainderYield / target`,
/// for a target that is their sum. The exact total is therefore
/// `base.scaleBy(ratio)`, reached from data stored inside the component
/// rather than read back from `scaleRatio`.
///
/// The other two numeric behaviors carry no witness and are skipped
/// deliberately, the way [_checkFullBatchYieldWitness] skips a run with no
/// remainder batch: `_scale` fills a per-batch component's batches with
/// `base` itself and a fixed-once component's with `base` and zeroes, so
/// neither routes the ratio into a stored quantity at all. The null guard
/// covers what the types allow rather than what a payload can reach — a
/// numeric component with no base quantity, or a proportional one with no
/// total, is rejected while its `source` is still being decoded.
void _checkScaleRatioWitness(
  Rational scaleRatio,
  List<ScaledComponent> components,
) {
  for (final component in components) {
    if (component.source.behavior != ScalingBehavior.proportional) continue;
    final base = component.source.baseQuantity;
    final total = component.total;
    if (base == null || total == null) continue;

    final witness = base.scaleBy(scaleRatio);
    if (total.exact != witness) {
      throw CorruptDatabaseError(
        'scale ratio $scaleRatio is inconsistent with component '
        "${component.source.id}'s exact total: $witness was expected, "
        '${total.exact} was stored',
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
///
/// The failure names [rowLabel] because a warning kind carries no position
/// of its own — nothing in the message would otherwise say which stored run
/// must be repaired.
ProductionWarning _warningFromJson(
  Map<String, Object?> json, {
  required String rowLabel,
}) {
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
    _ => throw CorruptDatabaseError('unknown warning kind in $rowLabel: $kind'),
  };
}
