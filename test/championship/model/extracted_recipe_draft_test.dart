import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';

const _fixturePath = 'assets/championship/sample_croissant_draft.json';

Map<String, Object?> _fixtureJson() => jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>;

void main() {
  group('ExtractedRecipeDraft', () {
    test('decodes the checked-in sample without changing its JSON', () {
      final json = _fixtureJson();

      final draft = ExtractedRecipeDraft.fromJson(json);

      expect(draft.schemaVersion, 1);
      expect(draft.sourceKind, RecipeImportSourceKind.sample);
      expect(draft.recipe.name.value, 'Croissant dough');
      expect(draft.recipe.baseYield.amount.value, '24');
      expect(draft.recipe.baseYield.unit.value, 'piece');
      expect(draft.recipe.maxBatchYield!.amount.value, '12');
      expect(
        draft.recipe.preparationNotes.single.value,
        'Rest 20 minutes between folds.',
      );
      expect(draft.components, hasLength(4));
      expect(draft.components[0].amount.value, '1000');
      expect(draft.components[1].amount.value, '500');
      expect(draft.components[2].amount.value, '480');
      expect(draft.components[2].unit.value, isNull);
      expect(draft.components[2].unit.issues, [
        'The source does not state a unit.',
      ]);
      expect(draft.components[3].behavior.value, DraftScalingBehavior.manual);
      expect(draft.components[3].amount.value, isNull);
      expect(draft.toJson(), json);
    });

    test('preserves evidence and exposes immutable collections', () {
      final draft = ExtractedRecipeDraft.fromJson(_fixtureJson());

      expect(draft.components[2].unit.evidence, 'Water 480');
      expect(
        () => draft.components.add(draft.components.first),
        throwsUnsupportedError,
      );
      expect(
        () => draft.components[2].unit.issues.add('changed'),
        throwsUnsupportedError,
      );
    });

    test('rejects a schema version other than one', () {
      final integerJson = _fixtureJson()..['schemaVersion'] = 2;
      final decimalJson = _fixtureJson()..['schemaVersion'] = 1.0;

      expect(
        () => ExtractedRecipeDraft.fromJson(integerJson),
        throwsFormatException,
      );
      expect(
        () => ExtractedRecipeDraft.fromJson(decimalJson),
        throwsFormatException,
      );
    });

    test('rejects JSON numbers used as quantities', () {
      final json = _fixtureJson();
      final components = json['components']! as List<Object?>;
      final flour = components.first! as Map<String, Object?>;
      final amount = flour['amount']! as Map<String, Object?>;
      amount['value'] = 1000;

      expect(() => ExtractedRecipeDraft.fromJson(json), throwsFormatException);
    });

    test('rejects a field without issues', () {
      final json = _fixtureJson();
      final recipe = json['recipe']! as Map<String, Object?>;
      (recipe['name']! as Map<String, Object?>).remove('issues');

      expect(() => ExtractedRecipeDraft.fromJson(json), throwsFormatException);
    });

    test('rejects an unknown confidence', () {
      final json = _fixtureJson();
      final recipe = json['recipe']! as Map<String, Object?>;
      final name = recipe['name']! as Map<String, Object?>;
      name['confidence'] = 'certain';

      expect(() => ExtractedRecipeDraft.fromJson(json), throwsFormatException);
    });

    test('rejects an unknown scaling behavior', () {
      final json = _fixtureJson();
      final components = json['components']! as List<Object?>;
      final flour = components.first! as Map<String, Object?>;
      final behavior = flour['behavior']! as Map<String, Object?>;
      behavior['value'] = 'sometimes';

      expect(() => ExtractedRecipeDraft.fromJson(json), throwsFormatException);
    });

    test('rejects a numeric amount on a manual component', () {
      final json = _fixtureJson();
      final components = json['components']! as List<Object?>;
      final manual = components.last! as Map<String, Object?>;
      final amount = manual['amount']! as Map<String, Object?>;
      amount['value'] = '1';

      expect(() => ExtractedRecipeDraft.fromJson(json), throwsFormatException);
    });

    test('rejects unknown properties at every object boundary', () {
      final json = _fixtureJson()..['providerId'] = 'not-allowed';

      expect(() => ExtractedRecipeDraft.fromJson(json), throwsFormatException);

      final nestedJson = _fixtureJson();
      final recipe = nestedJson['recipe']! as Map<String, Object?>;
      recipe['providerId'] = 'not-allowed';
      expect(
        () => ExtractedRecipeDraft.fromJson(nestedJson),
        throwsFormatException,
      );
    });

    test('rejects wrong object, array, and field metadata types', () {
      final invalidDocuments = <Map<String, Object?>>[];
      final numericEvidence = _fixtureJson();
      final evidenceRecipe = numericEvidence['recipe']! as Map<String, Object?>;
      final evidenceName = evidenceRecipe['name']! as Map<String, Object?>;
      evidenceName['evidence'] = 1;

      final numericIssue = _fixtureJson();
      final issueRecipe = numericIssue['recipe']! as Map<String, Object?>;
      final issueName = issueRecipe['name']! as Map<String, Object?>;
      issueName['issues'] = <Object?>[1];

      invalidDocuments
        ..add(_fixtureJson()..['recipe'] = <Object?>[])
        ..add(_fixtureJson()..['components'] = <String, Object?>{})
        ..add(numericEvidence)
        ..add(numericIssue)
        ..add(_fixtureJson()..['sourceKind'] = 1)
        ..add(_fixtureJson()..remove('sourceKind'));

      for (final document in invalidDocuments) {
        expect(
          () => ExtractedRecipeDraft.fromJson(document),
          throwsFormatException,
        );
      }
    });
  });
}
