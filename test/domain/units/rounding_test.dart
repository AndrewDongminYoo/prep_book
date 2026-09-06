import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('RoundingRule', () {
    test('rounds up to the next increment', () {
      final rule = RoundingRule.upToIncrement(Decimal.parse('0.25'));
      final rounded = rule.apply(Quantity.parse('12.34', Unit.kilogram));
      expect(rounded.amount, Decimal.parse('12.5').toRational());
    });

    test('leaves an exact multiple alone', () {
      final rule = RoundingRule.upToIncrement(Decimal.parse('0.25'));
      final rounded = rule.apply(Quantity.parse('12.5', Unit.kilogram));
      expect(rounded.amount, Decimal.parse('12.5').toRational());
    });

    test('rounds a non-terminating amount up', () {
      final rule = RoundingRule.upToIncrement(Decimal.one);
      final third = Quantity.parse(
        '1',
        Unit.gram,
      ).scaleBy(Rational(BigInt.one, BigInt.from(3)));
      expect(rule.apply(third).amount, Rational.one);
    });

    test('rejects a zero or negative increment', () {
      expect(
        () => RoundingRule.upToIncrement(Decimal.zero),
        throwsA(isA<InvalidRoundingIncrementError>()),
      );
      expect(
        () => RoundingRule.upToIncrement(Decimal.parse('-1')),
        throwsA(isA<InvalidRoundingIncrementError>()),
      );
    });
  });

  group('ScaledQuantity', () {
    test('an unrounded value reports no rounding', () {
      final value = Quantity.parse('3', Unit.gram);
      final scaled = ScaledQuantity.unrounded(value);
      expect(scaled.exact, value);
      expect(scaled.displayed, value);
      expect(scaled.wasRounded, isFalse);
    });

    test('keeps the exact value alongside the rounded one', () {
      final exact = Quantity.parse('12.34', Unit.kilogram);
      final scaled = ScaledQuantity.rounded(
        exact: exact,
        rule: RoundingRule.upToIncrement(Decimal.parse('0.25')),
      );
      expect(scaled.exact, exact);
      expect(scaled.displayed.amount, Decimal.parse('12.5').toRational());
      expect(scaled.wasRounded, isTrue);
    });

    test('reports no rounding when the rule changes nothing', () {
      final exact = Quantity.parse('12.5', Unit.kilogram);
      final scaled = ScaledQuantity.rounded(
        exact: exact,
        rule: RoundingRule.upToIncrement(Decimal.parse('0.25')),
      );
      expect(scaled.wasRounded, isFalse);
    });

    test('summing sums the exact and displayed amounts independently', () {
      final rule = RoundingRule.upToIncrement(Decimal.one);
      final parts = [
        ScaledQuantity.rounded(
          exact: Quantity.parse('1.2', Unit.count('item')),
          rule: rule,
        ),
        ScaledQuantity.rounded(
          exact: Quantity.parse('1.2', Unit.count('item')),
          rule: rule,
        ),
        ScaledQuantity.rounded(
          exact: Quantity.parse('0.6', Unit.count('item')),
          rule: rule,
        ),
      ];
      final total = ScaledQuantity.summing(parts);
      expect(total.exact.amount, Decimal.parse('3').toRational());
      expect(total.displayed.amount, Decimal.parse('5').toRational());
      expect(total.wasRounded, isTrue);
    });

    test('summing reports no rounding when every part agrees', () {
      final value = Quantity.parse('2', Unit.gram);
      final total = ScaledQuantity.summing([
        ScaledQuantity.unrounded(value),
        ScaledQuantity.unrounded(value),
      ]);
      expect(total.exact.amount, Decimal.parse('4').toRational());
      expect(total.wasRounded, isFalse);
    });

    test('summing converts parts recorded in different units', () {
      final total = ScaledQuantity.summing([
        ScaledQuantity.unrounded(Quantity.parse('1', Unit.kilogram)),
        ScaledQuantity.unrounded(Quantity.parse('500', Unit.gram)),
      ]);
      expect(total.exact, Quantity.parse('1.5', Unit.kilogram));
    });

    test('summing rejects an empty iterable', () {
      expect(
        () => ScaledQuantity.summing(const <ScaledQuantity>[]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
