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
  /// Creates the warning for [componentId].
  const ManualComponentWarning(this.componentId);

  /// The component that needs an operator value.
  final String componentId;

  @override
  bool get isBlocking => true;

  @override
  bool operator ==(Object other) =>
      other is ManualComponentWarning && other.componentId == componentId;

  @override
  int get hashCode => Object.hash('manual', componentId);
}

/// Display rounding moved a component away from its calculated value.
final class RoundingAdjustedWarning extends ProductionWarning {
  /// Creates the warning for [componentId].
  const RoundingAdjustedWarning(this.componentId);

  /// The component whose displayed value differs from the exact one.
  final String componentId;

  @override
  bool get isBlocking => false;

  @override
  bool operator ==(Object other) =>
      other is RoundingAdjustedWarning && other.componentId == componentId;

  @override
  int get hashCode => Object.hash('rounding', componentId);
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
