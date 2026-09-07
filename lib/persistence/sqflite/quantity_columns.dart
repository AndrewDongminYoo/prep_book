import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';

/// The `Unit` instances the domain exposes as a fixed, enumerable set.
///
/// `Unit.count` and `Unit.namedYield` build additional units from arbitrary
/// caller-chosen symbols, so the domain's full unit space is not enumerable.
/// [unitBySymbol] can only recover units from this fixed set; see its doc
/// comment for what that means for a stored dynamic unit.
final _fixedUnits = <Unit>[
  Unit.milligram,
  Unit.gram,
  Unit.kilogram,
  Unit.milliliter,
  Unit.liter,
  Unit.teaspoon,
  Unit.tablespoon,
  Unit.portion,
];

/// Recovers the domain `Unit` for a stored [symbol].
///
/// Only the fixed units in [_fixedUnits] can be recovered this way. A symbol
/// outside that set is treated as a corrupt row rather than invented: the
/// domain also builds units from arbitrary symbols via `Unit.count` and
/// `Unit.namedYield`, and nothing stored alongside a bare symbol column can
/// tell those apart from garbage data, so this lookup does not attempt to
/// reconstruct them.
Unit unitBySymbol(String symbol) {
  for (final unit in _fixedUnits) {
    if (unit.symbol == symbol) return unit;
  }
  throw CorruptDatabaseError('unknown unit symbol: $symbol');
}

/// Splits [quantity] into the three text columns named by [prefix]:
/// `<prefix>_numerator`, `<prefix>_denominator`, and `<prefix>_unit`.
///
/// The numerator and denominator are stored as decimal strings because a
/// `Rational`'s components are `BigInt`, which SQLite's 64-bit `INTEGER`
/// cannot be relied on to hold.
Map<String, Object?> quantityToColumns(Quantity quantity, String prefix) =>
    <String, Object?>{
      '${prefix}_numerator': quantity.amount.numerator.toString(),
      '${prefix}_denominator': quantity.amount.denominator.toString(),
      '${prefix}_unit': quantity.unit.symbol,
    };

/// Rebuilds the `Quantity` stored under [prefix] in [row].
///
/// Throws [CorruptDatabaseError] when any of the three columns is missing or
/// is not a `String`, or when the unit symbol is not one [unitBySymbol]
/// recognises.
Quantity quantityFromColumns(Map<String, Object?> row, String prefix) {
  final numerator = row['${prefix}_numerator'];
  final denominator = row['${prefix}_denominator'];
  final symbol = row['${prefix}_unit'];
  if (numerator is! String || denominator is! String || symbol is! String) {
    throw CorruptDatabaseError('incomplete quantity in column group $prefix');
  }
  return Quantity.fromRational(
    Rational(BigInt.parse(numerator), BigInt.parse(denominator)),
    unitBySymbol(symbol),
  );
}
