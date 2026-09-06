import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe bread({Quantity? maxBatchYield}) {
  return Recipe(
    id: 'bread',
    revision: 1,
    name: 'Bread',
    baseYield: Quantity.parse('10', Unit.portion),
    maxBatchYield: maxBatchYield,
    components: [
      RecipeComponent(
        id: 'flour',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'yeast',
        target: const IngredientRef('yeast'),
        baseQuantity: Quantity.parse('7', Unit.gram),
        behavior: ScalingBehavior.perBatch,
        displayOrder: 1,
      ),
      RecipeComponent(
        id: 'pan-grease',
        target: const IngredientRef('butter'),
        baseQuantity: Quantity.parse('20', Unit.gram),
        behavior: ScalingBehavior.fixedOnce,
        displayOrder: 2,
      ),
      RecipeComponent(
        id: 'salt',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        note: 'to taste',
        displayOrder: 3,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

ScaledComponent componentById(ProductionResult result, String id) =>
    result.components.firstWhere((c) => c.source.id == id);

/// For every component, the per-batch values must sum to the total —
/// exact to exact, and displayed to displayed — so a chef reading the
/// total-oriented sheet and the batch-oriented sheet never sees two
/// different numbers for the same run.
void expectBatchesSumToTotal(ProductionResult result) {
  for (final component in result.components) {
    final total = component.total;
    if (total == null) {
      expect(component.perBatch, everyElement(isNull));
      continue;
    }
    final exactSum = component.perBatch
        .map((batch) => batch!.exact)
        .reduce((a, b) => a + b);
    final displayedSum = component.perBatch
        .map((batch) => batch!.displayed)
        .reduce((a, b) => a + b);
    expect(exactSum, total.exact);
    expect(displayedSum, total.displayed);
  }
}

void main() {
  const calculator = ProductionCalculator();

  group('ProductionCalculator', () {
    test('a target equal to the base yield changes nothing', () {
      final result = calculator.calculate(
        recipe: bread(),
        targetYield: Quantity.parse('10', Unit.portion),
      );
      expectBatchesSumToTotal(result);
      expect(result.scaleRatio, Rational.one);
      expect(
        componentById(result, 'flour').total!.exact,
        Quantity.parse('1', Unit.kilogram),
      );
    });

    test('scales a proportional component by the ratio', () {
      final result = calculator.calculate(
        recipe: bread(),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      expectBatchesSumToTotal(result);
      expect(result.scaleRatio, Rational.fromInt(5, 2));
      expect(
        componentById(result, 'flour').total!.exact,
        Quantity.parse('2.5', Unit.kilogram),
      );
    });

    test('keeps a non-terminating ratio exact', () {
      final result = calculator.calculate(
        recipe: bread(),
        targetYield: Quantity.parse('10', Unit.portion).scaleBy(
          Rational(BigInt.one, BigInt.from(3)),
        ),
      );
      expectBatchesSumToTotal(result);
      final flour = componentById(result, 'flour').total!.exact;
      expect(flour.isExactDecimal, isFalse);
      expect(flour.amount, Rational(BigInt.one, BigInt.from(3)));
    });

    test('multiplies a per-batch component by the batch count', () {
      final result = calculator.calculate(
        recipe: bread(maxBatchYield: Quantity.parse('10', Unit.portion)),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      expectBatchesSumToTotal(result);
      expect(result.batchPlan.batchCount, 3);
      expect(
        componentById(result, 'yeast').total!.exact,
        Quantity.parse('21', Unit.gram),
      );
    });

    test('includes a fixed-once component exactly once', () {
      final result = calculator.calculate(
        recipe: bread(maxBatchYield: Quantity.parse('10', Unit.portion)),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      expectBatchesSumToTotal(result);
      expect(
        componentById(result, 'pan-grease').total!.exact,
        Quantity.parse('20', Unit.gram),
      );
    });

    test('leaves a manual component unresolved and warns', () {
      final result = calculator.calculate(
        recipe: bread(),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      expectBatchesSumToTotal(result);
      expect(componentById(result, 'salt').total, isNull);
      expect(
        result.warnings,
        contains(isA<ManualComponentWarning>()),
      );
      expect(result.hasBlockingWarnings, isTrue);
    });

    test('reports per-batch quantities for every batch', () {
      final result = calculator.calculate(
        recipe: bread(maxBatchYield: Quantity.parse('10', Unit.portion)),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      expectBatchesSumToTotal(result);
      final flour = componentById(result, 'flour');
      expect(flour.perBatch, hasLength(3));
      expect(flour.perBatch[0]!.exact, Quantity.parse('1', Unit.kilogram));
      expect(flour.perBatch[2]!.exact, Quantity.parse('0.5', Unit.kilogram));
    });

    test('rounds a display quantity and warns that it changed', () {
      final recipe = Recipe(
        id: 'buns',
        revision: 1,
        name: 'Buns',
        baseYield: Quantity.parse('10', Unit.portion),
        components: [
          RecipeComponent(
            id: 'eggs',
            target: const IngredientRef('egg'),
            baseQuantity: Quantity.parse('3', Unit.count('item')),
            behavior: ScalingBehavior.proportional,
            rounding: RoundingRule.upToIncrement(Decimal.one),
            displayOrder: 0,
          ),
        ],
        modifiedAt: DateTime.utc(2026, 9, 6),
      );
      final result = calculator.calculate(
        recipe: recipe,
        targetYield: Quantity.parse('15', Unit.portion),
      );
      expectBatchesSumToTotal(result);
      final eggs = componentById(result, 'eggs').total!;
      expect(eggs.exact.amount, Rational.fromInt(9, 2));
      expect(eggs.displayed.amount, Rational.fromInt(5));
      expect(
        result.warnings,
        contains(const RoundingAdjustedWarning('buns', 'eggs')),
      );
      expect(result.hasBlockingWarnings, isFalse);
    });

    test('does not warn when rounding leaves the value unchanged', () {
      final recipe = Recipe(
        id: 'buns',
        revision: 1,
        name: 'Buns',
        baseYield: Quantity.parse('10', Unit.portion),
        components: [
          RecipeComponent(
            id: 'eggs',
            target: const IngredientRef('egg'),
            baseQuantity: Quantity.parse('3', Unit.count('item')),
            behavior: ScalingBehavior.proportional,
            rounding: RoundingRule.upToIncrement(Decimal.one),
            displayOrder: 0,
          ),
        ],
        modifiedAt: DateTime.utc(2026, 9, 6),
      );
      final result = calculator.calculate(
        recipe: recipe,
        targetYield: Quantity.parse('20', Unit.portion),
      );
      expectBatchesSumToTotal(result);
      final eggs = componentById(result, 'eggs').total!;
      expect(eggs.wasRounded, isFalse);
      expect(result.warnings, isEmpty);
    });

    test(
      'the displayed total is the sum of the displayed batches, '
      'not a fresh rounding of the exact total',
      () {
        final recipe = Recipe(
          id: 'buns',
          revision: 1,
          name: 'Buns',
          baseYield: Quantity.parse('10', Unit.portion),
          maxBatchYield: Quantity.parse('4', Unit.portion),
          components: [
            RecipeComponent(
              id: 'eggs',
              target: const IngredientRef('egg'),
              baseQuantity: Quantity.parse('3', Unit.count('item')),
              behavior: ScalingBehavior.proportional,
              rounding: RoundingRule.upToIncrement(Decimal.one),
              displayOrder: 0,
            ),
          ],
          modifiedAt: DateTime.utc(2026, 9, 6),
        );
        final result = calculator.calculate(
          recipe: recipe,
          targetYield: Quantity.parse('10', Unit.portion),
        );
        expectBatchesSumToTotal(result);

        final eggs = componentById(result, 'eggs');
        expect(
          eggs.perBatch.map((batch) => batch!.displayed.amount).toList(),
          [Rational.fromInt(2), Rational.fromInt(2), Rational.fromInt(1)],
        );
        expect(eggs.total!.exact.amount, Rational.fromInt(3));
        expect(eggs.total!.displayed.amount, Rational.fromInt(5));
        expect(
          result.warnings,
          contains(const RoundingAdjustedWarning('buns', 'eggs')),
        );
      },
    );

    test(
      'the total and every per-batch value agree across all four '
      'behaviors and a sub-recipe line',
      () {
        final recipe = Recipe(
          id: 'bread-with-starter',
          revision: 1,
          name: 'Bread with starter',
          baseYield: Quantity.parse('10', Unit.portion),
          maxBatchYield: Quantity.parse('4', Unit.portion),
          components: [
            RecipeComponent(
              id: 'flour',
              target: const IngredientRef('flour'),
              baseQuantity: Quantity.parse('1', Unit.kilogram),
              behavior: ScalingBehavior.proportional,
              displayOrder: 0,
            ),
            RecipeComponent(
              id: 'yeast',
              target: const IngredientRef('yeast'),
              baseQuantity: Quantity.parse('7', Unit.gram),
              behavior: ScalingBehavior.perBatch,
              displayOrder: 1,
            ),
            RecipeComponent(
              id: 'pan-grease',
              target: const IngredientRef('butter'),
              baseQuantity: Quantity.parse('20', Unit.gram),
              behavior: ScalingBehavior.fixedOnce,
              displayOrder: 2,
            ),
            RecipeComponent(
              id: 'salt',
              target: const IngredientRef('salt'),
              baseQuantity: null,
              behavior: ScalingBehavior.manual,
              note: 'to taste',
              displayOrder: 3,
            ),
            RecipeComponent(
              id: 'dough',
              target: const SubRecipeRef('starter-dough'),
              baseQuantity: Quantity.parse('2', Unit.kilogram),
              behavior: ScalingBehavior.proportional,
              displayOrder: 4,
            ),
          ],
          modifiedAt: DateTime.utc(2026, 9, 6),
        );

        final starterDough = Recipe(
          id: 'starter-dough',
          revision: 1,
          name: 'Starter dough',
          baseYield: Quantity.parse('2', Unit.kilogram),
          components: [
            RecipeComponent(
              id: 'starter-flour',
              target: const IngredientRef('flour'),
              baseQuantity: Quantity.parse('1.5', Unit.kilogram),
              behavior: ScalingBehavior.proportional,
              displayOrder: 0,
            ),
          ],
          modifiedAt: DateTime.utc(2026, 9, 6),
        );

        final result = calculator.calculate(
          recipe: recipe,
          targetYield: Quantity.parse('10', Unit.portion),
          recipeIndex: {'starter-dough': starterDough},
        );
        expectBatchesSumToTotal(result);

        final flour = componentById(result, 'flour');
        expect(flour.total!.exact, Quantity.parse('1', Unit.kilogram));
        expect(
          flour.perBatch.map((batch) => batch!.exact).toList(),
          [
            Quantity.parse('0.4', Unit.kilogram),
            Quantity.parse('0.4', Unit.kilogram),
            Quantity.parse('0.2', Unit.kilogram),
          ],
        );

        final yeast = componentById(result, 'yeast');
        expect(yeast.total!.exact, Quantity.parse('21', Unit.gram));
        expect(
          yeast.perBatch.map((batch) => batch!.exact).toList(),
          [
            Quantity.parse('7', Unit.gram),
            Quantity.parse('7', Unit.gram),
            Quantity.parse('7', Unit.gram),
          ],
        );

        final panGrease = componentById(result, 'pan-grease');
        expect(panGrease.total!.exact, Quantity.parse('20', Unit.gram));
        expect(
          panGrease.perBatch.map((batch) => batch!.exact).toList(),
          [
            Quantity.parse('20', Unit.gram),
            Quantity.parse('0', Unit.gram),
            Quantity.parse('0', Unit.gram),
          ],
        );

        final salt = componentById(result, 'salt');
        expect(salt.total, isNull);
        expect(salt.perBatch, [isNull, isNull, isNull]);

        final dough = componentById(result, 'dough');
        final nestedStarter = dough.subRecipe;
        expect(nestedStarter, isNotNull);
        expect(nestedStarter!.scaleRatio, Rational.one);
        expect(
          nestedStarter.components.single.total!.exact,
          Quantity.parse('1.5', Unit.kilogram),
        );
        expect(dough.total!.exact, Quantity.parse('2', Unit.kilogram));
        expect(
          dough.perBatch.map((batch) => batch!.exact).toList(),
          [
            Quantity.parse('0.8', Unit.kilogram),
            Quantity.parse('0.8', Unit.kilogram),
            Quantity.parse('0.4', Unit.kilogram),
          ],
        );
      },
    );

    test('rejects a target yield in another dimension', () {
      expect(
        () => calculator.calculate(
          recipe: bread(),
          targetYield: Quantity.parse('5', Unit.kilogram),
        ),
        throwsA(isA<IncompatibleYieldUnitError>()),
      );
    });

    test('rejects a zero target yield', () {
      expect(
        () => calculator.calculate(
          recipe: bread(),
          targetYield: Quantity.parse('0', Unit.portion),
        ),
        throwsA(isA<InvalidTargetYieldError>()),
      );
    });
  });
}
