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
  });
}
