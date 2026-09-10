import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('BatchPlan', () {
    test('is a single batch when the recipe defines no maximum', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('30', Unit.portion),
      );
      expect(plan.fullBatchCount, 1);
      expect(plan.fullBatchYield, Quantity.parse('30', Unit.portion));
      expect(plan.remainderYield, isNull);
      expect(plan.batchCount, 1);
    });

    test('is a single batch when the maximum is zero', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('30', Unit.portion),
        maxBatchYield: Quantity.parse('0', Unit.portion),
      );
      expect(plan.fullBatchCount, 1);
      expect(plan.fullBatchYield, Quantity.parse('30', Unit.portion));
      expect(plan.remainderYield, isNull);
      expect(plan.batchCount, 1);
    });

    test('divides evenly into full batches', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('30', Unit.portion),
        maxBatchYield: Quantity.parse('10', Unit.portion),
      );
      expect(plan.fullBatchCount, 3);
      expect(plan.remainderYield, isNull);
      expect(plan.batchCount, 3);
    });

    test('adds a remainder batch when it does not divide evenly', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('25', Unit.portion),
        maxBatchYield: Quantity.parse('10', Unit.portion),
      );
      expect(plan.fullBatchCount, 2);
      expect(plan.remainderYield, Quantity.parse('5', Unit.portion));
      expect(plan.batchCount, 3);
    });

    test('is a single remainder batch below one maximum', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('4', Unit.portion),
        maxBatchYield: Quantity.parse('10', Unit.portion),
      );
      expect(plan.fullBatchCount, 0);
      expect(plan.remainderYield, Quantity.parse('4', Unit.portion));
      expect(plan.batchCount, 1);
    });

    test('converts the maximum into the target unit', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('3', Unit.kilogram),
        maxBatchYield: Quantity.parse('1000', Unit.gram),
      );
      expect(plan.fullBatchCount, 3);
      expect(plan.remainderYield, isNull);
    });

    test('handles a fractional remainder exactly', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('7.5', Unit.kilogram),
        maxBatchYield: Quantity.parse('2', Unit.kilogram),
      );
      expect(plan.fullBatchCount, 3);
      expect(plan.remainderYield, Quantity.parse('1.5', Unit.kilogram));
      expect(plan.batchCount, 4);
    });

    test('refuses a count no batch count could hold', () {
      // The count is derived as a `BigInt` and kept as an `int`, and
      // `BigInt.toInt` clamps rather than throwing. Measured on this
      // decomposition before the refusal existed: the full count came back
      // as 9223372036854775807 and, with the remainder batch added,
      // `batchCount` as -9223372036854775808. Both are answers, and both
      // are wrong.
      expect(
        () => BatchPlan.decompose(
          target: Quantity.parse(
            '1000000000000000000000000000000.5',
            Unit.gram,
          ),
          maxBatchYield: Quantity.parse('1', Unit.gram),
        ),
        throwsA(
          isA<BatchCountOverflowError>().having(
            (error) => error.batchCount,
            'batchCount',
            BigInt.parse('1000000000000000000000000000001'),
          ),
        ),
      );
    });

    test('admits the largest count a batch count can hold', () {
      // Exactly the largest `int` full batches and nothing over, which is
      // a plan a batch count can hold and answer. A refusal that reserved
      // the remainder batch's slot before knowing there was one would
      // refuse this.
      final largest = BigInt.parse('9223372036854775807');

      final plan = BatchPlan.decompose(
        target: Quantity.parse('9223372036854775807', Unit.gram),
        maxBatchYield: Quantity.parse('1', Unit.gram),
      );

      // Read off `largest` rather than written out, because a literal this
      // size is one the analyzer refuses on a target that compiles to
      // JavaScript.
      expect(plan.fullBatchCount, largest.toInt());
      expect(plan.remainderYield, isNull);
      expect(plan.batchCount, largest.toInt());
    });

    test('refuses the same count once a remainder is added to it', () {
      // Half a gram more than the test above, which is the whole
      // difference: the full count is unchanged and still fits, and the
      // remainder batch after it does not. The pair is what pins the
      // boundary — a refusal on the full count alone passes the test above
      // and fails this one.
      expect(
        () => BatchPlan.decompose(
          target: Quantity.parse('9223372036854775807.5', Unit.gram),
          maxBatchYield: Quantity.parse('1', Unit.gram),
        ),
        throwsA(
          isA<BatchCountOverflowError>().having(
            (error) => error.batchCount,
            'batchCount',
            BigInt.parse('9223372036854775808'),
          ),
        ),
      );
    });
  });
}
