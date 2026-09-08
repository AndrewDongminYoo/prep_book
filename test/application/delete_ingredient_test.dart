import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';

import 'fakes.dart';

void main() {
  test('an unused ingredient is deleted on the first call', () async {
    final ingredients = FakeIngredientRepository()
      ..stored['flour'] = buildIngredient(id: 'flour');
    final recipes = FakeRecipeRepository();

    final outcome = await DeleteIngredient(ingredients, recipes).call('flour');

    expect(outcome.deleted, isTrue);
    expect(outcome.blockedBy, isEmpty);
    expect(ingredients.stored, isEmpty);
  });

  test(
    'an ingredient in use is not deleted, and its recipes come back',
    () async {
      final ingredients = FakeIngredientRepository()
        ..stored['flour'] = buildIngredient(id: 'flour');
      final recipes = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'a'))
        ..seed(buildRecipe(id: 'b'));

      final outcome = await DeleteIngredient(
        ingredients,
        recipes,
      ).call('flour');

      expect(outcome.deleted, isFalse);
      expect(outcome.blockedBy.map((r) => r.id).toSet(), {'a', 'b'});
      expect(ingredients.stored.keys, ['flour']);
    },
  );

  test(
    'a single recipe using it still refuses deletion without force',
    () async {
      // Closes a gap a two-recipe test cannot: an implementation that
      // blocks only once more than one recipe is found (e.g. checking
      // `users.length > 1` instead of `users.isNotEmpty`) would pass the
      // two-recipe case above but wrongly allow this one through.
      final ingredients = FakeIngredientRepository()
        ..stored['flour'] = buildIngredient(id: 'flour');
      final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));

      final outcome = await DeleteIngredient(
        ingredients,
        recipes,
      ).call('flour');

      expect(outcome.deleted, isFalse);
      expect(outcome.blockedBy.map((r) => r.id), ['a']);
      expect(ingredients.stored.keys, ['flour']);
    },
  );

  test('an archived recipe still blocks deletion without force', () async {
    // Closes a gap none of the other tests can: an implementation that
    // filters blockedBy down to non-archived recipes before deciding
    // whether to block would pass every other test here (none of them
    // seed an archived user) while silently deleting an ingredient an
    // archived recipe still names.
    final ingredients = FakeIngredientRepository()
      ..stored['flour'] = buildIngredient(id: 'flour');
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', isArchived: true));

    final outcome = await DeleteIngredient(ingredients, recipes).call('flour');

    expect(outcome.deleted, isFalse);
    expect(outcome.blockedBy.map((r) => r.id), ['a']);
    expect(ingredients.stored.keys, ['flour']);
  });

  test('forcing deletes it and still reports what used it', () async {
    final ingredients = FakeIngredientRepository()
      ..stored['flour'] = buildIngredient(id: 'flour');
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));

    final outcome = await DeleteIngredient(
      ingredients,
      recipes,
    ).call('flour', force: true);

    expect(outcome.deleted, isTrue);
    expect(outcome.blockedBy.map((r) => r.id), ['a']);
    expect(ingredients.stored, isEmpty);
  });
}
