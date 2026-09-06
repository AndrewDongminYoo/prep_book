import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/units/quantity.dart';

/// Rounds a display quantity up to the nearest multiple of an increment.
///
/// The spec makes rounding up the default so a kitchen never under-produces.
@immutable
final class RoundingRule {
  /// Creates a rule that rounds up to the nearest [increment].
  factory RoundingRule.upToIncrement(Decimal increment) {
    if (increment <= Decimal.zero) {
      throw InvalidRoundingIncrementError(increment);
    }
    return RoundingRule._(increment);
  }

  const RoundingRule._(this.increment);

  /// The step the displayed value is rounded up to.
  final Decimal increment;

  /// [value] rounded up to the next multiple of [increment].
  Quantity apply(Quantity value) {
    final steps = (value.amount / increment.toRational()).ceil();
    return Quantity.fromRational(
      Decimal.fromBigInt(steps).toRational() * increment.toRational(),
      value.unit,
    );
  }
}

/// A calculated quantity together with what the operator is shown.
///
/// The spec requires the unrounded value to stay visible and stored, so both
/// are kept even when they are identical.
@immutable
final class ScaledQuantity {
  /// A value that carries no rounding rule.
  const ScaledQuantity.unrounded(Quantity value)
    : exact = value,
      displayed = value;

  /// A value rounded for display by [rule].
  ScaledQuantity.rounded({required this.exact, required RoundingRule rule})
    : displayed = rule.apply(exact);

  /// A value whose displayed amount was computed independently of its
  /// exact amount, rather than derived from it by a rounding rule.
  ///
  /// Used for a total whose displayed amount is the sum of already-rounded
  /// per-batch values, so the total and the batches never disagree.
  const ScaledQuantity.withDisplayed({
    required this.exact,
    required this.displayed,
  });

  /// The calculated value before any rounding.
  final Quantity exact;

  /// The value shown to the operator.
  final Quantity displayed;

  /// Whether rounding changed the value.
  bool get wasRounded => displayed != exact;
}
