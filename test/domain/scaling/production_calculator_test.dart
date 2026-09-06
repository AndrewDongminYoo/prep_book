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

void main() {
  const calculator = ProductionCalculator();

  group('ProductionCalculator', () {
    test('a target equal to the base yield changes nothing', () {
      final result = calculator.calculate(
        recipe: bread(),
        targetYield: Quantity.parse('10', Unit.portion),
      );
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
      final flour = componentById(result, 'flour').total!.exact;
      expect(flour.isExactDecimal, isFalse);
      expect(flour.amount, Rational(BigInt.one, BigInt.from(3)));
    });

    test('multiplies a per-batch component by the batch count', () {
      final result = calculator.calculate(
        recipe: bread(maxBatchYield: Quantity.parse('10', Unit.portion)),
        targetYield: Quantity.parse('25', Unit.portion),
      );
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
      final eggs = componentById(result, 'eggs').total!;
      expect(eggs.exact.amount, Rational.fromInt(9, 2));
      expect(eggs.displayed.amount, Rational.fromInt(5));
      expect(result.warnings, contains(const RoundingAdjustedWarning('eggs')));
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
      final eggs = componentById(result, 'eggs').total!;
      expect(eggs.wasRounded, isFalse);
      expect(result.warnings, isEmpty);
    });

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
