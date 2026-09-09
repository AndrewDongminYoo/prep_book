import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/graph/recipe_dependency_graph.dart';
import 'package:prep_book/domain/recipe/component.dart';
import 'package:prep_book/domain/recipe/recipe.dart';
import 'package:prep_book/domain/recipe/scaling_behavior.dart';
import 'package:prep_book/domain/scaling/batch_plan.dart';
import 'package:prep_book/domain/scaling/scaled_component.dart';
import 'package:prep_book/domain/units/quantity.dart';
import 'package:prep_book/domain/units/rounding.dart';
import 'package:prep_book/domain/warnings.dart';
import 'package:rational/rational.dart';

/// Turns a recipe and a target yield into an exact production result.
final class ProductionCalculator {
  /// Creates a calculator. It holds no state beyond [maxPlannedBatches].
  const ProductionCalculator({this.maxPlannedBatches});

  /// The largest number of batches any one recipe in a run may be split
  /// into, or `null` — the default — for no bound at all.
  ///
  /// The bound is what a caller spends to keep a calculation's cost
  /// knowable, and it applies to every batch plan the run builds rather
  /// than to the root's alone: a sub-recipe is scaled to whatever its
  /// parent's component total demands, against its own maximum batch
  /// yield, so it is where an unbounded plan actually appears. The check
  /// runs immediately after each plan is decomposed and before anything is
  /// allocated against it, so a refused plan costs one comparison rather
  /// than one entry per batch per component.
  ///
  /// Positive by contract. A caller that passes zero or less refuses every
  /// run, which is not a state worth a guard of its own.
  final int? maxPlannedBatches;

  /// Scales [recipe] to [targetYield].
  ///
  /// [recipeIndex] supplies sub-recipes so a [SubRecipeRef] component can be
  /// expanded recursively; a component's nested warnings are lifted into the
  /// returned result's [ProductionResult.warnings]. The dependency graph
  /// (with [recipe] itself injected under its own id, so a caller never has
  /// to include the root) is always validated before any component is
  /// scaled, throwing [RecipeCycleError] or [MissingDependencyError] if
  /// [recipe] cannot be resolved into a finite tree — a missing dependency
  /// makes the calculation impossible, so it is a hard error. An archived
  /// dependency is different: the calculation can still run, so it expands
  /// normally and instead raises a blocking [ArchivedDependencyWarning] the
  /// operator must acknowledge before the run is finalized. The same check
  /// applies to [recipe] itself, not only to a sub-recipe it references —
  /// a run computed straight from an archived recipe raises the warning
  /// too.
  ///
  /// Throws [BatchLimitExceededError] when [maxPlannedBatches] is set and
  /// this recipe, or any sub-recipe expanded under it, splits into more
  /// batches than that.
  ProductionResult calculate({
    required Recipe recipe,
    required Quantity targetYield,
    Map<String, Recipe> recipeIndex = const {},
  }) {
    if (targetYield.isZero) throw InvalidTargetYieldError();
    if (!recipe.baseYield.unit.canConvertTo(targetYield.unit)) {
      throw IncompatibleYieldUnitError(recipe.baseYield.unit, targetYield.unit);
    }
    RecipeDependencyGraph({
      ...recipeIndex,
      recipe.id: recipe,
    }).assertResolvable(recipe.id);

    final target = targetYield.convertTo(recipe.baseYield.unit);
    final ratio = target.amount / recipe.baseYield.amount;
    final plan = BatchPlan.decompose(
      target: target,
      maxBatchYield: recipe.maxBatchYield,
    );
    final limit = maxPlannedBatches;
    // `fullBatchCount` is compared first rather than folded into a single
    // test on `batchCount`, and the order is load-bearing: `BatchPlan`
    // derives the full count from a `BigInt` through `toInt`, which clamps
    // to the largest int instead of failing, so a target large enough to
    // clamp it leaves `batchCount` — that value plus a remainder batch —
    // wrapped to a negative number that no upper bound rejects. Once the
    // full count is known to be inside the limit, the sum cannot wrap.
    if (limit != null &&
        (plan.fullBatchCount > limit || plan.batchCount > limit)) {
      throw BatchLimitExceededError(recipe.id, limit);
    }

    final warnings = <ProductionWarning>[];
    if (recipe.isArchived) {
      _addUnique(warnings, ArchivedDependencyWarning(recipe.id));
    }
    final components = [
      for (final component in recipe.components)
        _scale(component, ratio, plan, recipeIndex, recipe.id, warnings),
    ];

    return ProductionResult(
      scaleRatio: ratio,
      batchPlan: plan,
      components: components,
      warnings: warnings,
    );
  }

  ScaledComponent _scale(
    RecipeComponent component,
    Rational ratio,
    BatchPlan plan,
    Map<String, Recipe> recipeIndex,
    String recipeId,
    List<ProductionWarning> warnings,
  ) {
    // A null base quantity means manual; RecipeComponent guarantees it.
    final base = component.baseQuantity;
    if (base == null) {
      _addUnique(warnings, ManualComponentWarning(recipeId, component.id));
      // A manual line has no total to expand a sub-recipe against, so it
      // never reaches _expand — the only other place an archived reference
      // is reported. Archival is a property of the reference itself rather
      // than of the numbers, so it is checked here too; the index lookup is
      // safe for the reason _expand gives below.
      if (component.target case SubRecipeRef(
        recipeId: final targetRecipeId,
      ) when recipeIndex[targetRecipeId]!.isArchived) {
        _addUnique(warnings, ArchivedDependencyWarning(targetRecipeId));
      }
      return ScaledComponent(
        source: component,
        total: null,
        perBatch: List.filled(plan.batchCount, null),
      );
    }

    final List<Quantity> perBatchExact;
    if (component.behavior == ScalingBehavior.perBatch) {
      perBatchExact = List.filled(plan.batchCount, base);
    } else if (component.behavior == ScalingBehavior.fixedOnce) {
      perBatchExact = [
        base,
        for (var i = 1; i < plan.batchCount; i++)
          Quantity.fromRational(Rational.zero, base.unit),
      ];
    } else {
      perBatchExact = [
        for (final batchRatio in _batchRatios(plan))
          base.scaleBy(ratio * batchRatio),
      ];
    }

    final perBatch = [
      for (final value in perBatchExact) _presentBatch(component, value),
    ];
    final totalExact = perBatchExact.reduce((a, b) => a + b);
    final total = _presentTotal(
      component,
      totalExact,
      perBatch,
      recipeId,
      warnings,
    );

    final expanded = switch (component.target) {
      SubRecipeRef(recipeId: final targetRecipeId) => _expand(
        targetRecipeId,
        total.displayed,
        recipeIndex,
        warnings,
      ),
      IngredientRef() => null,
    };

    return ScaledComponent(
      source: component,
      total: total,
      perBatch: perBatch,
      subRecipe: expanded,
    );
  }

  /// Scales the recipe [recipeId] points at to [requiredYield] and folds its
  /// warnings into the parent's [warnings], de-duplicating a warning that is
  /// already present — a sub-recipe referenced more than once by the same
  /// parent must not report the same problem twice.
  ///
  /// Recurses through `calculate` on this same calculator, so
  /// [maxPlannedBatches] bounds the expanded plan exactly as it bounds the
  /// root's. That is the whole point of holding the bound on the calculator
  /// rather than passing it to one call: a nested plan is where a target
  /// the root absorbs in a single batch turns into millions.
  ProductionResult _expand(
    String recipeId,
    Quantity requiredYield,
    Map<String, Recipe> recipeIndex,
    List<ProductionWarning> warnings,
  ) {
    // calculate already validated the dependency graph — with the current
    // recipe injected under its own id — before scaling any component, so
    // every direct sub-recipe reference is guaranteed present here.
    final child = recipeIndex[recipeId]!;
    if (child.isArchived) {
      _addUnique(warnings, ArchivedDependencyWarning(recipeId));
    }

    final nested = calculate(
      recipe: child,
      targetYield: requiredYield,
      recipeIndex: recipeIndex,
    );
    for (final warning in nested.warnings) {
      _addUnique(warnings, warning);
    }
    return nested;
  }

  /// Appends [warning] to [warnings] unless an equal warning is already
  /// there. Every warning this calculator adds — a component's own, or one
  /// lifted from an expanded sub-recipe — goes through this, so an
  /// identical warning is reported once regardless of whether it was
  /// produced directly or through expansion, or in what order the two
  /// arrive. [ManualComponentWarning] and [RoundingAdjustedWarning] compare
  /// by their recipe id together with their component id, so two warnings
  /// are equal only when both the recipe and the component match — the
  /// same sub-recipe referenced twice collapses to one warning, while a
  /// same-named component in a different recipe stays distinct.
  /// [ArchivedDependencyWarning] compares by recipe id alone, so one recipe
  /// can produce two equal ones for itself with no expansion involved: two
  /// manual lines naming the same archived sub-recipe raise the warning
  /// twice, and this is what collapses them. The other two carry a
  /// component id that is unique within its own recipe, so a single recipe
  /// cannot produce two equal warnings of those kinds — routing a
  /// component's own warning through here changes nothing for them until
  /// expansion is involved.
  void _addUnique(List<ProductionWarning> warnings, ProductionWarning warning) {
    if (!warnings.contains(warning)) warnings.add(warning);
  }

  /// Each batch's share of the whole run, in batch order.
  Iterable<Rational> _batchRatios(BatchPlan plan) sync* {
    final whole = plan.fullBatchYield.scaleBy(
      Rational.fromInt(plan.fullBatchCount),
    );
    final remainder = plan.remainderYield;
    final total = remainder == null ? whole : whole + remainder;

    for (var i = 0; i < plan.fullBatchCount; i++) {
      yield plan.fullBatchYield.amount / total.amount;
    }
    if (remainder != null) {
      yield remainder.amount / total.amount;
    }
  }

  /// One batch's displayed amount, rounded independently of the total.
  ScaledQuantity _presentBatch(RecipeComponent component, Quantity exact) {
    final rule = component.rounding;
    if (rule == null) return ScaledQuantity.unrounded(exact);
    return ScaledQuantity.rounded(exact: exact, rule: rule);
  }

  /// The run's total for [component].
  ///
  /// A component with no rounding rule returns the unrounded exact total
  /// directly, the same as [_presentBatch]. When a rule is set, the total is
  /// summed from the already-rounded batches rather than freshly rounded
  /// from the exact total, so a total-oriented view and a batch-oriented
  /// view of the same run never disagree.
  ScaledQuantity _presentTotal(
    RecipeComponent component,
    Quantity exact,
    List<ScaledQuantity> perBatch,
    String recipeId,
    List<ProductionWarning> warnings,
  ) {
    if (component.rounding == null) return ScaledQuantity.unrounded(exact);

    final total = ScaledQuantity.summing(perBatch);
    if (total.wasRounded) {
      _addUnique(warnings, RoundingAdjustedWarning(recipeId, component.id));
    }
    return total;
  }
}
