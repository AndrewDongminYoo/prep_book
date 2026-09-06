import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe dough({bool isArchived = false}) {
  return Recipe(
    id: 'dough',
    revision: 1,
    name: 'Dough',
    baseYield: Quantity.parse('2', Unit.kilogram),
    isArchived: isArchived,
    components: [
      RecipeComponent(
        id: 'dough-flour',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1.2', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'dough-salt',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

Recipe pie() {
  return Recipe(
    id: 'pie',
    revision: 1,
    name: 'Pie',
    baseYield: Quantity.parse('4', Unit.portion),
    components: [
      RecipeComponent(
        id: 'pie-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  const calculator = ProductionCalculator();

  group('nested recipes', () {
    test('expands a sub-recipe against the parent quantity', () {
      final result = calculator.calculate(
        recipe: pie(),
        targetYield: Quantity.parse('8', Unit.portion),
        recipeIndex: {'dough': dough(), 'pie': pie()},
      );

      final line = result.components.single;
      expect(line.total!.exact, Quantity.parse('2', Unit.kilogram));

      final nested = line.subRecipe!;
      expect(nested.scaleRatio, Rational.one);
      expect(
        nested.components.first.total!.exact,
        Quantity.parse('1.2', Unit.kilogram),
      );
      expect(
        result.warnings,
        isNot(contains(isA<ArchivedDependencyWarning>())),
      );
    });

    test('lifts a nested blocking warning into the parent', () {
      final result = calculator.calculate(
        recipe: pie(),
        targetYield: Quantity.parse('8', Unit.portion),
        recipeIndex: {'dough': dough(), 'pie': pie()},
      );
      expect(result.warnings, contains(isA<ManualComponentWarning>()));
      expect(result.hasBlockingWarnings, isTrue);
    });

    test('warns when a dependency is archived', () {
      final result = calculator.calculate(
        recipe: pie(),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough(isArchived: true), 'pie': pie()},
      );
      expect(
        result.warnings,
        contains(const ArchivedDependencyWarning('dough')),
      );
      expect(result.hasBlockingWarnings, isTrue);
    });

    test('rejects a cycle before calculating', () {
      final a = Recipe(
        id: 'a',
        revision: 1,
        name: 'A',
        baseYield: Quantity.parse('1', Unit.portion),
        components: [
          RecipeComponent(
            id: 'a-b',
            target: const SubRecipeRef('a'),
            baseQuantity: Quantity.parse('1', Unit.portion),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
        modifiedAt: DateTime.utc(2026, 9, 6),
      );
      expect(
        () => calculator.calculate(
          recipe: a,
          targetYield: Quantity.parse('2', Unit.portion),
          recipeIndex: {'a': a},
        ),
        throwsA(isA<RecipeCycleError>()),
      );
    });

    test('rejects a missing dependency', () {
      expect(
        () => calculator.calculate(
          recipe: pie(),
          targetYield: Quantity.parse('4', Unit.portion),
          recipeIndex: {'pie': pie()},
        ),
        throwsA(isA<MissingDependencyError>()),
      );
    });
  });
}
