import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

/// A recipe with a single proportional component, split into batches by
/// [maxBatchYield] when one is supplied.
Recipe proportionalRecipe({
  required String baseYield,
  required String baseQuantity,
  String? maxBatchYield,
}) {
  return Recipe(
    id: 'r',
    revision: 1,
    name: 'R',
    baseYield: Quantity.parse(baseYield, Unit.portion),
    maxBatchYield: maxBatchYield == null
        ? null
        : Quantity.parse(maxBatchYield, Unit.portion),
    components: [
      RecipeComponent(
        id: 'c',
        target: const IngredientRef('i'),
        baseQuantity: Quantity.parse(baseQuantity, Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  const calculator = ProductionCalculator();

  // Each test seeds its own generator so a reported failing input stays
  // reproducible regardless of how many tests run before it, or in what
  // order.

  test('scaling by x then y equals scaling by x times y', () {
    final random = Random(20260906);
    for (var i = 0; i < 200; i++) {
      final base = Quantity.parse('${1 + random.nextInt(500)}', Unit.gram);
      final x = Rational(
        BigInt.from(1 + random.nextInt(50)),
        BigInt.from(1 + random.nextInt(50)),
      );
      final y = Rational(
        BigInt.from(1 + random.nextInt(50)),
        BigInt.from(1 + random.nextInt(50)),
      );

      expect(base.scaleBy(x).scaleBy(y), base.scaleBy(x * y));
    }
  });

  test('a proportional component only ever produces strictly positive '
      'quantities', () {
    final random = Random(20260906);
    for (var i = 0; i < 200; i++) {
      final recipe = proportionalRecipe(
        baseYield: '${1 + random.nextInt(100)}',
        baseQuantity: '${1 + random.nextInt(1000)}',
        // A batching maximum is included on every iteration so full
        // batches, a trailing remainder batch, and an exact division
        // (no remainder batch at all) are all reachable — a component
        // scaled as a single batch can never observe a zero-valued
        // remainder batch slipping past this check.
        maxBatchYield: '${1 + random.nextInt(100)}',
      );
      final result = calculator.calculate(
        recipe: recipe,
        targetYield: Quantity.parse(
          '${1 + random.nextInt(1000)}',
          Unit.portion,
        ),
      );

      for (final component in result.components) {
        // Strict positivity, not mere non-negativity: every Quantity
        // already carries a non-negative-amount invariant enforced by
        // Quantity.fromRational, so asserting signum >= 0 here would
        // hold for any Quantity value that could ever exist and could
        // never fail. Asserting signum == 1 instead exercises the
        // calculator's own arithmetic — a zero-valued batch (e.g. an
        // exact-division remainder that should have been dropped) would
        // still be a non-negative Quantity, but fails this.
        expect(component.total!.exact.amount.signum, 1);
        expect(component.total!.displayed.amount.signum, 1);
        for (final batch in component.perBatch) {
          expect(batch!.exact.amount.signum, 1);
          expect(batch.displayed.amount.signum, 1);
        }
      }
    }
  });

  test('a proportional component exact per-batch values sum to the base '
      'quantity scaled by the run ratio', () {
    final random = Random(20260906);
    for (var i = 0; i < 100; i++) {
      final maxBatch = 1 + random.nextInt(20);
      final target = 1 + random.nextInt(200);
      final baseYield = 1 + random.nextInt(50);
      final baseQuantityAmount = 1 + random.nextInt(1000);

      final recipe = proportionalRecipe(
        baseYield: '$baseYield',
        baseQuantity: '$baseQuantityAmount',
        maxBatchYield: '$maxBatch',
      );

      final result = calculator.calculate(
        recipe: recipe,
        targetYield: Quantity.parse('$target', Unit.portion),
      );

      // The expectation is built from the test's own inputs alone —
      // never from `result.scaleRatio` or `component.total` — so this
      // is independent of how the calculator derives its total. It can
      // only hold if the batch plan's ratios sum to exactly one, which
      // is the real property BatchPlan.decompose and _batchRatios must
      // satisfy for a batched run to reconstruct the unbatched result.
      final expected = Quantity.parse(
        '$baseQuantityAmount',
        Unit.gram,
      ).scaleBy(Rational(BigInt.from(target), BigInt.from(baseYield)));

      final component = result.components.single;
      final summed = component.perBatch
          .map((value) => value!.exact)
          .reduce((a, b) => a + b);
      expect(summed, expected);
    }
  });

  test('rounding never lowers the displayed value', () {
    final random = Random(20260906);
    for (var i = 0; i < 100; i++) {
      final rule = RoundingRule.upToIncrement(
        Decimal.parse('0.${1 + random.nextInt(8)}'),
      );
      final value = Quantity.parse(
        '${random.nextInt(1000)}.${random.nextInt(100)}',
        Unit.gram,
      );
      final scaled = ScaledQuantity.rounded(exact: value, rule: rule);
      expect(scaled.displayed.compareTo(scaled.exact), greaterThanOrEqualTo(0));
    }
  });
}
