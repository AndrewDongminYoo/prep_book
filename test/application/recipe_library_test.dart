import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';

import 'fakes.dart';

void main() {
  test('the library lists the latest revision of every recipe', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'Old'))
      ..seed(buildRecipe(id: 'a', revision: 2, name: 'New'))
      ..seed(buildRecipe(id: 'b'));

    final all = await ListLibrary(recipes).call();

    expect(all.map((r) => r.name), containsAll(<String>['New', 'Test recipe']));
    expect(all.where((r) => r.id == 'a'), hasLength(1));
  });

  test('search matches a substring of the name, case-insensitively', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'CHOCOLATE Torte'))
      ..seed(buildRecipe(id: 'b', name: 'Brioche'));

    final hits = await SearchLibrary(recipes).call('CHOCOLATE');

    expect(hits.map((r) => r.id), ['a']);
  });

  test('search returns latest revisions only', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'Brioche'))
      ..seed(buildRecipe(id: 'a', revision: 2, name: 'Brioche Loaf'));

    final hits = await SearchLibrary(recipes).call('brioche');

    expect(hits, hasLength(1));
    expect(hits.single.revision, 2);
  });

  test('an empty query returns the whole library', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'Recipe A'))
      ..seed(buildRecipe(id: 'b', name: 'Recipe B'));

    final hits = await SearchLibrary(recipes).call('');

    expect(hits.map((r) => r.id), containsAll(<String>['a', 'b']));
  });
}
