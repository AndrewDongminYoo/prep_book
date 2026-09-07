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

  test('an unknown unit symbol is a corrupt database, not a new unit', () {
    expect(
      () => unitBySymbol('parsec'),
      throwsA(
        isA<CorruptDatabaseError>().having(
          (error) => error.toString(),
          'toString',
          'CorruptDatabaseError: unknown unit symbol: parsec',
        ),
      ),
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
