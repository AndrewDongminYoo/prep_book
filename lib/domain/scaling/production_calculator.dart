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
  /// Creates a calculator. It holds no state.
  const ProductionCalculator();

  /// Scales [recipe] to [targetYield].
  ///
  /// [recipeIndex] supplies sub-recipes so a [SubRecipeRef] component can be
  /// expanded recursively; a component's nested warnings are lifted into the
  /// returned result's [ProductionResult.warnings]. An empty [recipeIndex]
  /// (the default) opts out of expansion entirely: every [SubRecipeRef]
  /// component comes back with a null [ScaledComponent.subRecipe] and no
  /// validation runs. A non-empty [recipeIndex] is validated up front,
  /// keyed by each recipe's own id — [recipe] itself must be one of the
  /// entries, or this throws [MissingDependencyError] before any component
  /// is scaled — and also throws [RecipeCycleError] if [recipe] cannot be
  /// resolved into a finite tree.
  ProductionResult calculate({
    required Recipe recipe,
    required Quantity targetYield,
    Map<String, Recipe> recipeIndex = const {},
  }) {
    if (targetYield.isZero) throw InvalidTargetYieldError();
    if (!recipe.baseYield.unit.canConvertTo(targetYield.unit)) {
      throw IncompatibleYieldUnitError(recipe.baseYield.unit, targetYield.unit);
    }
    if (recipeIndex.isNotEmpty) {
      RecipeDependencyGraph(recipeIndex).assertResolvable(recipe.id);
    }

    final target = targetYield.convertTo(recipe.baseYield.unit);
    final ratio = target.amount / recipe.baseYield.amount;
    final plan = BatchPlan.decompose(
      target: target,
      maxBatchYield: recipe.maxBatchYield,
    );

    final warnings = <ProductionWarning>[];
    final components = [
      for (final component in recipe.components)
        _scale(component, ratio, plan, recipeIndex, warnings),
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
    List<ProductionWarning> warnings,
  ) {
    // A null base quantity means manual; RecipeComponent guarantees it.
    final base = component.baseQuantity;
    if (base == null) {
      warnings.add(ManualComponentWarning(component.id));
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
    final total = _presentTotal(component, totalExact, perBatch, warnings);

    final expanded = switch (component.target) {
      SubRecipeRef(:final recipeId) => _expand(
        recipeId,
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
  /// warnings into the parent's [warnings], or returns null when [recipeId]
  /// is absent from [recipeIndex]. See [calculate] for when that lookup can
  /// fail versus when it is expected to.
  ProductionResult? _expand(
    String recipeId,
    Quantity requiredYield,
    Map<String, Recipe> recipeIndex,
    List<ProductionWarning> warnings,
  ) {
    final child = recipeIndex[recipeId];
    if (child == null) return null;
    if (child.isArchived) {
      warnings.add(ArchivedDependencyWarning(recipeId));
    }

    final nested = calculate(
      recipe: child,
      targetYield: requiredYield,
      recipeIndex: recipeIndex,
    );
    warnings.addAll(nested.warnings);
    return nested;
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

  /// The run's total, summed from the batches rather than freshly rounded
  /// from the exact total. That keeps a total-oriented view and a
  /// batch-oriented view of the same run in agreement.
  ScaledQuantity _presentTotal(
    RecipeComponent component,
    Quantity exact,
    List<ScaledQuantity> perBatch,
    List<ProductionWarning> warnings,
  ) {
    if (component.rounding == null) return ScaledQuantity.unrounded(exact);

    final total = ScaledQuantity.summing(perBatch);
    if (total.wasRounded) {
      warnings.add(RoundingAdjustedWarning(component.id));
    }
    return total;
  }
}
