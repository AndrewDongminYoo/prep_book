import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/domain/units/quantity.dart';

/// How a production run is split into batches.
@immutable
final class BatchPlan {
  /// Splits [target] into full batches of [maxBatchYield] plus a remainder.
  ///
  /// Without a maximum the run is a single batch producing the whole target.
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
