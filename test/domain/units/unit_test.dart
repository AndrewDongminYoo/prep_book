import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('Unit', () {
    test('mass units share a dimension and convert', () {
      expect(Unit.kilogram.dimension, UnitDimension.mass);
      expect(Unit.gram.canConvertTo(Unit.kilogram), isTrue);
    });

    test('mass does not convert to volume', () {
      expect(Unit.gram.canConvertTo(Unit.milliliter), isFalse);
    });

    test('volume units convert within their dimension', () {
      expect(Unit.teaspoon.canConvertTo(Unit.tablespoon), isTrue);
      expect(Unit.milliliter.canConvertTo(Unit.liter), isTrue);
    });

    test('spoons are defined against milliliters', () {
      expect(Unit.teaspoon.factorToCanonical, Decimal.fromInt(5));
      expect(Unit.tablespoon.factorToCanonical, Decimal.fromInt(15));
    });

    test('milligrams and kilograms are defined against grams', () {
      expect(Unit.milligram.factorToCanonical, Decimal.parse('0.001'));
      expect(Unit.kilogram.factorToCanonical, Decimal.fromInt(1000));
    });

    test('litres are defined against milliliters', () {
      expect(Unit.liter.factorToCanonical, Decimal.fromInt(1000));
    });

    test('two different count units never convert', () {
      final sheet = Unit.count('sheet');
      final bag = Unit.count('bag');
      expect(sheet.canConvertTo(sheet), isTrue);
      expect(sheet.canConvertTo(bag), isFalse);
    });

    test('count units have a canonical factor of one', () {
      expect(Unit.count('sheet').factorToCanonical, Decimal.one);
    });

    test('yield-only units convert only to themselves', () {
      final tray = Unit.namedYield('tray');
      expect(Unit.portion.canConvertTo(Unit.portion), isTrue);
      expect(Unit.portion.canConvertTo(tray), isFalse);
    });

    test('yield-only units have a canonical factor of one', () {
      expect(Unit.portion.factorToCanonical, Decimal.one);
    });

    test('units with the same symbol and dimension are equal', () {
      expect(Unit.count('sheet'), Unit.count('sheet'));
      expect(Unit.count('sheet').hashCode, Unit.count('sheet').hashCode);
    });

    test('describes itself by symbol', () {
      expect(Unit.kilogram.toString(), 'kg');
    });
  });

  group('UndefinedConversionError', () {
    test('names both units in its message', () {
      final error = UndefinedConversionError(Unit.gram, Unit.milliliter);
      expect(error.toString(), contains('g'));
      expect(error.toString(), contains('ml'));
    });
  });
}
