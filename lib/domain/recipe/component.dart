import 'package:meta/meta.dart';
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/recipe/scaling_behavior.dart';
import 'package:prep_book/domain/units/quantity.dart';
import 'package:prep_book/domain/units/rounding.dart';

/// What a component points at.
@immutable
sealed class ComponentTarget {
  const ComponentTarget();
}

/// A component that consumes a library ingredient.
final class IngredientRef extends ComponentTarget {
  /// Creates a reference to [ingredientId].
  const IngredientRef(this.ingredientId);

  /// The referenced ingredient.
  final String ingredientId;

  @override
  bool operator ==(Object other) =>
      other is IngredientRef && other.ingredientId == ingredientId;

  @override
  int get hashCode => Object.hash('ingredient', ingredientId);
}

/// A component that consumes the output of another recipe.
final class SubRecipeRef extends ComponentTarget {
  /// Creates a reference to [recipeId].
  const SubRecipeRef(this.recipeId);

  /// The referenced recipe.
  final String recipeId;

  @override
  bool operator ==(Object other) =>
      other is SubRecipeRef && other.recipeId == recipeId;

  @override
  int get hashCode => Object.hash('recipe', recipeId);
}

/// One line of a recipe.
@immutable
final class RecipeComponent {
  /// Creates a component, rejecting combinations the domain forbids.
  factory RecipeComponent({
    required String id,
    required ComponentTarget target,
    required Quantity? baseQuantity,
    required ScalingBehavior behavior,
    required int displayOrder,
    RoundingRule? rounding,
    String? note,
  }) {
    if (behavior != ScalingBehavior.manual && baseQuantity == null) {
      throw InvalidComponentError(
        id,
        'a ${behavior.name} component needs a base quantity',
      );
    }
    // A null base quantity means exactly "manual". The calculator relies on
    // that equivalence to branch without an unreachable case.
    if (behavior == ScalingBehavior.manual && baseQuantity != null) {
      throw InvalidComponentError(
        id,
        'a manual component may not carry a base quantity',
      );
    }
    return RecipeComponent._(
      id: id,
      target: target,
      baseQuantity: baseQuantity,
      behavior: behavior,
      displayOrder: displayOrder,
      rounding: rounding,
      note: note,
    );
  }

  const RecipeComponent._({
    required this.id,
    required this.target,
    required this.baseQuantity,
    required this.behavior,
    required this.displayOrder,
    required this.rounding,
    required this.note,
  });

  /// Stable identifier, unique within the recipe.
  final String id;

  /// The ingredient or recipe this line consumes.
  final ComponentTarget target;

  /// The amount written in the recipe, absent only for a manual line.
  final Quantity? baseQuantity;

  /// How the amount responds to a production run.
  final ScalingBehavior behavior;

  /// Optional display rounding.
  final RoundingRule? rounding;

  /// Optional note for the operator.
  final String? note;

  /// Position in the recipe.
  final int displayOrder;
}
