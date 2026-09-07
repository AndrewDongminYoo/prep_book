import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';

/// The `Unit` instances the domain exposes as a fixed, enumerable set.
///
/// `Unit.count` and `Unit.namedYield` build additional units from arbitrary
/// caller-chosen symbols, so the domain's full unit space is not enumerable.
/// A unit outside this fixed set is stored with a `count:` or `yield:`
/// prefix by [unitToStorage] instead of relying on a table lookup; see that
/// function and [unitFromStorage] for the encoding.
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

/// Encodes [unit] as the string a `_unit` column stores.
///
/// One of the fixed units in [_fixedUnits] stores its bare symbol (`g`,
/// `kg`, `portion`, ...). Every other unit is dynamic — built by
/// `Unit.count` or `Unit.namedYield` from a caller-chosen symbol — and is
/// stored as `count:<symbol>` or `yield:<symbol>` so the single `_unit`
/// column can still round-trip it without a second schema column recording
/// which factory built it. A mass or volume unit can only be one of the
/// fixed instances above, since `Unit`'s constructor is private, so the
/// dynamic branch below is reached only for `count` and `yieldOnly`.
String unitToStorage(Unit unit) {
  for (final fixed in _fixedUnits) {
    if (fixed == unit) return fixed.symbol;
  }
  final kind = unit.dimension == UnitDimension.count ? 'count' : 'yield';
  return '$kind:${unit.symbol}';
}

/// Recovers the domain `Unit` a [stored] string encodes.
///
/// A bare symbol matching one of [_fixedUnits] decodes to that unit. A
/// `count:<symbol>` or `yield:<symbol>` form decodes to `Unit.count` or
/// `Unit.namedYield` on the trailing payload. Anything else — an
/// unrecognised bare symbol, an unrecognised prefix, or a prefixed form
/// with an empty payload — is a corrupt row, never a guessed unit.
Unit unitFromStorage(String stored) {
  for (final fixed in _fixedUnits) {
    if (fixed.symbol == stored) return fixed;
  }
  final separator = stored.indexOf(':');
  if (separator > 0 && separator < stored.length - 1) {
    final kind = stored.substring(0, separator);
    final symbol = stored.substring(separator + 1);
    if (kind == 'count') return Unit.count(symbol);
    if (kind == 'yield') return Unit.namedYield(symbol);
  }
  throw CorruptDatabaseError('unknown unit symbol: $stored');
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
      '${prefix}_unit': unitToStorage(quantity.unit),
    };

/// Rebuilds the `Quantity` stored under [prefix] in [row].
///
/// Throws [CorruptDatabaseError] when any of the three columns is missing or
/// is not a `String`, or when the unit column is not one [unitFromStorage]
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
    unitFromStorage(symbol),
  );
}
