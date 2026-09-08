import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';

import 'fakes.dart';

void main() {
  test('a recipe with no sub-recipes resolves to itself alone', () async {
    final recipes = FakeRecipeRepository();
    final root = buildRecipe(id: 'cake');

    final closure = await resolveDependencyClosure(recipes, root);

    expect(closure.keys, ['cake']);
    expect(closure['cake'], same(root));
  });

  test(
    'the passed root wins over the stored revision of the same id',
    () async {
      final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'cake'));
      final edited = buildRecipe(
        id: 'cake',
        revision: 2,
        components: [buildSubRecipeComponent('syrup')],
      );
      recipes.seed(buildRecipe(id: 'syrup'));

      final closure = await resolveDependencyClosure(recipes, edited);

      expect(closure['cake']!.revision, 2);
      expect(closure.keys, containsAll(<String>['cake', 'syrup']));
    },
  );

  test('a sub-recipe reached through two paths is loaded once', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'syrup'))
      ..seed(
        buildRecipe(id: 'left', components: [buildSubRecipeComponent('syrup')]),
      )
      ..seed(
        buildRecipe(
          id: 'right',
          components: [buildSubRecipeComponent('syrup')],
        ),
      );
    final root = buildRecipe(
      id: 'cake',
      components: [
        buildSubRecipeComponent('left'),
        RecipeComponent(
          id: 'sub-right',
          target: const SubRecipeRef('right'),
          baseQuantity: Quantity.parse('100', Unit.gram),
          behavior: ScalingBehavior.proportional,
          displayOrder: 2,
        ),
      ],
    );

    final closure = await resolveDependencyClosure(recipes, root);

    expect(closure.keys.toSet(), {'cake', 'left', 'right', 'syrup'});
    expect(recipes.calls.where((call) => call == 'findLatest:syrup').length, 1);
  });

  test('a cycle terminates the walk instead of hanging', () async {
    final recipes = FakeRecipeRepository()
      ..seed(
        buildRecipe(id: 'syrup', components: [buildSubRecipeComponent('cake')]),
      );
    final root = buildRecipe(
      id: 'cake',
      components: [buildSubRecipeComponent('syrup')],
    );

    final closure = await resolveDependencyClosure(recipes, root);

    expect(closure.keys.toSet(), {'cake', 'syrup'});
  });

  test('an id the repository does not have is left out', () async {
    final recipes = FakeRecipeRepository();
    final root = buildRecipe(
      id: 'cake',
      components: [buildSubRecipeComponent('missing')],
    );

    final closure = await resolveDependencyClosure(recipes, root);

    expect(closure.keys, ['cake']);
  });
}
