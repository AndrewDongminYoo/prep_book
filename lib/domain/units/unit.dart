import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';

/// The kinds of quantity the application can express.
enum UnitDimension {
  /// Milligrams, grams, kilograms.
  mass,

  /// Milliliters, litres, teaspoons, tablespoons.
  volume,

  /// Discrete named things: item, sheet, bag.
  count,

  /// Recipe output units that measure nothing else: portion, tray.
  yieldOnly,
}

/// A unit of measure with a defined position in its dimension.
@immutable
final class Unit {
  const Unit._(this.symbol, this.dimension, this.factorToCanonical);

  /// A named count unit. Count units never convert into one another.
  factory Unit.count(String symbol) =>
      Unit._(symbol, UnitDimension.count, Decimal.one);

  /// A recipe-defined output unit. These never convert into one another.
  factory Unit.namedYield(String symbol) =>
      Unit._(symbol, UnitDimension.yieldOnly, Decimal.one);

  static final Unit milligram = Unit._(
    'mg',
    UnitDimension.mass,
    Decimal.parse('0.001'),
  );
  static final Unit gram = Unit._('g', UnitDimension.mass, Decimal.one);
  static final Unit kilogram = Unit._(
    'kg',
    UnitDimension.mass,
    Decimal.fromInt(1000),
  );

  static final Unit milliliter = Unit._(
    'ml',
    UnitDimension.volume,
    Decimal.one,
  );
  static final Unit liter = Unit._(
    'L',
    UnitDimension.volume,
    Decimal.fromInt(1000),
  );
  static final Unit teaspoon = Unit._(
    'tsp',
    UnitDimension.volume,
    Decimal.fromInt(5),
  );
  static final Unit tablespoon = Unit._(
    'tbsp',
    UnitDimension.volume,
    Decimal.fromInt(15),
  );

  static final Unit portion = Unit.namedYield('portion');

  /// The unit's symbol as the operator writes it.
  final String symbol;

  /// The dimension this unit measures.
  final UnitDimension dimension;

  /// How many canonical units one of this unit is worth.
  ///
  /// Grams for mass, milliliters for volume, and one for every count or
  /// yield-only unit, which are never scaled against a sibling.
  final Decimal factorToCanonical;

  /// Whether the dimension defines conversions between distinct units.
  bool get hasDefinedConversions =>
      dimension == UnitDimension.mass || dimension == UnitDimension.volume;

  /// Whether a conversion from this unit to [other] is defined.
  ///
  /// Density is never inferred, so mass never converts to volume.
  bool canConvertTo(Unit other) {
    if (dimension != other.dimension) return false;
    return hasDefinedConversions || symbol == other.symbol;
  }

  @override
  bool operator ==(Object other) =>
      other is Unit && other.symbol == symbol && other.dimension == dimension;

  @override
  int get hashCode => Object.hash(symbol, dimension);

  @override
  String toString() => symbol;
}
