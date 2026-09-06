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
/// are kept even when they are identical. Every value this class can
/// produce satisfies `displayed >= exact`: [ScaledQuantity.unrounded] keeps
/// them equal, [ScaledQuantity.rounded] only ever rounds up, and
/// [ScaledQuantity.summing] combines values that already satisfy the
/// inequality by summing each side independently, which preserves it.
/// There is no constructor that accepts an exact and a displayed amount
/// directly, so a caller cannot build a value that under-reports what a
/// kitchen actually needs.
@immutable
final class ScaledQuantity {
  /// A value that carries no rounding rule.
  const ScaledQuantity.unrounded(Quantity value)
    : exact = value,
      displayed = value;

  /// A value rounded for display by [rule].
  ScaledQuantity.rounded({required this.exact, required RoundingRule rule})
    : displayed = rule.apply(exact);

  const ScaledQuantity._({required this.exact, required this.displayed});

  /// The sum of already-computed [parts]: the exact amount is the sum of
  /// the parts' exact amounts, and the displayed amount is the sum of
  /// their displayed amounts, each reduced independently.
  ///
  /// Used for a total whose displayed amount is the sum of already-rounded
  /// per-batch values, so a total-oriented view of a run and a
  /// batch-oriented view of the same run never disagree.
  ///
  /// The parts may be recorded in different units — [Quantity]'s `+`
  /// converts each addend into the running sum's unit as it is added.
  ///
  /// Throws [ArgumentError] if [parts] is empty: an empty sum has no unit
  /// to report, so it is rejected rather than silently producing something
  /// meaningless. A production run always has at least one batch, so the
  /// calculator never passes an empty iterable here, but this constructor
  /// is public and must not assume that of every caller.
  factory ScaledQuantity.summing(Iterable<ScaledQuantity> parts) {
    final iterator = parts.iterator;
    if (!iterator.moveNext()) {
      throw ArgumentError.value(parts, 'parts', 'must not be empty');
    }
    var exact = iterator.current.exact;
    var displayed = iterator.current.displayed;
    while (iterator.moveNext()) {
      exact += iterator.current.exact;
      displayed += iterator.current.displayed;
    }
    return ScaledQuantity._(exact: exact, displayed: displayed);
  }

  /// The calculated value before any rounding.
  final Quantity exact;

  /// The value shown to the operator.
  final Quantity displayed;

  /// Whether the displayed amount differs from the exact one — from
  /// rounding a single value, or from summing already-computed parts whose
  /// displayed amounts diverge from their exact amounts as a group.
  bool get wasRounded => displayed != exact;
}
