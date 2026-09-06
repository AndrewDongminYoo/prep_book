import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('RecipeComponent', () {
    test('a numeric behavior requires a base quantity', () {
      expect(
        () => RecipeComponent(
          id: 'c1',
          target: const IngredientRef('flour'),
          baseQuantity: null,
          behavior: ScalingBehavior.proportional,
          displayOrder: 0,
        ),
        throwsA(isA<InvalidComponentError>()),
      );
    });

    test('a manual component may omit its quantity', () {
      final component = RecipeComponent(
        id: 'c1',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        note: 'to taste',
        displayOrder: 0,
      );
      expect(component.baseQuantity, isNull);
      expect(component.behavior, ScalingBehavior.manual);
    });

    test('a manual component may not carry a base quantity', () {
      expect(
        () => RecipeComponent(
          id: 'c1',
          target: const IngredientRef('salt'),
          baseQuantity: Quantity.parse('1', Unit.gram),
          behavior: ScalingBehavior.manual,
          displayOrder: 0,
        ),
        throwsA(isA<InvalidComponentError>()),
      );
    });

    test('an ingredient carries its display name and default unit', () {
      final ingredient = Ingredient(
        id: 'flour',
        name: 'Bread flour',
        defaultUnit: Unit.kilogram,
        category: 'Dry goods',
      );
      expect(ingredient.name, 'Bread flour');
      expect(ingredient.defaultUnit, Unit.kilogram);
      expect(ingredient.category, 'Dry goods');
    });

    test('targets compare by their referenced identifier', () {
      expect(const IngredientRef('flour'), const IngredientRef('flour'));
      expect(const SubRecipeRef('dough'), isNot(const IngredientRef('dough')));
    });

    test('sub-recipe targets compare by their referenced identifier', () {
      expect(const SubRecipeRef('dough'), const SubRecipeRef('dough'));
      expect(const SubRecipeRef('dough'), isNot(const SubRecipeRef('bread')));
    });

    test('equal targets share a hash code', () {
      expect(
        const IngredientRef('flour').hashCode,
        const IngredientRef('flour').hashCode,
      );
      expect(
        const SubRecipeRef('dough').hashCode,
        const SubRecipeRef('dough').hashCode,
      );
    });
  });
}
