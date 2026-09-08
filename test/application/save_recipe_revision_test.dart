import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';

import 'fakes.dart';

void main() {
  test('a first save becomes revision 1', () async {
    final recipes = FakeRecipeRepository();
    final saved = await SaveRecipeRevision(recipes).call(buildRecipe(id: 'a'));

    expect(saved.revision, 1);
    expect((await recipes.findLatest('a'))!.revision, 1);
  });

  test(
    'an edit becomes the next revision and leaves the old one readable',
    () async {
      final recipes = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'a', name: 'Old'));

      final saved = await SaveRecipeRevision(
        recipes,
      ).call(buildRecipe(id: 'a', name: 'New'));

      expect(saved.revision, 2);
      expect((await recipes.findRevision('a', 1))!.name, 'Old');
      expect((await recipes.findRevision('a', 2))!.name, 'New');
    },
  );

  test('the revision the caller supplied is ignored', () async {
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));

    final saved = await SaveRecipeRevision(
      recipes,
    ).call(buildRecipe(id: 'a', revision: 99));

    expect(saved.revision, 2);
  });

  test('a missing sub-recipe is rejected and nothing is written', () async {
    final recipes = FakeRecipeRepository();
    final edited = buildRecipe(
      id: 'a',
      components: [buildSubRecipeComponent('nope')],
    );

    await expectLater(
      SaveRecipeRevision(recipes).call(edited),
      throwsA(isA<MissingDependencyError>()),
    );
    expect(
      recipes.calls.where((call) => call.startsWith('saveRevision:')),
      isEmpty,
    );
  });

  test(
    'a cycle the edit introduces is rejected and nothing is written',
    () async {
      // Stored: syrup -> cake. Stored cake does not reference syrup, so a
      // validation that read the stored revision would see no cycle.
      final recipes = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'cake'))
        ..seed(
          buildRecipe(
            id: 'syrup',
            components: [buildSubRecipeComponent('cake')],
          ),
        );
      final edited = buildRecipe(
        id: 'cake',
        components: [buildSubRecipeComponent('syrup')],
      );

      await expectLater(
        SaveRecipeRevision(recipes).call(edited),
        throwsA(isA<RecipeCycleError>()),
      );
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
    },
  );
}
