import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';

import 'fakes.dart';

void main() {
  test('the library lists every stored ingredient, ordered by name', () async {
    final ingredients = FakeIngredientRepository();
    await ingredients.upsert(buildIngredient(id: 'sugar', name: 'Sugar'));
    await ingredients.upsert(buildIngredient(id: 'butter', name: 'Butter'));

    final all = await ListIngredients(ingredients).call();

    // Ordered, not merely present: the repository interface promises name
    // order and the picker relies on it, so an implementation that returned
    // insertion order has to fail here.
    expect(all.map((i) => i.id), ['butter', 'sugar']);
  });

  test('an empty library reads as an empty list, not a failure', () async {
    expect(await ListIngredients(FakeIngredientRepository()).call(), isEmpty);
  });

  test('saving stores the ingredient under its id', () async {
    final ingredients = FakeIngredientRepository();

    await SaveIngredient(
      ingredients,
    ).call(Ingredient(id: 'milk', name: 'Whole milk', defaultUnit: Unit.gram));

    expect(ingredients.stored['milk']!.name, 'Whole milk');
    expect(ingredients.stored['milk']!.defaultUnit, Unit.gram);
  });

  test('saving under an existing id replaces that row', () async {
    final ingredients = FakeIngredientRepository();
    final save = SaveIngredient(ingredients);

    await save(buildIngredient(id: 'milk', name: 'Milk'));
    await save(buildIngredient(id: 'milk', name: 'Whole milk'));

    expect(ingredients.stored, hasLength(1));
    expect(ingredients.stored['milk']!.name, 'Whole milk');
  });
}
