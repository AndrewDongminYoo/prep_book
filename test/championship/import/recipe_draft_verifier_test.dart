import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';

const _fixturePath = 'assets/championship/sample_croissant_draft.json';

Map<String, Object?> _fixtureJson() => jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>;

ReviewRecipeDraft _review([Map<String, Object?>? json]) => ReviewRecipeDraft.fromExtracted(
  ExtractedRecipeDraft.fromJson(json ?? _fixtureJson()),
);

ReviewRecipeDraft _completedReview() =>
    _review().confirmAllUnambiguous().editComponentUnit(2, 'g').confirmComponentUnit(2).confirmComponentBehavior(3);

void main() {
  const verifier = RecipeDraftVerifier();

  test(
    'returns a verified immutable draft after every required confirmation',
    () {
      final result = verifier.verify(_completedReview());

      expect(result, isA<RecipeDraftVerified>());
      final verified = (result as RecipeDraftVerified).draft;
      expect(verified.recipe.name, 'Croissant dough');
      expect(verified.recipe.baseYield.amount, '24');
      expect(verified.components[2].unit, 'g');
      expect(verified.components[3].behavior, DraftScalingBehavior.manual);
      expect(
        () => verified.components.add(verified.components.first),
        throwsUnsupportedError,
      );
    },
  );

  test('rejects the untouched sample with actionable issues', () {
    final result = verifier.verify(_review());

    expect(result, isA<RecipeDraftRejected>());
    final issues = (result as RecipeDraftRejected).issues;
    expect(
      issues,
      contains(
        isA<RecipeDraftVerificationIssue>()
            .having(
              (issue) => issue.kind,
              'kind',
              RecipeDraftVerificationIssueKind.confirmationRequired,
            )
            .having((issue) => issue.path, 'path', 'recipe.name'),
      ),
    );
    expect(
      issues,
      contains(
        isA<RecipeDraftVerificationIssue>()
            .having(
              (issue) => issue.kind,
              'kind',
              RecipeDraftVerificationIssueKind.unitRequired,
            )
            .having((issue) => issue.path, 'path', 'components[2].unit'),
      ),
    );
    expect(
      issues,
      contains(
        isA<RecipeDraftVerificationIssue>()
            .having(
              (issue) => issue.kind,
              'kind',
              RecipeDraftVerificationIssueKind.confirmationRequired,
            )
            .having((issue) => issue.path, 'path', 'components[3].behavior'),
      ),
    );
    expect(
      () => issues.add(
        const RecipeDraftVerificationIssue(
          kind: RecipeDraftVerificationIssueKind.atLeastOneComponent,
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test('rejects blank names and non-positive yields', () {
    final json = _fixtureJson();
    final recipe = json['recipe']! as Map<String, Object?>;
    final name = recipe['name']! as Map<String, Object?>;
    final baseYield = recipe['baseYield']! as Map<String, Object?>;
    final amount = baseYield['amount']! as Map<String, Object?>;
    name['value'] = '   ';
    amount['value'] = '0';

    final result = verifier.verify(_review(json).confirmAllUnambiguous());

    expect(result, isA<RecipeDraftRejected>());
    final issues = (result as RecipeDraftRejected).issues;
    expect(
      issues,
      contains(
        isA<RecipeDraftVerificationIssue>()
            .having(
              (issue) => issue.kind,
              'kind',
              RecipeDraftVerificationIssueKind.valueRequired,
            )
            .having((issue) => issue.path, 'path', 'recipe.name'),
      ),
    );
    expect(
      issues,
      contains(
        isA<RecipeDraftVerificationIssue>()
            .having(
              (issue) => issue.kind,
              'kind',
              RecipeDraftVerificationIssueKind.quantityNotPositive,
            )
            .having((issue) => issue.path, 'path', 'recipe.baseYield.amount'),
      ),
    );
  });

  test('rejects incompatible maximum yield units', () {
    final json = _fixtureJson();
    final recipe = json['recipe']! as Map<String, Object?>;
    final maxYield = recipe['maxBatchYield']! as Map<String, Object?>;
    final unit = maxYield['unit']! as Map<String, Object?>;
    unit['value'] = 'kg';

    final result = verifier.verify(_review(json).confirmAllUnambiguous());

    expect(result, isA<RecipeDraftRejected>());
    expect(
      (result as RecipeDraftRejected).issues,
      contains(
        isA<RecipeDraftVerificationIssue>().having(
          (issue) => issue.kind,
          'kind',
          RecipeDraftVerificationIssueKind.maxUnitIncompatible,
        ),
      ),
    );
  });

  test('rejects an empty component list', () {
    final json = _fixtureJson()..['components'] = <Object?>[];

    final result = verifier.verify(_review(json).confirmAllUnambiguous());

    expect(result, isA<RecipeDraftRejected>());
    expect(
      (result as RecipeDraftRejected).issues,
      contains(
        isA<RecipeDraftVerificationIssue>().having(
          (issue) => issue.kind,
          'kind',
          RecipeDraftVerificationIssueKind.atLeastOneComponent,
        ),
      ),
    );
  });

  test('rejects a non-manual component without a quantity', () {
    final json = _fixtureJson();
    final components = json['components']! as List<Object?>;
    final butter = components[1]! as Map<String, Object?>;
    final amount = butter['amount']! as Map<String, Object?>;
    amount['value'] = null;

    final result = verifier.verify(_review(json).confirmAllUnambiguous());

    expect(result, isA<RecipeDraftRejected>());
    expect(
      (result as RecipeDraftRejected).issues,
      contains(
        isA<RecipeDraftVerificationIssue>()
            .having(
              (issue) => issue.kind,
              'kind',
              RecipeDraftVerificationIssueKind.quantityRequired,
            )
            .having((issue) => issue.path, 'path', 'components[1].amount'),
      ),
    );
  });

  test('classifies a blank quantity as required', () {
    final result = verifier.verify(
      _completedReview().editComponentAmount(0, '   '),
    );

    expect(result, isA<RecipeDraftRejected>());
    expect(
      (result as RecipeDraftRejected).issues,
      contains(
        isA<RecipeDraftVerificationIssue>()
            .having(
              (issue) => issue.kind,
              'kind',
              RecipeDraftVerificationIssueKind.quantityRequired,
            )
            .having((issue) => issue.path, 'path', 'components[0].amount'),
      ),
    );
  });

  test('classifies a negative quantity as non-positive', () {
    final result = verifier.verify(
      _completedReview().editComponentAmount(0, '-1'),
    );

    expect(result, isA<RecipeDraftRejected>());
    expect(
      (result as RecipeDraftRejected).issues,
      contains(
        isA<RecipeDraftVerificationIssue>()
            .having(
              (issue) => issue.kind,
              'kind',
              RecipeDraftVerificationIssueKind.quantityNotPositive,
            )
            .having((issue) => issue.path, 'path', 'components[0].amount'),
      ),
    );
  });

  test('rejects edited malformed amounts and absent behaviors', () {
    final malformed = _completedReview().editComponentAmount(0, 'many');
    final absentBehavior = _completedReview().editComponentBehavior(0, null);

    final malformedResult = verifier.verify(malformed);
    final behaviorResult = verifier.verify(absentBehavior);

    expect(
      (malformedResult as RecipeDraftRejected).issues,
      contains(
        isA<RecipeDraftVerificationIssue>().having(
          (issue) => issue.kind,
          'kind',
          RecipeDraftVerificationIssueKind.quantityNotDecimal,
        ),
      ),
    );
    expect(
      (behaviorResult as RecipeDraftRejected).issues,
      contains(
        isA<RecipeDraftVerificationIssue>().having(
          (issue) => issue.kind,
          'kind',
          RecipeDraftVerificationIssueKind.behaviorRequired,
        ),
      ),
    );
  });

  test('rejects a numeric quantity edited onto a manual component', () {
    final review = _completedReview().editComponentAmount(3, '1');

    final result = verifier.verify(review);

    expect(result, isA<RecipeDraftRejected>());
    expect(
      (result as RecipeDraftRejected).issues,
      contains(
        isA<RecipeDraftVerificationIssue>().having(
          (issue) => issue.kind,
          'kind',
          RecipeDraftVerificationIssueKind.manualHasQuantity,
        ),
      ),
    );
  });

  test('reports a unit edited onto a manual component as a unit issue', () {
    final review = _completedReview().editComponentUnit(3, 'g');

    final result = verifier.verify(review);

    expect(result, isA<RecipeDraftRejected>());
    final issues = (result as RecipeDraftRejected).issues;
    expect(
      issues,
      contains(
        isA<RecipeDraftVerificationIssue>()
            .having(
              (issue) => issue.kind,
              'kind',
              RecipeDraftVerificationIssueKind.manualHasUnit,
            )
            .having((issue) => issue.path, 'path', 'components[3].behavior'),
      ),
    );
    expect(
      issues.where(
        (issue) => issue.kind == RecipeDraftVerificationIssueKind.manualHasQuantity,
      ),
      isEmpty,
    );
  });

  test('rejects removal of maximum yield until absence is confirmed', () {
    final review = _completedReview().removeMaxBatchYield();

    final result = verifier.verify(review);

    expect(result, isA<RecipeDraftRejected>());
    expect(
      (result as RecipeDraftRejected).issues,
      contains(
        isA<RecipeDraftVerificationIssue>().having(
          (issue) => issue.kind,
          'kind',
          RecipeDraftVerificationIssueKind.maximumAbsenceConfirmationRequired,
        ),
      ),
    );
  });
}
