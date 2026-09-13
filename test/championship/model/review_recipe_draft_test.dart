import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';

const _fixturePath = 'assets/championship/sample_croissant_draft.json';

ExtractedRecipeDraft _fixture() => ExtractedRecipeDraft.fromJson(
  jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>,
);

void main() {
  group('ReviewRecipeDraft', () {
    test('starts with no confirmed fields and immutable components', () {
      final draft = ReviewRecipeDraft.fromExtracted(_fixture());

      expect(draft.allFields.every((field) => !field.isConfirmed), isTrue);
      expect(
        () => draft.components.add(draft.components.first),
        throwsUnsupportedError,
      );
    });

    test('bulk confirmation skips ambiguous and manual decisions', () {
      final draft = ReviewRecipeDraft.fromExtracted(
        _fixture(),
      ).confirmAllUnambiguous();

      expect(draft.recipe.name.isConfirmed, isTrue);
      expect(draft.recipe.baseYield.amount.isConfirmed, isTrue);
      expect(draft.components[0].unit.isConfirmed, isTrue);
      expect(draft.components[2].unit.isConfirmed, isFalse);
      expect(draft.components[2].unit.activeIssues, isNotEmpty);
      expect(draft.components[3].behavior.isConfirmed, isFalse);
      expect(draft.components[3].amount.isConfirmed, isFalse);
      expect(draft.components[3].amount.activeIssues, isEmpty);
      expect(draft.components[3].unit.activeIssues, isEmpty);
    });

    test('editing a field clears confirmation and revalidates it', () {
      final original = ReviewRecipeDraft.fromExtracted(
        _fixture(),
      ).confirmAllUnambiguous();

      final edited = original.editComponentUnit(0, 'kg');
      final unsupported = edited.editComponentUnit(0, 'cup');

      expect(original.components[0].unit.isConfirmed, isTrue);
      expect(edited.components[0].unit.isConfirmed, isFalse);
      expect(edited.components[0].unit.isEdited, isTrue);
      expect(edited.components[0].unit.activeIssues, isEmpty);
      expect(unsupported.components[0].unit.activeIssues, isNotEmpty);
      expect(() => unsupported.confirmComponentUnit(0), throwsStateError);
    });

    test(
      'water correction and manual behavior require explicit confirmation',
      () {
        final bulk = ReviewRecipeDraft.fromExtracted(
          _fixture(),
        ).confirmAllUnambiguous();

        final corrected = bulk
            .editComponentUnit(2, 'g')
            .confirmComponentUnit(2)
            .confirmComponentBehavior(3);

        expect(corrected.components[2].unit.value, 'g');
        expect(corrected.components[2].unit.isConfirmed, isTrue);
        expect(corrected.components[2].unit.sourceIssues, isNotEmpty);
        expect(corrected.components[2].unit.activeIssues, isEmpty);
        expect(corrected.components[3].behavior.isConfirmed, isTrue);
      },
    );

    test('bulk confirmation skips an incompatible maximum yield unit', () {
      final json =
          jsonDecode(File(_fixturePath).readAsStringSync())
              as Map<String, Object?>;
      final recipe = json['recipe']! as Map<String, Object?>;
      final maxYield = recipe['maxBatchYield']! as Map<String, Object?>;
      final unit = maxYield['unit']! as Map<String, Object?>;
      unit['value'] = 'kg';

      final draft = ReviewRecipeDraft.fromExtracted(
        ExtractedRecipeDraft.fromJson(json),
      ).confirmAllUnambiguous();

      expect(draft.recipe.maxBatchYield!.unit.isConfirmed, isFalse);
      expect(draft.recipe.maxBatchYield!.unit.activeIssues, isNotEmpty);
    });

    test('corrects and confirms every editable review field', () {
      final json =
          jsonDecode(File(_fixturePath).readAsStringSync())
              as Map<String, Object?>;
      final recipe = json['recipe']! as Map<String, Object?>;
      (recipe['name']! as Map<String, Object?>)['value'] = null;
      final baseYield = recipe['baseYield']! as Map<String, Object?>;
      (baseYield['amount']! as Map<String, Object?>)['value'] = '0';
      (baseYield['unit']! as Map<String, Object?>)['value'] = 'cup';
      final maxYield = recipe['maxBatchYield']! as Map<String, Object?>;
      (maxYield['amount']! as Map<String, Object?>)['value'] = '0';
      (maxYield['unit']! as Map<String, Object?>)['value'] = 'kg';
      final notes = recipe['preparationNotes']! as List<Object?>;
      (notes.single! as Map<String, Object?>)['value'] = null;

      final components = json['components']! as List<Object?>;
      final flour = components[0]! as Map<String, Object?>;
      (flour['name']! as Map<String, Object?>)['value'] = ' ';
      (flour['amount']! as Map<String, Object?>)['value'] = '0';
      (flour['unit']! as Map<String, Object?>)['value'] = 'cup';
      (flour['behavior']! as Map<String, Object?>)['value'] = null;
      final manual = components[3]! as Map<String, Object?>;
      (manual['note']! as Map<String, Object?>)['value'] = null;

      var draft = ReviewRecipeDraft.fromExtracted(
        ExtractedRecipeDraft.fromJson(json),
      ).confirmAllUnambiguous();
      draft = draft
          .editRecipeName('Croissant dough')
          .confirmRecipeName()
          .editBaseYieldAmount('24')
          .confirmBaseYieldAmount()
          .editBaseYieldUnit('piece')
          .confirmBaseYieldUnit()
          .editMaxBatchYieldAmount('12')
          .confirmMaxBatchYieldAmount()
          .editMaxBatchYieldUnit('piece')
          .confirmMaxBatchYieldUnit()
          .editPreparationNote(0, 'Rest 20 minutes between folds.')
          .confirmPreparationNote(0)
          .editComponentName(0, 'Flour')
          .confirmComponentName(0)
          .editComponentBehavior(0, DraftScalingBehavior.proportional)
          .confirmComponentBehavior(0)
          .editComponentAmount(0, '1000')
          .confirmComponentAmount(0)
          .editComponentUnit(0, 'g')
          .confirmComponentUnit(0)
          .editComponentUnit(2, 'g')
          .confirmComponentUnit(2)
          .confirmComponentBehavior(3)
          .editComponentNote(3, 'For dusting the bench, as needed.')
          .confirmComponentNote(3);

      final result = const RecipeDraftVerifier().verify(draft);
      expect(result, isA<RecipeDraftVerified>());
      expect(() => draft.editComponentNote(0, 'none'), throwsStateError);
      expect(() => draft.confirmComponentNote(0), throwsStateError);
    });

    test('clears numeric quantity fields when changing to manual', () {
      final draft = ReviewRecipeDraft.fromExtracted(
        _fixture(),
      ).confirmAllUnambiguous();

      final edited = draft.editComponentUnit(3, 'g');
      final changedToManual = draft.editComponentBehavior(
        0,
        DraftScalingBehavior.manual,
      );

      expect(edited.components[3].unit.activeIssues, isNotEmpty);
      expect(changedToManual.components[0].amount.value, isNull);
      expect(changedToManual.components[0].unit.value, isNull);
      expect(changedToManual.components[0].amount.activeIssues, isEmpty);
      expect(changedToManual.components[0].unit.activeIssues, isEmpty);
    });

    test(
      'retains the proposal while explicitly confirming no maximum yield',
      () {
        final draft = ReviewRecipeDraft.fromExtracted(_fixture());

        expect(draft.confirmMaxBatchYieldAbsent, throwsStateError);
        final removed = draft.removeMaxBatchYield();
        final confirmed = removed.confirmMaxBatchYieldAbsent();

        expect(removed.recipe.maxBatchYield, isNull);
        expect(removed.recipe.maxBatchYieldProposal, isNotNull);
        expect(removed.recipe.isMaxBatchYieldAbsentConfirmed, isFalse);
        expect(confirmed.recipe.isMaxBatchYieldAbsentConfirmed, isTrue);
      },
    );
  });
}
