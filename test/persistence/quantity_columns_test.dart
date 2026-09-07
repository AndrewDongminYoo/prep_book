import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';

void main() {
  test('a non-terminating quantity round-trips exactly', () {
    final third = Quantity.parse(
      '1',
      Unit.gram,
    ).scaleBy(Rational(BigInt.one, BigInt.from(3)));

    final columns = quantityToColumns(third, 'base');
    expect(columns['base_numerator'], '1');
    expect(columns['base_denominator'], '3');
    expect(columns['base_unit'], 'g');

    expect(quantityFromColumns(columns, 'base'), third);
  });

  test('a count unit outside the fixed table round-trips', () {
    final quantity = Quantity.parse('3', Unit.count('item'));

    final columns = quantityToColumns(quantity, 'base');
    expect(columns['base_unit'], 'count:item');

    expect(quantityFromColumns(columns, 'base'), quantity);
  });

  test('a named-yield unit outside the fixed table round-trips', () {
    final quantity = Quantity.parse('2', Unit.namedYield('tray'));

    final columns = quantityToColumns(quantity, 'base');
    expect(columns['base_unit'], 'yield:tray');

    expect(quantityFromColumns(columns, 'base'), quantity);
  });

  test('unitToStorage and unitFromStorage agree for every fixed unit', () {
    for (final unit in [
      Unit.milligram,
      Unit.gram,
      Unit.kilogram,
      Unit.milliliter,
      Unit.liter,
      Unit.teaspoon,
      Unit.tablespoon,
      Unit.portion,
    ]) {
      expect(unitFromStorage(unitToStorage(unit)), unit);
    }
  });

  test('an unknown bare unit symbol is a corrupt database, not a new unit', () {
    expect(
      () => unitFromStorage('parsec'),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.toString(),
          'toString',
          'CorruptDatabaseError: unknown unit symbol: parsec',
        ),
      ),
    );
  });

  test('a prefixed unit with an empty payload is a corrupt database', () {
    expect(
      () => unitFromStorage('count:'),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test('a column group missing a column is a corrupt database', () {
    expect(
      () => quantityFromColumns(<String, Object?>{
        'base_numerator': '1',
        'base_denominator': '3',
      }, 'base'),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });
}
