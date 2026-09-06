import 'package:prep_book/domain/errors.dart';
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
  /// [recipeIndex] supplies sub-recipes; it is unused until nested expansion
  /// is added.
  ProductionResult calculate({
    required Recipe recipe,
    required Quantity targetYield,
    Map<String, Recipe> recipeIndex = const {},
  }) {
    if (targetYield.isZero) throw InvalidTargetYieldError();
    if (!recipe.baseYield.unit.canConvertTo(targetYield.unit)) {
      throw IncompatibleYieldUnitError(recipe.baseYield.unit, targetYield.unit);
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
        _scale(component, ratio, plan, warnings),
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

    return ScaledComponent(
      source: component,
      total: total,
      perBatch: perBatch,
    );
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

  /// The run's total, whose displayed amount is the sum of the batches'
  /// already-rounded displayed amounts, not a fresh rounding of the exact
  /// total. That keeps a total-oriented view and a batch-oriented view of
  /// the same run in agreement.
  ScaledQuantity _presentTotal(
    RecipeComponent component,
    Quantity exact,
    List<ScaledQuantity> perBatch,
    List<ProductionWarning> warnings,
  ) {
    if (component.rounding == null) return ScaledQuantity.unrounded(exact);

    final displayed = perBatch
        .map((batch) => batch.displayed)
        .reduce(
          (a, b) => a + b,
        );
    final total = ScaledQuantity.withDisplayed(
      exact: exact,
      displayed: displayed,
    );
    if (total.wasRounded) {
      warnings.add(RoundingAdjustedWarning(component.id));
    }
    return total;
  }
}
