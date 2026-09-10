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
            (error) => error.fullBatchCount,
            'fullBatchCount',
            BigInt.parse('1000000000000000000000000000000'),
          ),
        ),
      );
    });

    test('admits the largest count a batch count can hold', () {
      // One less than the largest `int`, so the full count and the
      // remainder batch after it both fit. A refusal written one off — on
      // the count alone rather than on the count plus its remainder —
      // either rejects this plan or lets the wrap back in.
      final largest = BigInt.parse('9223372036854775807');
      final plan = BatchPlan.decompose(
        target: Quantity.parse('9223372036854775806.5', Unit.gram),
        maxBatchYield: Quantity.parse('1', Unit.gram),
      );

      // Read off `largest` rather than written out, because a literal this
      // size is one the analyzer refuses on a target that compiles to
      // JavaScript.
      expect(plan.fullBatchCount, (largest - BigInt.one).toInt());
      expect(plan.remainderYield, Quantity.parse('0.5', Unit.gram));
      expect(plan.batchCount, largest.toInt());
    });
  });
}
