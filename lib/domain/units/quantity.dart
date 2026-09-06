import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/units/unit.dart';
import 'package:rational/rational.dart';

/// An exact amount paired with the unit it is measured in.
///
/// The amount is a [Rational] so that a scale ratio such as `1/3` survives
/// without rounding. [toDecimal] is the only place a value is ever
/// approximated, and only when the value has no finite decimal form.
@immutable
final class Quantity implements Comparable<Quantity> {
  /// Creates a quantity from an exact rational amount.
  factory Quantity.fromRational(Rational amount, Unit unit) {
    if (amount.signum < 0) throw NegativeQuantityError(amount);
    return Quantity._(amount, unit);
  }

  /// Creates a quantity from a decimal amount.
  factory Quantity.fromDecimal(Decimal amount, Unit unit) =>
      Quantity.fromRational(amount.toRational(), unit);

  /// Creates a quantity by parsing a decimal literal such as `'250.5'`.
  factory Quantity.parse(String amount, Unit unit) =>
      Quantity.fromDecimal(Decimal.parse(amount), unit);

  const Quantity._(this.amount, this.unit);

  /// The exact amount. Never rounded.
  final Rational amount;

  /// The unit the amount is measured in.
  final Unit unit;

  /// Whether the amount has a terminating decimal representation.
  bool get isExactDecimal => amount.hasFinitePrecision;

  /// Whether the amount is exactly zero.
  bool get isZero => amount == Rational.zero;

  /// The amount as a decimal, approximated only when [isExactDecimal] is
  /// false.
  Decimal toDecimal({int scaleOnInfinitePrecision = 6}) =>
      amount.toDecimal(scaleOnInfinitePrecision: scaleOnInfinitePrecision);

  /// This quantity multiplied by [ratio], exactly.
  Quantity scaleBy(Rational ratio) =>
      Quantity.fromRational(amount * ratio, unit);

  /// This quantity expressed in [target].
  ///
  /// Throws [UndefinedConversionError] when no conversion is defined.
  /// Density is never inferred.
  Quantity convertTo(Unit target) {
    if (unit == target) return this;
    if (!unit.canConvertTo(target)) {
      throw UndefinedConversionError(unit, target);
    }
    final canonical = amount * unit.factorToCanonical.toRational();
    return Quantity.fromRational(
      canonical / target.factorToCanonical.toRational(),
      target,
    );
  }

  /// The sum of this quantity and [other], expressed in this unit.
  Quantity operator +(Quantity other) =>
      Quantity.fromRational(amount + other.convertTo(unit).amount, unit);

  @override
  int compareTo(Quantity other) =>
      amount.compareTo(other.convertTo(unit).amount);

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => '${toDecimal()} ${unit.symbol}';
}
