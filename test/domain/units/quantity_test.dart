import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('Quantity', () {
    test('keeps a non-terminating ratio exact', () {
      final base = Quantity.parse('1', Unit.kilogram);
      final scaled = base.scaleBy(Rational(BigInt.one, BigInt.from(3)));

      expect(scaled.isExactDecimal, isFalse);
      expect(scaled.amount, Rational(BigInt.one, BigInt.from(3)));
      expect(
        scaled.toDecimal(scaleOnInfinitePrecision: 4),
        Decimal.parse('0.3333'),
      );
    });

    test('scaling by a then b equals scaling by a times b', () {
      final base = Quantity.parse('250.5', Unit.gram);
      final a = Rational(BigInt.from(7), BigInt.from(3));
      final b = Rational(BigInt.from(5), BigInt.from(11));

      expect(base.scaleBy(a).scaleBy(b), base.scaleBy(a * b));
    });

    test('converts within a dimension', () {
      final grams = Quantity.parse('1500', Unit.gram);
      expect(grams.convertTo(Unit.kilogram).amount, Rational.fromInt(3, 2));
      expect(grams.convertTo(Unit.kilogram).unit, Unit.kilogram);
    });

    test('a tablespoon is fifteen milliliters', () {
      final spoon = Quantity.parse('2', Unit.tablespoon);
      expect(spoon.convertTo(Unit.milliliter).amount, Rational.fromInt(30));
    });

    test('converting to a compatible unit and back is reversible', () {
      final original = Quantity.parse('1.5', Unit.kilogram);
      final roundTripped = original
          .convertTo(Unit.gram)
          .convertTo(Unit.kilogram);
      expect(roundTripped, original);
    });

    test('a non-terminating amount survives a round trip through a compatible '
        'unit exactly, not merely within a rounded precision', () {
      final original = Quantity.parse(
        '1',
        Unit.kilogram,
      ).scaleBy(Rational(BigInt.one, BigInt.from(3)));
      final roundTripped = original
          .convertTo(Unit.gram)
          .convertTo(Unit.kilogram);
      expect(roundTripped, original);
    });

    test('rejects a conversion across dimensions', () {
      final grams = Quantity.parse('100', Unit.gram);
      expect(
        () => grams.convertTo(Unit.milliliter),
        throwsA(isA<UndefinedConversionError>()),
      );
    });

    test('rejects a conversion between two count units', () {
      final sheets = Quantity.parse('3', Unit.count('sheet'));
      expect(
        () => sheets.convertTo(Unit.count('bag')),
        throwsA(isA<UndefinedConversionError>()),
      );
    });

    test('adds after converting the operand', () {
      final a = Quantity.parse('1', Unit.kilogram);
      final b = Quantity.parse('500', Unit.gram);
      expect((a + b).amount, Rational.fromInt(3, 2));
      expect((a + b).unit, Unit.kilogram);
    });

    test('refuses to add across dimensions', () {
      final a = Quantity.parse('1', Unit.kilogram);
      final b = Quantity.parse('1', Unit.liter);
      expect(() => a + b, throwsA(isA<UndefinedConversionError>()));
    });

    test('rejects a negative amount', () {
      expect(
        () => Quantity.parse('-1', Unit.gram),
        throwsA(isA<NegativeQuantityError>()),
      );
    });

    test('compares within a dimension', () {
      final a = Quantity.parse('1', Unit.kilogram);
      final b = Quantity.parse('999', Unit.gram);
      expect(a.compareTo(b), greaterThan(0));
      expect(Quantity.parse('0', Unit.gram).isZero, isTrue);
    });

    test('equal values in the same unit are equal', () {
      expect(
        Quantity.parse('1.50', Unit.kilogram),
        Quantity.parse('1.5', Unit.kilogram),
      );
      expect(
        Quantity.parse('1.5', Unit.kilogram).hashCode,
        Quantity.parse('1.5', Unit.kilogram).hashCode,
      );
    });

    test('describes itself with the unit symbol', () {
      expect(Quantity.parse('1.5', Unit.kilogram).toString(), '1.5 kg');
    });

    test('equality is unit-structural while ordering converts', () {
      final kilogram = Quantity.parse('1', Unit.kilogram);
      final thousandGrams = Quantity.parse('1000', Unit.gram);

      expect(kilogram, isNot(equals(thousandGrams)));
      expect(kilogram.compareTo(thousandGrams), 0);
    });

    test('converting to the same unit returns the identical instance', () {
      final grams = Quantity.parse('250', Unit.gram);

      expect(identical(grams.convertTo(Unit.gram), grams), isTrue);
    });
  });
}
