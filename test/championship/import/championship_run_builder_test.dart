import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';
import 'package:prep_book/domain/domain.dart';

const _fixturePath = 'assets/championship/sample_croissant_draft.json';

VerifiedRecipeDraft _verifiedDraft({bool removeMaxBatchYield = false}) {
  final extracted = ExtractedRecipeDraft.fromJson(
    jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>,
  );
  var review = ReviewRecipeDraft.fromExtracted(extracted)
      .confirmAllUnambiguous()
      .editComponentUnit(2, 'g')
      .confirmComponentUnit(2)
      .confirmComponentBehavior(3);
  if (removeMaxBatchYield) {
    review = review.removeMaxBatchYield().confirmMaxBatchYieldAbsent();
  }
  return (const RecipeDraftVerifier().verify(review) as RecipeDraftVerified)
      .draft;
}

void main() {
  final batchLimit = int.parse('1000');
  final builder = ChampionshipRunBuilder(
    calculator: ProductionCalculator(maxPlannedBatches: batchLimit),
  );
  final draft = _verifiedDraft();

  test('builds the exact 180 piece in-memory production run', () {
    final createdAt = DateTime.utc(2026, 9, 13, 6, 7, 8);

    final run = builder.build(
      draft: draft,
      targetAmount: '180',
      targetUnit: 'piece',
      createdAt: createdAt,
      runId: 'championship-run-1',
    );

    expect(run.id, 'championship-run-1');
    expect(run.createdAt, createdAt);
    expect(run.targetYield, Quantity.parse('180', Unit.count('piece')));
    expect(run.result.batchPlan.batchCount, 15);
    expect(
      run.result.components[0].total!.exact,
      Quantity.parse('7500', Unit.gram),
    );
    expect(
      run.result.components[1].total!.exact,
      Quantity.parse('3750', Unit.gram),
    );
    expect(
      run.result.components[2].total!.exact,
      Quantity.parse('3600', Unit.gram),
    );
    expect(run.result.components[3].total, isNull);
    expect(run.dependencySnapshot, isEmpty);
    expect(run.ingredientSnapshot, hasLength(3));
    expect(run.ingredientSnapshot.values.first.name, 'Flour');
  });

  test('rejects malformed, zero, unsupported, and incompatible targets', () {
    ProductionRun build(String amount, String unit) => builder.build(
      draft: draft,
      targetAmount: amount,
      targetUnit: unit,
      createdAt: DateTime.utc(2026, 9, 13),
      runId: 'run',
    );

    expect(() => build('many', 'piece'), throwsFormatException);
    expect(() => build('0', 'piece'), throwsA(isA<InvalidTargetYieldError>()));
    expect(() => build('180', 'cup'), throwsFormatException);
    expect(() => build('180', 'g'), throwsA(isA<IncompatibleYieldUnitError>()));
  });

  test('keeps the interactive batch policy local to the builder', () {
    expect(
      () => builder.build(
        draft: draft,
        targetAmount: '12001',
        targetUnit: 'piece',
        createdAt: DateTime.utc(2026, 9, 13),
        runId: 'too-large',
      ),
      throwsA(
        isA<BatchLimitExceededError>().having(
          (error) => error.maxPlannedBatches,
          'maxPlannedBatches',
          1000,
        ),
      ),
    );
  });

  test('rejects an injected calculator that removes the batch policy', () {
    const unsafeBuilder = ChampionshipRunBuilder(
      calculator: ProductionCalculator(),
    );

    expect(
      () => unsafeBuilder.build(
        draft: draft,
        targetAmount: '180',
        targetUnit: 'piece',
        createdAt: DateTime.utc(2026, 9, 13),
        runId: 'unsafe',
      ),
      throwsStateError,
    );
  });

  test('honors an explicitly confirmed absent maximum batch yield', () {
    final run = builder.build(
      draft: _verifiedDraft(removeMaxBatchYield: true),
      targetAmount: '180',
      targetUnit: 'piece',
      createdAt: DateTime.utc(2026, 9, 13),
      runId: 'without-maximum',
    );

    expect(run.recipe.maxBatchYield, isNull);
    expect(run.result.batchPlan.batchCount, 1);
  });
}
