import 'package:meta/meta.dart';

/// Something the operator must see before a run is finalized.
@immutable
sealed class ProductionWarning {
  const ProductionWarning();

  /// Whether the run may not be finalized until this is acknowledged.
  bool get isBlocking;
}

/// A manual component has no numeric result until the operator supplies one.
final class ManualComponentWarning extends ProductionWarning {
  /// Creates the warning for [componentId] of the recipe [recipeId].
  const ManualComponentWarning(this.recipeId, this.componentId);

  /// The recipe the component belongs to.
  ///
  /// A component's id is only unique within one recipe, not globally, so
  /// this is part of the warning's identity: without it, a parent's own
  /// manual component and a same-named manual component in an expanded
  /// sub-recipe would compare equal and collapse into one warning, silently
  /// dropping a distinct problem the operator still has to resolve. It also
  /// lets a presentation layer place the warning inside the right collapsed
  /// sub-recipe.
  final String recipeId;

  /// The component that needs an operator value.
  final String componentId;

  @override
  bool get isBlocking => true;

  @override
  bool operator ==(Object other) =>
      other is ManualComponentWarning &&
      other.recipeId == recipeId &&
      other.componentId == componentId;

  @override
  int get hashCode => Object.hash('manual', recipeId, componentId);
}

/// Display rounding moved a component away from its calculated value.
final class RoundingAdjustedWarning extends ProductionWarning {
  /// Creates the warning for [componentId] of the recipe [recipeId].
  const RoundingAdjustedWarning(this.recipeId, this.componentId);

  /// The recipe the component belongs to. See
  /// [ManualComponentWarning.recipeId] for why a component id alone is not a
  /// safe identity across an expanded tree of recipes.
  final String recipeId;

  /// The component whose displayed value differs from the exact one.
  final String componentId;

  @override
  bool get isBlocking => false;

  @override
  bool operator ==(Object other) =>
      other is RoundingAdjustedWarning &&
      other.recipeId == recipeId &&
      other.componentId == componentId;

  @override
  int get hashCode => Object.hash('rounding', recipeId, componentId);
}

/// A referenced recipe is archived.
final class ArchivedDependencyWarning extends ProductionWarning {
  /// Creates the warning for [recipeId].
  const ArchivedDependencyWarning(this.recipeId);

  /// The archived recipe.
  final String recipeId;

  @override
  bool get isBlocking => true;

  @override
  bool operator ==(Object other) =>
      other is ArchivedDependencyWarning && other.recipeId == recipeId;

  @override
  int get hashCode => Object.hash('archived', recipeId);
}
