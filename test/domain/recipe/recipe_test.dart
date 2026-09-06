import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe buildRecipe({Quantity? baseYield, Quantity? maxBatchYield}) {
  return Recipe(
    id: 'r1',
    revision: 1,
    name: 'Baguette',
    baseYield: baseYield ?? Quantity.parse('10', Unit.portion),
    maxBatchYield: maxBatchYield,
    components: [
      RecipeComponent(
        id: 'c1',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  group('Recipe', () {
    test('rejects a zero base yield', () {
      expect(
        () => buildRecipe(baseYield: Quantity.parse('0', Unit.portion)),
        throwsA(isA<InvalidBaseYieldError>()),
      );
    });

    test('rejects a max batch yield in another dimension', () {
      expect(
        () => buildRecipe(maxBatchYield: Quantity.parse('1', Unit.kilogram)),
        throwsA(isA<IncompatibleYieldUnitError>()),
      );
    });

    test('rejects two manual components sharing an id', () {
      expect(
        () => Recipe(
          id: 'r1',
          revision: 1,
          name: 'Baguette',
          baseYield: Quantity.parse('10', Unit.portion),
          components: [
            RecipeComponent(
              id: 'shared-id',
              target: const IngredientRef('salt'),
              baseQuantity: null,
              behavior: ScalingBehavior.manual,
              displayOrder: 0,
            ),
            RecipeComponent(
              id: 'shared-id',
              target: const IngredientRef('pepper'),
              baseQuantity: null,
              behavior: ScalingBehavior.manual,
              displayOrder: 1,
            ),
          ],
          modifiedAt: DateTime.utc(2026, 9, 6),
        ),
        throwsA(
          isA<InvalidComponentError>().having(
            (e) => e.componentId,
            'componentId',
            'shared-id',
          ),
        ),
      );
    });

    test('rejects two rounded proportional components sharing an id', () {
      expect(
        () => Recipe(
          id: 'r1',
          revision: 1,
          name: 'Baguette',
          baseYield: Quantity.parse('10', Unit.portion),
          components: [
            RecipeComponent(
              id: 'shared-round',
              target: const IngredientRef('egg'),
              baseQuantity: Quantity.parse('3', Unit.count('item')),
              behavior: ScalingBehavior.proportional,
              rounding: RoundingRule.upToIncrement(Decimal.one),
              displayOrder: 0,
            ),
            RecipeComponent(
              id: 'shared-round',
              target: const IngredientRef('butter'),
              baseQuantity: Quantity.parse('2', Unit.count('item')),
              behavior: ScalingBehavior.proportional,
              rounding: RoundingRule.upToIncrement(Decimal.one),
              displayOrder: 1,
            ),
          ],
          modifiedAt: DateTime.utc(2026, 9, 6),
        ),
        throwsA(
          isA<InvalidComponentError>().having(
            (e) => e.componentId,
            'componentId',
            'shared-round',
          ),
        ),
      );
    });

    test('accepts a max batch yield in the same dimension', () {
      final recipe = buildRecipe(
        maxBatchYield: Quantity.parse('4', Unit.portion),
      );
      expect(recipe.maxBatchYield, Quantity.parse('4', Unit.portion));
    });

    test('carries the identity, revision, and base yield later tasks '
        'compute against', () {
      final recipe = buildRecipe();
      expect(recipe.id, 'r1');
      expect(recipe.revision, 1);
      expect(recipe.baseYield, Quantity.parse('10', Unit.portion));
    });

    test('exposes components in display order', () {
      final recipe = buildRecipe();
      expect(recipe.components.map((c) => c.id), ['c1']);
      expect(recipe.isArchived, isFalse);
      expect(recipe.preparationNotes, isEmpty);
    });

    test('lists the recipes it depends on', () {
      final recipe = Recipe(
        id: 'r1',
        revision: 1,
        name: 'Sandwich',
        baseYield: Quantity.parse('10', Unit.portion),
        components: [
          RecipeComponent(
            id: 'c1',
            target: const SubRecipeRef('dough'),
            baseQuantity: Quantity.parse('2', Unit.portion),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
        modifiedAt: DateTime.utc(2026, 9, 6),
      );
      expect(recipe.subRecipeIds, ['dough']);
    });
  });
}
