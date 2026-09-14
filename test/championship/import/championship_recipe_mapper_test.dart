import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';
import 'package:prep_book/domain/domain.dart';

const _fixturePath = 'assets/championship/sample_croissant_draft.json';

Map<String, Object?> _fixtureJson() =>
    jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>;

VerifiedRecipeDraft _verifiedDraft([Map<String, Object?>? json]) {
  final extracted = ExtractedRecipeDraft.fromJson(json ?? _fixtureJson());
  var review = ReviewRecipeDraft.fromExtracted(
    extracted,
  ).confirmAllUnambiguous();
  for (var index = 0; index < review.components.length; index += 1) {
    final component = review.components[index];
    if (component.name.value == 'Water' && component.unit.value == null) {
      review = review.editComponentUnit(index, 'g').confirmComponentUnit(index);
    }
    if (component.behavior.value == DraftScalingBehavior.manual) {
      review = review.confirmComponentBehavior(index);
    }
  }
  final result = const RecipeDraftVerifier().verify(review);
  return (result as RecipeDraftVerified).draft;
}

void main() {
  test('maps the verified draft into deterministic domain snapshots', () {
    final modifiedAt = DateTime.utc(2026, 9, 13, 3, 4, 5);

    final bundle = const ChampionshipRecipeMapper().map(
      _verifiedDraft(),
      modifiedAt: modifiedAt,
    );

    expect(bundle.recipe.id, 'championship-recipe-1');
    expect(bundle.recipe.revision, 1);
    expect(bundle.recipe.modifiedAt, modifiedAt);
    expect(bundle.recipe.name, 'Croissant dough');
    expect(bundle.recipe.baseYield, Quantity.parse('24', Unit.count('piece')));
    expect(
      bundle.recipe.maxBatchYield,
      Quantity.parse('12', Unit.count('piece')),
    );
    expect(bundle.recipe.preparationNotes, ['Rest 20 minutes between folds.']);

    expect(bundle.ingredients.map((ingredient) => ingredient.id), [
      'championship-ingredient-1',
      'championship-ingredient-2',
      'championship-ingredient-3',
    ]);
    expect(bundle.ingredients.map((ingredient) => ingredient.name), [
      'Flour',
      'Butter',
      'Water',
    ]);

    expect(bundle.recipe.components.map((component) => component.id), [
      'championship-component-1',
      'championship-component-2',
      'championship-component-3',
      'championship-component-4',
    ]);
    expect(
      bundle.recipe.components.map((component) => component.displayOrder),
      [0, 1, 2, 3],
    );
    expect(
      bundle.recipe.components.map(
        (component) => (component.target as IngredientRef).ingredientId,
      ),
      [
        'championship-ingredient-1',
        'championship-ingredient-2',
        'championship-ingredient-3',
        'championship-ingredient-1',
      ],
    );
    expect(
      bundle.recipe.components[0].baseQuantity,
      Quantity.parse('1000', Unit.gram),
    );
    expect(bundle.recipe.components[3].baseQuantity, isNull);
    expect(bundle.recipe.components[3].behavior, ScalingBehavior.manual);
    expect(
      bundle.recipe.components[3].note,
      'For dusting the bench, as needed.',
    );
    expect(
      () => bundle.ingredients.add(bundle.ingredients.first),
      throwsUnsupportedError,
    );
  });

  test('normalizes names for identity and maps every scaling behavior', () {
    final json = _fixtureJson();
    final components = json['components']! as List<Object?>;
    final flour = components[0]! as Map<String, Object?>;
    final butter = components[1]! as Map<String, Object?>;
    final dusting = components[3]! as Map<String, Object?>;
    (flour['behavior']! as Map<String, Object?>)['value'] = 'perBatch';
    (butter['behavior']! as Map<String, Object?>)['value'] = 'fixedOnce';
    (dusting['name']! as Map<String, Object?>)['value'] = ' flour ';
    final draft = _verifiedDraft(json);

    final bundle = const ChampionshipRecipeMapper().map(
      draft,
      modifiedAt: DateTime.utc(2026, 9, 13),
    );

    expect(bundle.ingredients, hasLength(3));
    expect(bundle.recipe.components.map((component) => component.behavior), [
      ScalingBehavior.perBatch,
      ScalingBehavior.fixedOnce,
      ScalingBehavior.proportional,
      ScalingBehavior.manual,
    ]);
    final targets = bundle.recipe.components
        .map((component) => (component.target as IngredientRef).ingredientId)
        .toList();
    expect(targets.first, targets.last);
  });

  test('uses a non-quantity sentinel for a manual-only ingredient', () {
    final json = _fixtureJson();
    final components = json['components']! as List<Object?>;
    final manual = components.last! as Map<String, Object?>;
    (manual['name']! as Map<String, Object?>)['value'] = 'Dusting flour';
    json['components'] = [manual];
    final draft = _verifiedDraft(json);

    final bundle = const ChampionshipRecipeMapper().map(
      draft,
      modifiedAt: DateTime.utc(2026, 9, 13),
    );

    expect(bundle.ingredients.single.defaultUnit, Unit.count('manual'));
  });
}
