import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/units/quantity.dart';

/// How a production run is split into batches.
@immutable
final class BatchPlan {
  /// Splits [target] into full batches of [maxBatchYield] plus a remainder.
  ///
  /// Without a maximum the run is a single batch producing the whole target.
  ///
  /// Throws [BatchCountOverflowError] when the target needs more full
  /// batches than [batchCount] can hold. No caller can ask for that
  /// deliberately at any plausible scale, and the refusal is here rather
  /// than in a caller's bound because a caller may set no bound at all.
  factory BatchPlan.decompose({
    required Quantity target,
    Quantity? maxBatchYield,
  }) {
    if (maxBatchYield == null || maxBatchYield.isZero) {
      return BatchPlan._(
        fullBatchCount: 1,
        fullBatchYield: target,
        remainderYield: null,
      );
    }

    final max = maxBatchYield.convertTo(target.unit);
    final full = (target.amount / max.amount).floor();
    // Refused before the conversion below narrows it, because that
    // conversion cannot fail: `BigInt.toInt` clamps to the largest `int`
    // rather than throwing, and a clamped full count then makes
    // [batchCount] — one more than it, whenever there is a remainder —
    // wrap to the most negative `int` instead. Measured on a target of
    // 10^30 grams in one-gram batches: the count came back as
    // 9223372036854775807 and the batch count as -9223372036854775808.
    //
    // One is added before the test rather than after, so that the count
    // and the remainder batch that may follow it are both representable
    // and no later sum can wrap.
    if (!(full + BigInt.one).isValidInt) {
      throw BatchCountOverflowError(full);
    }
    final consumed = max.scaleBy(Decimal.fromBigInt(full).toRational());
    final remainder = Quantity.fromRational(
      target.amount - consumed.amount,
      target.unit,
    );

    return BatchPlan._(
      fullBatchCount: full.toInt(),
      fullBatchYield: max,
      remainderYield: remainder.isZero ? null : remainder,
    );
  }

  const BatchPlan._({
    required this.fullBatchCount,
    required this.fullBatchYield,
    required this.remainderYield,
  });

  /// How many batches produce a full [fullBatchYield].
  final int fullBatchCount;

  /// The yield of one full batch.
  final Quantity fullBatchYield;

  /// The yield of the trailing partial batch, when there is one.
  final Quantity? remainderYield;

  /// Every batch the run performs, counting a non-empty remainder as one.
  int get batchCount => fullBatchCount + (remainderYield == null ? 0 : 1);
}
