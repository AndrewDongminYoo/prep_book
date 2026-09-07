import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';

/// Every `Unit` this test (and `quantity_columns.dart`'s own hand-maintained
/// `_fixedUnits` list) knows about. `Unit` has no public way to enumerate its
/// own static instances, so this list stands in for one; see the drift test
/// below for what keeps it honest against the domain.
final List<Unit> _knownFixedUnits = [
  Unit.milligram,
  Unit.gram,
  Unit.kilogram,
  Unit.milliliter,
  Unit.liter,
  Unit.teaspoon,
  Unit.tablespoon,
  Unit.portion,
];

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

  test(
    'a count unit built from an empty symbol round-trips, because the '
    'domain permits constructing one',
    () {
      final quantity = Quantity.parse('1', Unit.count(''));

      final columns = quantityToColumns(quantity, 'base');
      expect(columns['base_unit'], 'count:');

      expect(quantityFromColumns(columns, 'base'), quantity);
    },
  );

  test('unitToStorage and unitFromStorage agree for every fixed unit', () {
    for (final unit in _knownFixedUnits) {
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

  test(
    'a recognised separator with an unrecognised kind is a corrupt '
    'database',
    () {
      expect(
        () => unitFromStorage('inch:5'),
        throwsA(isA<CorruptDatabaseError>()),
      );
    },
  );

  test('a column group missing a column is a corrupt database', () {
    expect(
      () => quantityFromColumns(<String, Object?>{
        'base_numerator': '1',
        'base_denominator': '3',
      }, 'base'),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test(
    'the fixed-unit table matches every static Unit the domain declares',
    () {
      // `Unit.all` does not exist, so `_fixedUnits` in quantity_columns.dart
      // (and `_knownFixedUnits` above) is a hand-maintained stand-in for the
      // domain's static `Unit` instances. Nothing else ties that list to the
      // domain, so a ninth instance added there would silently fall through
      // unitToStorage's dynamic branch and decode to the wrong Unit on
      // read, with no test failing. This counts the domain's own
      // declarations as an independent check on that list's size.
      final source = File('lib/domain/units/unit.dart').readAsStringSync();
      final declared = RegExp(
        r'static final Unit \w+ =',
      ).allMatches(source).length;

      expect(
        declared,
        _knownFixedUnits.length,
        reason:
            'lib/domain/units/unit.dart declares $declared static Unit '
            "instances, but this test and quantity_columns.dart's "
            '_fixedUnits list only account for '
            '${_knownFixedUnits.length}. Update both lists together.',
      );
    },
  );
}
