import 'package:meta/meta.dart';
import 'package:prep_book/domain/recipe/component.dart';
import 'package:prep_book/domain/scaling/batch_plan.dart';
import 'package:prep_book/domain/units/rounding.dart';
import 'package:prep_book/domain/warnings.dart';
import 'package:rational/rational.dart';

/// One calculated line of a production result.
@immutable
final class ScaledComponent {
  /// Creates a calculated line, taking its own copy of [perBatch] so a
  /// stored result can never be mutated through the caller's list.
  factory ScaledComponent({
    required RecipeComponent source,
    required ScaledQuantity? total,
    required List<ScaledQuantity?> perBatch,
    ProductionResult? subRecipe,
  }) => ScaledComponent._(
    source: source,
    total: total,
    perBatch: List.unmodifiable(perBatch),
    subRecipe: subRecipe,
  );

  const ScaledComponent._({
    required this.source,
    required this.total,
    required this.perBatch,
    this.subRecipe,
  });

  /// The recipe line this row was calculated from.
  final RecipeComponent source;

  /// The total for the whole run, absent for an unresolved manual line.
  final ScaledQuantity? total;

  /// The amount for each batch, in batch order.
  final List<ScaledQuantity?> perBatch;

  /// The expanded result when this line references another recipe.
  final ProductionResult? subRecipe;
}

/// The outcome of scaling one recipe to a target yield.
@immutable
final class ProductionResult {
  /// Creates a production result.
  ProductionResult({
    required this.scaleRatio,
    required this.batchPlan,
    required List<ScaledComponent> components,
    required List<ProductionWarning> warnings,
  }) : components = List.unmodifiable(components),
       warnings = List.unmodifiable(warnings);

  /// The proportional ratio, target over base.
  final Rational scaleRatio;

  /// How the run splits into batches.
  final BatchPlan batchPlan;

  /// The calculated lines, in the recipe's display order.
  final List<ScaledComponent> components;

  /// Everything the operator must see, including nested recipes' warnings.
  final List<ProductionWarning> warnings;

  /// Whether any warning must be acknowledged before finalizing.
  bool get hasBlockingWarnings => warnings.any((w) => w.isBlocking);
}
