import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';

import 'fakes.dart';

void main() {
  test('archiving sets the flag on every revision', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a'))
      ..seed(buildRecipe(id: 'a', revision: 2));

    await ArchiveRecipe(recipes).call('a', isArchived: true);

    expect((await recipes.findRevision('a', 1))!.isArchived, isTrue);
    expect((await recipes.findRevision('a', 2))!.isArchived, isTrue);
  });

  test('restoring clears it again', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', isArchived: true));

    await ArchiveRecipe(recipes).call('a', isArchived: false);

    expect((await recipes.findLatest('a'))!.isArchived, isFalse);
  });

  test('a duplicate starts at revision 1 under the new id', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', revision: 4, name: 'Original'));

    final copy = await DuplicateRecipe(
      recipes,
    ).call(sourceId: 'a', newId: 'b', name: 'Copy');

    expect(copy.id, 'b');
    expect(copy.revision, 1);
    expect(copy.name, 'Copy');
    expect((await recipes.findLatest('a'))!.name, 'Original');
  });

  test('a duplicate is never archived, whatever the source was', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', isArchived: true));

    final copy = await DuplicateRecipe(
      recipes,
    ).call(sourceId: 'a', newId: 'b', name: 'Copy');

    expect(copy.isArchived, isFalse);
  });

  test('duplicating a recipe that does not exist throws', () async {
    final recipes = FakeRecipeRepository();

    await expectLater(
      DuplicateRecipe(recipes).call(sourceId: 'gone', newId: 'b', name: 'Copy'),
      throwsA(
        isA<MissingDependencyError>().having(
          (e) => e.message,
          'message',
          'recipe gone is not in the index',
        ),
      ),
    );
  });

  test(
    'category, maxBatchYield, and preparationNotes survive onto the copy',
    () async {
      final recipes = FakeRecipeRepository()
        ..seed(
          Recipe(
            id: 'a',
            revision: 1,
            name: 'Original',
            baseYield: Quantity.parse('1000', Unit.gram),
            modifiedAt: DateTime.utc(2026, 9, 8),
            category: 'Pastry',
            maxBatchYield: Quantity.parse('5000', Unit.gram),
            preparationNotes: const ['Preheat oven', 'Rest dough'],
            components: [
              RecipeComponent(
                id: 'flour',
                target: const IngredientRef('flour'),
                baseQuantity: Quantity.parse('500', Unit.gram),
                behavior: ScalingBehavior.proportional,
                displayOrder: 0,
              ),
            ],
          ),
        );

      final copy = await DuplicateRecipe(
        recipes,
      ).call(sourceId: 'a', newId: 'b', name: 'Copy');

      expect(copy.category, 'Pastry');
      expect(copy.maxBatchYield, Quantity.parse('5000', Unit.gram));
      expect(copy.preparationNotes, ['Preheat oven', 'Rest dough']);
    },
  );
}
