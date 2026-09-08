# Application Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build `lib/application/`, the use cases a screen invokes for recipe revision management, production execution, and history.

**Architecture:** One class per use case, taking repository interfaces as constructor arguments and exposing a single `call` method. No use case holds mutable state, so every one is `const`-constructible. The layer depends on the repository interfaces only, never on their sqflite implementations, which is what lets every test run against in-memory fakes with no database.

**Tech Stack:** Dart, `package:meta`, the existing `lib/domain/` and `lib/persistence/repositories.dart`. No new package dependency.

**Spec:** `docs/specs/2026-09-08-application-layer.md`

## Global Constraints

- **`lib/application/` may import only** `package:prep_book/domain/…`, `package:prep_book/persistence/repositories.dart`, sibling `package:prep_book/application/…` files, `package:meta/…`, and `dart:` libraries. Task 1 makes this a test.
- **Never import** `package:sqflite`, `package:sqflite_common_ffi`, `package:flutter/…`, or anything under `lib/persistence/sqflite/`.
- **Coverage must be 100 percent.** `VeryGoodOpenSource/very_good_workflows` defaults `min_coverage` to 100, so every line added needs its test in the same task.
- **Verification command for every task:** `flutter analyze && very_good test --coverage`. Use `very_good`, not plain `flutter test --coverage`; CLAUDE.md explains why.
- **`Recipe` has no `copyWith`.** Rebuilding one means calling the factory with all ten arguments. Two tasks do this; both spell it out.
- **`OverrideKey` is `typedef OverrideKey = (String recipeId, String componentId)`**, a record, not a class.
- **A recipe's dependency list is `Recipe.subRecipeIds`**, a getter returning `List<String>`. There is no `dependsOn`.
- **Do not touch `lib/counter/`.** It is deleted in the change that adds the first real screen, which belongs to the presentation unit.
- **Commit after every task.** Conventional commits, no Co-Author lines, no session-URL trailer.

## File Structure

Created under `lib/application/`:

| File                        | Responsibility                                                           |
| --------------------------- | ------------------------------------------------------------------------ |
| `application.dart`          | Barrel. Each task adds its own export.                                   |
| `dependency_closure.dart`   | `resolveDependencyClosure`, shared by recipe saving and run calculation. |
| `save_recipe_revision.dart` | `SaveRecipeRevision`.                                                    |
| `recipe_library.dart`       | `ListLibrary`, `SearchLibrary`.                                          |
| `recipe_lifecycle.dart`     | `ArchiveRecipe`, `DuplicateRecipe`.                                      |
| `delete_ingredient.dart`    | `DeleteIngredient` and its `IngredientDeletion` result.                  |
| `start_production_run.dart` | `StartProductionRun`, `RunIdSource`, `Clock`.                            |
| `production_run_edits.dart` | `AcknowledgeWarning`, `ApplyOverride`, `SaveProductionRun`.              |
| `production_history.dart`   | `ListProductionHistory`, `OpenProductionRun`.                            |

Created under `test/application/`:

| File                                               | Responsibility                                                                                         |
| -------------------------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `fakes.dart`                                       | In-memory `IngredientRepository`, `RecipeRepository`, `ProductionRunRepository`, plus recipe fixtures. |
| `application_boundary_test.dart`                   | The import allowlist.                                                                                  |
| one `<file>_test.dart` per `lib/application/` file | That file's behaviour.                                                                                 |

---

### Task 1: Test harness and the import boundary

The boundary test exists before any use case does, so no task can introduce a forbidden import and have it noticed later in review.

**Files:**

- Create: `lib/application/application.dart`
- Create: `test/application/fakes.dart`
- Create: `test/application/application_boundary_test.dart`

**Interfaces:**

- Consumes: `IngredientRepository`, `RecipeRepository`, `ProductionRunRepository`, `ProductionRunSummary` from `package:prep_book/persistence/repositories.dart`.
- Produces: `FakeIngredientRepository`, `FakeRecipeRepository`, `FakeProductionRunRepository`, and the fixture builders `buildRecipe` and `buildIngredient`, all used by every later task.

- [ ] **Step 1: Read the interfaces you are faking**

Open `lib/persistence/repositories.dart` and read all three interfaces in full. The method names and signatures below were copied from it, but read it yourself — a fake that implements a method the interface does not declare fails to compile, and one that misses a method fails the same way.

- [ ] **Step 2: Write the fakes**

Create `test/application/fakes.dart`:

```dart
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// A one-component recipe, enough for most use-case tests.
Recipe buildRecipe({
  required String id,
  int revision = 1,
  String name = 'Test recipe',
  List<RecipeComponent>? components,
  bool isArchived = false,
}) => Recipe(
  id: id,
  revision: revision,
  name: name,
  baseYield: Quantity.parse('1000', Unit.gram),
  modifiedAt: DateTime.utc(2026, 9, 8),
  isArchived: isArchived,
  components:
      components ??
      [
        RecipeComponent(
          id: 'flour',
          target: const IngredientRef('flour'),
          baseQuantity: Quantity.parse('500', Unit.gram),
          behavior: ScalingBehavior.proportional,
          displayOrder: 0,
        ),
      ],
);

/// A recipe with one manual line, so its calculated result carries a
/// blocking `ManualComponentWarning` for Task 8 to acknowledge.
Recipe buildRecipeWithManualComponent({required String id}) => buildRecipe(
  id: id,
  components: [
    RecipeComponent(
      id: 'flour',
      target: const IngredientRef('flour'),
      baseQuantity: Quantity.parse('500', Unit.gram),
      behavior: ScalingBehavior.proportional,
      displayOrder: 0,
    ),
    RecipeComponent(
      id: 'salt',
      target: const IngredientRef('salt'),
      baseQuantity: null,
      behavior: ScalingBehavior.manual,
      displayOrder: 1,
    ),
  ],
);

/// A component referencing the sub-recipe [recipeId].
RecipeComponent buildSubRecipeComponent(String recipeId) => RecipeComponent(
  id: 'sub-$recipeId',
  target: SubRecipeRef(recipeId),
  baseQuantity: Quantity.parse('100', Unit.gram),
  behavior: ScalingBehavior.proportional,
  displayOrder: 1,
);

Ingredient buildIngredient({required String id, String name = 'Flour'}) =>
    Ingredient(id: id, name: name, defaultUnit: Unit.gram);

/// In-memory [RecipeRepository]. Stores every revision, keyed by id.
final class FakeRecipeRepository implements RecipeRepository {
  final Map<String, List<Recipe>> revisions = {};

  /// Every call this fake received, in order, for asserting that a rejected
  /// operation wrote nothing.
  final List<String> calls = [];

  void seed(Recipe recipe) =>
      revisions.putIfAbsent(recipe.id, () => []).add(recipe);

  @override
  Future<List<Recipe>> listLatestRevisions() async => [
    for (final list in revisions.values) _highest(list),
  ];

  @override
  Future<Recipe?> findRevision(String id, int revision) async {
    for (final recipe in revisions[id] ?? const <Recipe>[]) {
      if (recipe.revision == revision) return recipe;
    }
    return null;
  }

  @override
  Future<Recipe?> findLatest(String id) async {
    final list = revisions[id];
    if (list == null || list.isEmpty) return null;
    return _highest(list);
  }

  @override
  Future<void> saveRevision(Recipe recipe) async {
    calls.add('saveRevision:${recipe.id}:${recipe.revision}');
    final list = revisions.putIfAbsent(recipe.id, () => []);
    if (list.any((stored) => stored.revision == recipe.revision)) {
      throw StateError('revision ${recipe.revision} of ${recipe.id} exists');
    }
    list.add(recipe);
  }

  @override
  Future<void> setArchived(String id, {required bool isArchived}) async {
    calls.add('setArchived:$id:$isArchived');
    final list = revisions[id];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      list[i] = _withArchived(list[i], isArchived: isArchived);
    }
  }

  @override
  Future<List<Recipe>> listLatestRevisionsUsingIngredient(
    String ingredientId,
  ) async => [
    for (final list in revisions.values)
      if (_usesIngredient(_highest(list), ingredientId)) _highest(list),
  ];

  static bool _usesIngredient(Recipe recipe, String ingredientId) =>
      recipe.components.any(
        (component) => switch (component.target) {
          IngredientRef(ingredientId: final referenced) =>
            referenced == ingredientId,
          SubRecipeRef() => false,
        },
      );

  static Recipe _highest(List<Recipe> list) =>
      list.reduce((a, b) => a.revision >= b.revision ? a : b);

  static Recipe _withArchived(Recipe recipe, {required bool isArchived}) =>
      Recipe(
        id: recipe.id,
        revision: recipe.revision,
        name: recipe.name,
        baseYield: recipe.baseYield,
        components: recipe.components,
        modifiedAt: recipe.modifiedAt,
        category: recipe.category,
        maxBatchYield: recipe.maxBatchYield,
        preparationNotes: recipe.preparationNotes,
        isArchived: isArchived,
      );
}

/// In-memory [IngredientRepository].
final class FakeIngredientRepository implements IngredientRepository {
  final Map<String, Ingredient> stored = {};

  @override
  Future<List<Ingredient>> listAll() async =>
      stored.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Ingredient?> findById(String id) async => stored[id];

  @override
  Future<void> upsert(Ingredient ingredient) async =>
      stored[ingredient.id] = ingredient;

  @override
  Future<void> delete(String id) async => stored.remove(id);
}

/// In-memory [ProductionRunRepository].
final class FakeProductionRunRepository implements ProductionRunRepository {
  final Map<String, ProductionRun> stored = {};

  @override
  Future<List<ProductionRunSummary>> listSummaries() async {
    final runs = stored.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return [
      for (final run in runs)
        ProductionRunSummary(
          id: run.id,
          recipeId: run.recipeId,
          recipeRevision: run.recipeRevision,
          targetYield: run.targetYield,
          createdAt: run.createdAt,
        ),
    ];
  }

  @override
  Future<ProductionRun?> findById(String id) async => stored[id];

  @override
  Future<void> save(ProductionRun run) async => stored[run.id] = run;

  @override
  Future<void> recordAcknowledgement(
    String runId,
    ProductionWarning warning,
  ) async {
    final run = stored[runId];
    if (run != null) stored[runId] = run.acknowledge(warning);
  }

  @override
  Future<void> recordOverride(
    String runId,
    OverrideKey key,
    Quantity value,
  ) async {
    final run = stored[runId];
    if (run == null) return;
    stored[runId] = run.override(
      recipeId: key.$1,
      componentId: key.$2,
      value: value,
    );
  }
}
```

`_usesIngredient` mirrors what `SqfliteRecipeRepository.listLatestRevisionsUsingIngredient` answers: a direct component reference only, never one reached through a sub-recipe. Read that method's own documentation before changing the fake, because a fake that answers a wider question would make Task 6's tests pass against behaviour the real repository does not have.

The `SubRecipeRef() => false` arm is written out rather than left to a wildcard so that adding a third `ComponentTarget` fails `flutter analyze` here, the same way the domain's own sealed switches do.

- [ ] **Step 3: Write the boundary test**

Create `test/application/application_boundary_test.dart`. Model it on the import-allowlist half of `test/domain/domain_purity_test.dart` — open that file and reuse its directory walk and its directive extraction rather than inventing another one.

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Prefixes a `lib/application/` source may import or export.
const _allowed = <String>[
  'package:prep_book/domain/',
  'package:prep_book/persistence/repositories.dart',
  'package:prep_book/application/',
  'package:meta/',
  'dart:',
];

void main() {
  test('every application import stays inside the allowed set', () {
    final offenders = <String>[];
    final dir = Directory('lib/application');
    for (final entity in dir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      for (final line in entity.readAsLinesSync()) {
        final match = RegExp(
          r"""^\s*(?:import|export)\s+['"]([^'"]+)['"]""",
        ).firstMatch(line);
        if (match == null) continue;
        final uri = match.group(1)!;
        if (uri.startsWith('package:') || uri.startsWith('dart:')) {
          if (!_allowed.any(uri.startsWith)) {
            offenders.add('${entity.path}: $uri');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
```

- [ ] **Step 4: Prove the boundary test can fail**

Add `import 'package:sqflite/sqflite.dart';` to `lib/application/application.dart`, run the test, confirm it fails naming that file and URI, then remove the import. A guard whose failure you have not seen is not a guard.

Run: `flutter test test/application/application_boundary_test.dart`

- [ ] **Step 5: Run the full gate**

Run: `flutter analyze && very_good test --coverage`
Expected: analyze clean, all tests pass. `application.dart` is an empty barrel at this point and contributes no uncovered lines.

- [ ] **Step 6: Commit**

```bash
git add lib/application test/application
git commit -m "test(application): add repository fakes and the import boundary"
```

---

### Task 2: Dependency closure resolution

**Files:**

- Create: `lib/application/dependency_closure.dart`
- Modify: `lib/application/application.dart`
- Test: `test/application/dependency_closure_test.dart`

**Interfaces:**

- Consumes: `FakeRecipeRepository` and `buildRecipe`/`buildSubRecipeComponent` from Task 1.
- Produces: `Future<Map<String, Recipe>> resolveDependencyClosure(RecipeRepository recipes, Recipe root)`, returning a map that includes `root` under `root.id`. Tasks 3 and 7 both call it.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';

import 'fakes.dart';

void main() {
  test('a recipe with no sub-recipes resolves to itself alone', () async {
    final recipes = FakeRecipeRepository();
    final root = buildRecipe(id: 'cake');

    final closure = await resolveDependencyClosure(recipes, root);

    expect(closure.keys, ['cake']);
    expect(closure['cake'], same(root));
  });

  test('the passed root wins over the stored revision of the same id',
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
  });

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
```

Import `package:prep_book/domain/domain.dart` in the test as well; `RecipeComponent`, `SubRecipeRef`, `Quantity`, `Unit`, and `ScalingBehavior` all come from there.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/application/dependency_closure_test.dart`
Expected: FAIL — `resolveDependencyClosure` is not defined.

- [ ] **Step 3: Implement**

Create `lib/application/dependency_closure.dart`:

```dart
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Every recipe reachable from [root] through `subRecipeIds`, keyed by id,
/// with [root] itself included under its own id.
///
/// [root] is the caller's own object, not a re-read of storage, so an edit
/// that has not been saved yet is what the walk follows. That is what lets
/// a cycle introduced *by* the edit be found: the stored revision of the
/// same id does not carry the new reference.
///
/// Dependencies are read at their latest revision, matching what
/// [RecipeRepository.listLatestRevisionsUsingIngredient] already assumes is
/// current. An id no revision is stored for is left out rather than
/// reported: the caller passes this map to `RecipeDependencyGraph` or to
/// `ProductionCalculator`, and both already raise `MissingDependencyError`
/// naming the reference and its parent. Reporting it here would duplicate
/// an error the domain owns, in a worse form, because this walk does not
/// track which parent asked.
///
/// A recipe already in the map is not visited again, so a diamond loads
/// once and a cycle terminates. The cycle is not diagnosed here either;
/// `RecipeDependencyGraph.assertResolvable` names its path.
Future<Map<String, Recipe>> resolveDependencyClosure(
  RecipeRepository recipes,
  Recipe root,
) async {
  final closure = <String, Recipe>{root.id: root};
  final pending = <String>[...root.subRecipeIds];

  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (closure.containsKey(id)) continue;
    final recipe = await recipes.findLatest(id);
    if (recipe == null) continue;
    closure[id] = recipe;
    pending.addAll(recipe.subRecipeIds);
  }

  return closure;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/application/dependency_closure_test.dart`
Expected: PASS, five tests.

- [ ] **Step 5: Export it**

Add to `lib/application/application.dart`:

```dart
export 'dependency_closure.dart';
```

- [ ] **Step 6: Run the full gate**

Run: `flutter analyze && very_good test --coverage`

- [ ] **Step 7: Commit**

```bash
git add lib/application test/application
git commit -m "feat(application): resolve a recipe's dependency closure"
```

---

### Task 3: SaveRecipeRevision

**Files:**

- Create: `lib/application/save_recipe_revision.dart`
- Modify: `lib/application/application.dart`
- Test: `test/application/save_recipe_revision_test.dart`

**Interfaces:**

- Consumes: `resolveDependencyClosure` from Task 2.
- Produces: `SaveRecipeRevision(RecipeRepository)` with `Future<Recipe> call(Recipe edited)`, returning the recipe as stored, carrying the revision this use case assigned.

- [ ] **Step 1: Write the failing tests**

```dart
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

  test('an edit becomes the next revision and leaves the old one readable',
      () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'Old'));

    final saved =
        await SaveRecipeRevision(recipes).call(buildRecipe(id: 'a', name: 'New'));

    expect(saved.revision, 2);
    expect((await recipes.findRevision('a', 1))!.name, 'Old');
    expect((await recipes.findRevision('a', 2))!.name, 'New');
  });

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
    expect(recipes.calls, isEmpty);
  });

  test('a cycle the edit introduces is rejected and nothing is written',
      () async {
    // Stored: syrup -> cake. Stored cake does not reference syrup, so a
    // validation that read the stored revision would see no cycle.
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'cake'))
      ..seed(
        buildRecipe(id: 'syrup', components: [buildSubRecipeComponent('cake')]),
      );
    final edited = buildRecipe(
      id: 'cake',
      components: [buildSubRecipeComponent('syrup')],
    );

    await expectLater(
      SaveRecipeRevision(recipes).call(edited),
      throwsA(isA<RecipeCycleError>()),
    );
    expect(recipes.calls, isEmpty);
  });
}
```

The last two tests assert `recipes.calls` is empty, which is what proves the rejection happened before the write rather than after it. `FakeRecipeRepository` records `saveRevision` and `setArchived` calls for exactly this.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/application/save_recipe_revision_test.dart`
Expected: FAIL — `SaveRecipeRevision` is not defined.

- [ ] **Step 3: Implement**

Create `lib/application/save_recipe_revision.dart`:

```dart
import 'package:prep_book/application/dependency_closure.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Writes an edited recipe as the next revision of its id.
final class SaveRecipeRevision {
  /// Creates the use case over [_recipes].
  const SaveRecipeRevision(this._recipes);

  final RecipeRepository _recipes;

  /// Stores [edited] as revision N+1 and returns it as stored.
  ///
  /// The revision on [edited] is ignored. Letting a caller supply it would
  /// put a read-modify-write in every screen and let two parallel edits
  /// choose the same number, which `saveRevision` refuses rather than
  /// merges.
  ///
  /// Throws [RecipeCycleError] naming the path, or [MissingDependencyError],
  /// before anything is written.
  Future<Recipe> call(Recipe edited) async {
    final closure = await resolveDependencyClosure(_recipes, edited);
    RecipeDependencyGraph(closure).assertResolvable(edited.id);

    final latest = await _recipes.findLatest(edited.id);
    final next = _withRevision(edited, (latest?.revision ?? 0) + 1);
    await _recipes.saveRevision(next);
    return next;
  }

  /// [Recipe] has no `copyWith`, so every field is restated here.
  static Recipe _withRevision(Recipe recipe, int revision) => Recipe(
    id: recipe.id,
    revision: revision,
    name: recipe.name,
    baseYield: recipe.baseYield,
    components: recipe.components,
    modifiedAt: recipe.modifiedAt,
    category: recipe.category,
    maxBatchYield: recipe.maxBatchYield,
    preparationNotes: recipe.preparationNotes,
    isArchived: recipe.isArchived,
  );
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/application/save_recipe_revision_test.dart`
Expected: PASS, five tests.

- [ ] **Step 5: Export, run the gate, commit**

Add `export 'save_recipe_revision.dart';` to the barrel.

Run: `flutter analyze && very_good test --coverage`

```bash
git add lib/application test/application
git commit -m "feat(application): save an edited recipe as the next revision"
```

---

### Task 4: Library reads

**Files:**

- Create: `lib/application/recipe_library.dart`
- Modify: `lib/application/application.dart`
- Test: `test/application/recipe_library_test.dart`

**Interfaces:**

- Produces: `ListLibrary(RecipeRepository)` with `Future<List<Recipe>> call()`, and `SearchLibrary(RecipeRepository)` with `Future<List<Recipe>> call(String query)`.

- [ ] **Step 1: Write the failing tests**

```dart
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
      ..seed(buildRecipe(id: 'a', name: 'Sourdough Loaf'))
      ..seed(buildRecipe(id: 'b', name: 'Brioche'));

    final hits = await SearchLibrary(recipes).call('DOUGH');

    expect(hits.map((r) => r.id), ['a']);
  });

  test('search returns latest revisions only', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'Brioche'))
      ..seed(buildRecipe(id: 'a', revision: 2, name: 'Brioche Sucree'));

    final hits = await SearchLibrary(recipes).call('brioche');

    expect(hits, hasLength(1));
    expect(hits.single.revision, 2);
  });

  test('an empty query returns the whole library', () async {
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));

    expect(await SearchLibrary(recipes).call(''), hasLength(1));
  });
}
```

- [ ] **Step 2: Run to verify failure, then implement**

Run: `flutter test test/application/recipe_library_test.dart` — expect FAIL.

Create `lib/application/recipe_library.dart`:

```dart
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// The latest revision of every recipe, archived ones included.
final class ListLibrary {
  /// Creates the use case over [_recipes].
  const ListLibrary(this._recipes);

  final RecipeRepository _recipes;

  /// Reads the library.
  Future<List<Recipe>> call() => _recipes.listLatestRevisions();
}

/// The library, filtered by name.
///
/// An in-memory filter rather than a query, because the library is one
/// restaurant's recipes and the persistence layer's query surface stays
/// smaller for it. Moving this into SQL later does not change the
/// signature.
final class SearchLibrary {
  /// Creates the use case over [_recipes].
  const SearchLibrary(this._recipes);

  final RecipeRepository _recipes;

  /// Every latest revision whose name contains [query], ignoring case. An
  /// empty [query] matches everything, which is what a cleared search box
  /// should show.
  Future<List<Recipe>> call(String query) async {
    final needle = query.toLowerCase();
    final all = await _recipes.listLatestRevisions();
    return [
      for (final recipe in all)
        if (recipe.name.toLowerCase().contains(needle)) recipe,
    ];
  }
}
```

- [ ] **Step 3: Run the tests, export, run the gate, commit**

Run: `flutter test test/application/recipe_library_test.dart` — expect PASS.

Add `export 'recipe_library.dart';` to the barrel.

Run: `flutter analyze && very_good test --coverage`

```bash
git add lib/application test/application
git commit -m "feat(application): list and search the recipe library"
```

---

### Task 5: Archive and duplicate

**Files:**

- Create: `lib/application/recipe_lifecycle.dart`
- Modify: `lib/application/application.dart`
- Test: `test/application/recipe_lifecycle_test.dart`

**Interfaces:**

- Consumes: `SaveRecipeRevision` from Task 3, which `DuplicateRecipe` reuses so the copy is validated the same way an edit is.
- Produces: `ArchiveRecipe(RecipeRepository)` with `Future<void> call(String recipeId, {required bool isArchived})`, and `DuplicateRecipe(RecipeRepository)` with `Future<Recipe> call({required String sourceId, required String newId, required String name})`.

- [ ] **Step 1: Write the failing tests**

```dart
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
      throwsA(isA<MissingDependencyError>()),
    );
  });
}
```

- [ ] **Step 2: Run to verify failure, then implement**

Create `lib/application/recipe_lifecycle.dart`:

```dart
import 'package:prep_book/application/save_recipe_revision.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Archives or restores every revision of a recipe.
final class ArchiveRecipe {
  /// Creates the use case over [_recipes].
  const ArchiveRecipe(this._recipes);

  final RecipeRepository _recipes;

  /// Sets the archived flag on every revision of [recipeId].
  ///
  /// Archiving is not deletion: the design document keeps an archived
  /// recipe readable, and a stored production run computed from it is
  /// unaffected either way.
  Future<void> call(String recipeId, {required bool isArchived}) =>
      _recipes.setArchived(recipeId, isArchived: isArchived);
}

/// Copies a recipe's latest revision under a new id.
final class DuplicateRecipe {
  /// Creates the use case over [_recipes].
  const DuplicateRecipe(this._recipes);

  final RecipeRepository _recipes;

  /// Writes the latest revision of [sourceId] as revision 1 of [newId].
  ///
  /// [name] is the caller's, not derived: what a copy is called is a
  /// product decision, and a screen can prefill a field with whatever it
  /// likes.
  ///
  /// The copy goes through [SaveRecipeRevision], so it is validated exactly
  /// as an edit is — a source whose dependencies have since been deleted
  /// fails here rather than producing an unusable copy.
  ///
  /// Throws [MissingDependencyError] when [sourceId] has no stored revision.
  Future<Recipe> call({
    required String sourceId,
    required String newId,
    required String name,
  }) async {
    final source = await _recipes.findLatest(sourceId);
    // Both arguments are `sourceId` on purpose. `MissingDependencyError`
    // renders "recipe X is not in the index" when they match and
    // "recipe X references missing recipe Y" when they differ, and nothing
    // references the source here — the operator asked for it directly.
    if (source == null) throw MissingDependencyError(sourceId, sourceId);

    return SaveRecipeRevision(_recipes).call(
      Recipe(
        id: newId,
        // Ignored by SaveRecipeRevision, which assigns the real number.
        revision: 1,
        name: name,
        baseYield: source.baseYield,
        components: source.components,
        modifiedAt: source.modifiedAt,
        category: source.category,
        maxBatchYield: source.maxBatchYield,
        preparationNotes: source.preparationNotes,
        // A copy is a live recipe even when its source was archived;
        // otherwise duplicating to revive a recipe produces another
        // archived one.
      ),
    );
  }
}
```

- [ ] **Step 3: Run the tests, export, run the gate, commit**

Add `export 'recipe_lifecycle.dart';` to the barrel.

Run: `flutter analyze && very_good test --coverage`

```bash
git add lib/application test/application
git commit -m "feat(application): archive and duplicate a recipe"
```

---

### Task 6: DeleteIngredient

**Files:**

- Create: `lib/application/delete_ingredient.dart`
- Modify: `lib/application/application.dart`
- Test: `test/application/delete_ingredient_test.dart`

**Interfaces:**

- Produces: `IngredientDeletion` with `bool get deleted` and `List<Recipe> get blockedBy`, and `DeleteIngredient(IngredientRepository, RecipeRepository)` with `Future<IngredientDeletion> call(String ingredientId, {bool force = false})`.

- [ ] **Step 1: Write the failing tests**

```dart
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

  test('an ingredient in use is not deleted, and its recipes come back',
      () async {
    final ingredients = FakeIngredientRepository()
      ..stored['flour'] = buildIngredient(id: 'flour');
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a'))
      ..seed(buildRecipe(id: 'b'));

    final outcome = await DeleteIngredient(ingredients, recipes).call('flour');

    expect(outcome.deleted, isFalse);
    expect(outcome.blockedBy.map((r) => r.id).toSet(), {'a', 'b'});
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
```

`buildRecipe`'s default component targets the ingredient `flour`, which is what makes the second and third tests find a user. Confirm that in `fakes.dart` rather than assuming it.

- [ ] **Step 2: Run to verify failure, then implement**

Create `lib/application/delete_ingredient.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// What [DeleteIngredient] did, and what stood in the way.
@immutable
final class IngredientDeletion {
  /// Creates an outcome.
  const IngredientDeletion({required this.deleted, required this.blockedBy});

  /// Whether the ingredient was removed.
  final bool deleted;

  /// The recipes whose latest revision names the ingredient directly.
  ///
  /// Populated whether or not the deletion went ahead, so a forced call can
  /// still tell the operator which recipes now carry a dangling reference.
  final List<Recipe> blockedBy;
}

/// Removes an ingredient, refusing while recipes still name it.
///
/// The repository deliberately refuses nothing — its own documentation says
/// so — which is why the rule lives here.
final class DeleteIngredient {
  /// Creates the use case over [_ingredients] and [_recipes].
  const DeleteIngredient(this._ingredients, this._recipes);

  final IngredientRepository _ingredients;
  final RecipeRepository _recipes;

  /// Deletes [ingredientId] when nothing uses it.
  ///
  /// When recipes do, nothing is removed and they are returned instead. A
  /// caller that wants to delete anyway calls again with [force], so the
  /// operator's confirmation is a second decision rather than a flag the
  /// first call already carried and the screen forgot to unset.
  Future<IngredientDeletion> call(
    String ingredientId, {
    bool force = false,
  }) async {
    final users = await _recipes.listLatestRevisionsUsingIngredient(
      ingredientId,
    );
    if (users.isNotEmpty && !force) {
      return IngredientDeletion(deleted: false, blockedBy: users);
    }
    await _ingredients.delete(ingredientId);
    return IngredientDeletion(deleted: true, blockedBy: users);
  }
}
```

- [ ] **Step 3: Run the tests, export, run the gate, commit**

Add `export 'delete_ingredient.dart';` to the barrel.

```bash
git add lib/application test/application
git commit -m "feat(application): refuse to delete an ingredient recipes still use"
```

---

### Task 7: StartProductionRun

**Files:**

- Create: `lib/application/start_production_run.dart`
- Modify: `lib/application/application.dart`
- Test: `test/application/start_production_run_test.dart`

**Interfaces:**

- Consumes: `resolveDependencyClosure` from Task 2.
- Produces: `RunIdSource` and `Clock` (both abstract interfaces with one method), and `StartProductionRun(RecipeRepository, RunIdSource, Clock)` with `Future<ProductionRun> call({required String recipeId, required Quantity targetYield})`.

That this use case does not store anything is proved by its constructor taking no `ProductionRunRepository`, not by a test. A test that built one, never passed it in, and asserted it was empty would pass whatever the implementation did.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';

import 'fakes.dart';

final class _FixedIds implements RunIdSource {
  @override
  String next() => 'run-1';
}

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 8, 12);
}

StartProductionRun _useCase(FakeRecipeRepository recipes) =>
    StartProductionRun(recipes, _FixedIds(), _FixedClock());

void main() {
  test('a run carries the injected id and timestamp', () async {
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));

    final run = await _useCase(recipes).call(
      recipeId: 'a',
      targetYield: Quantity.parse('1000', Unit.gram),
    );

    expect(run.id, 'run-1');
    expect(run.createdAt, DateTime.utc(2026, 9, 8, 12));
  });

  test('the run is calculated from the latest revision', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'Old'))
      ..seed(buildRecipe(id: 'a', revision: 2, name: 'New'));

    final run = await _useCase(recipes).call(
      recipeId: 'a',
      targetYield: Quantity.parse('1000', Unit.gram),
    );

    expect(run.recipe.revision, 2);
    expect(run.result.components, isNotEmpty);
  });

  test('the dependency snapshot holds every sub-recipe', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'syrup'))
      ..seed(
        buildRecipe(id: 'a', components: [buildSubRecipeComponent('syrup')]),
      );

    final run = await _useCase(recipes).call(
      recipeId: 'a',
      targetYield: Quantity.parse('1000', Unit.gram),
    );

    expect(run.dependencySnapshot.keys, contains('syrup'));
  });

  test('a recipe that is not stored throws', () async {
    final recipes = FakeRecipeRepository();

    await expectLater(
      _useCase(recipes).call(
        recipeId: 'gone',
        targetYield: Quantity.parse('1', Unit.gram),
      ),
      throwsA(isA<MissingDependencyError>()),
    );
  });

  test('a missing sub-recipe is the domain error, not a silent gap', () async {
    final recipes = FakeRecipeRepository()
      ..seed(
        buildRecipe(id: 'a', components: [buildSubRecipeComponent('nope')]),
      );

    await expectLater(
      _useCase(recipes).call(
        recipeId: 'a',
        targetYield: Quantity.parse('1000', Unit.gram),
      ),
      throwsA(isA<MissingDependencyError>()),
    );
  });

  test('a zero target yield is the domain error', () async {
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));

    await expectLater(
      _useCase(recipes).call(
        recipeId: 'a',
        targetYield: Quantity.parse('0', Unit.gram),
      ),
      throwsA(isA<InvalidTargetYieldError>()),
    );
  });
}
```

A zero quantity is constructible — `Quantity` rejects only a negative amount, and exposes `isZero` — so the last test really does reach `ProductionCalculator.calculate`, which is what raises `InvalidTargetYieldError`. Do not weaken it to `throwsA(isA<DomainError>())`; the point of the test is which error a screen will have to render.

- [ ] **Step 2: Run to verify failure, then implement**

Create `lib/application/start_production_run.dart`:

```dart
import 'package:prep_book/application/dependency_closure.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Supplies the identifier a new production run is stored under.
///
/// Injected rather than generated inline so a test can assert an exact
/// snapshot; the app binds it to a UUID source.
abstract interface class RunIdSource {
  /// A new, unused run identifier.
  String next();
}

/// Supplies the current instant, for the same reason as [RunIdSource].
abstract interface class Clock {
  /// The current instant.
  DateTime now();
}

/// Calculates a production run without storing it.
///
/// The design document requires the snapshot to be computed before
/// persistence; returning an unsaved value is how that is satisfied. The
/// caller reviews it, records acknowledgements and overrides, and then
/// passes it to `SaveProductionRun`.
final class StartProductionRun {
  /// Creates the use case.
  const StartProductionRun(this._recipes, this._ids, this._clock);

  final RecipeRepository _recipes;
  final RunIdSource _ids;
  final Clock _clock;

  /// Scales [recipeId] to [targetYield].
  ///
  /// Throws [MissingDependencyError] when the recipe or one of its
  /// sub-recipes is not stored, [RecipeCycleError] when the stored graph has
  /// a cycle, and the domain's own yield errors for a target the recipe
  /// cannot take. None is rewrapped: each already names what the operator
  /// has to be told.
  Future<ProductionRun> call({
    required String recipeId,
    required Quantity targetYield,
  }) async {
    final root = await _recipes.findLatest(recipeId);
    // Both arguments match on purpose: `MissingDependencyError` renders
    // "recipe X is not in the index" in that case, which is the wording the
    // domain chose for an absent root rather than a dangling reference. Its
    // own "reports a missing root as absent, not self-referencing" test
    // pins that message.
    if (root == null) throw MissingDependencyError(recipeId, recipeId);

    final closure = await resolveDependencyClosure(_recipes, root);
    final result = const ProductionCalculator().calculate(
      recipe: root,
      targetYield: targetYield,
      recipeIndex: closure,
    );

    return ProductionRun(
      id: _ids.next(),
      createdAt: _clock.now(),
      recipe: root,
      dependencySnapshot: closure,
      targetYield: targetYield,
      result: result,
    );
  }
}
```

- [ ] **Step 3: Run the tests, export, run the gate, commit**

Add `export 'start_production_run.dart';` to the barrel.

```bash
git add lib/application test/application
git commit -m "feat(application): calculate a production run before storing it"
```

---

### Task 8: Run edits and saving

**Files:**

- Create: `lib/application/production_run_edits.dart`
- Modify: `lib/application/application.dart`
- Test: `test/application/production_run_edits_test.dart`

**Interfaces:**

- Consumes: `StartProductionRun` from Task 7, to build the run under test.
- Produces: `AcknowledgeWarning`, `ApplyOverride` (both stateless, no repository), and `SaveProductionRun(ProductionRunRepository)` with `Future<void> call(ProductionRun run)`.

- [ ] **Step 1: Write the failing tests**

`buildRecipeWithManualComponent` from Task 1 gives a result carrying a blocking `ManualComponentWarning`, which is what makes the acknowledgement tests meaningful. The fixed id and clock fakes are written out again here rather than imported from Task 7's test file, matching this project's convention of self-contained fixtures per test file.

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';

import 'fakes.dart';

final class _FixedIds implements RunIdSource {
  @override
  String next() => 'run-1';
}

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 8, 12);
}

/// A calculated, unsaved run whose result carries one blocking warning.
Future<ProductionRun> _buildRun() async {
  final recipes = FakeRecipeRepository()
    ..seed(buildRecipeWithManualComponent(id: 'a'));
  return StartProductionRun(recipes, _FixedIds(), _FixedClock()).call(
    recipeId: 'a',
    targetYield: Quantity.parse('1000', Unit.gram),
  );
}

void main() {
  test('acknowledging the blocking warning makes the run finalizable',
      () async {
    final run = await _buildRun();
    expect(run.isFinalizable, isFalse);

    final blocking = run.result.warnings.firstWhere((w) => w.isBlocking);
    final acknowledged = const AcknowledgeWarning().call(run, blocking);

    expect(acknowledged.isFinalizable, isTrue);
  });

  test('an override is keyed by recipe and component together', () async {
    final run = await _buildRun();

    final overridden = const ApplyOverride().call(
      run,
      recipeId: run.recipeId,
      componentId: 'flour',
      value: Quantity.parse('600', Unit.gram),
    );

    expect(
      overridden.overrides[(run.recipeId, 'flour')],
      Quantity.parse('600', Unit.gram),
    );
    // The calculated result is never rewritten.
    expect(overridden.result, same(run.result));
  });

  test('saving stores the run with its acknowledgements', () async {
    final runs = FakeProductionRunRepository();
    final run = await _buildRun();
    final blocking = run.result.warnings.firstWhere((w) => w.isBlocking);
    final acknowledged = const AcknowledgeWarning().call(run, blocking);

    await SaveProductionRun(runs).call(acknowledged);

    expect((await runs.findById('run-1'))!.acknowledgedWarnings, isNotEmpty);
  });

  test('a run that is not finalizable is still saved', () async {
    final runs = FakeProductionRunRepository();
    final run = await _buildRun();
    expect(run.isFinalizable, isFalse);

    await SaveProductionRun(runs).call(run);

    expect(await runs.findById('run-1'), isNotNull);
  });
}
```

`Quantity` equality is structural — same amount, same unit, no conversion — so comparing to `Quantity.parse('600', Unit.gram)` directly is correct here, and would not be if the two sides were in different units.

- [ ] **Step 2: Run to verify failure, then implement**

Create `lib/application/production_run_edits.dart`:

```dart
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Records that the operator has seen a warning.
///
/// One domain call, kept as a use case so the presentation unit never
/// reaches past this layer into the domain to mutate a run, and so a later
/// rule about which warnings may be acknowledged has one place to live.
final class AcknowledgeWarning {
  /// Creates the use case.
  const AcknowledgeWarning();

  /// [run] with [warning] marked as seen.
  ProductionRun call(ProductionRun run, ProductionWarning warning) =>
      run.acknowledge(warning);
}

/// Records an operator-entered quantity for one component.
final class ApplyOverride {
  /// Creates the use case.
  const ApplyOverride();

  /// [run] with [value] recorded for [componentId] of [recipeId].
  ///
  /// The calculated result is never rewritten, so the original stays
  /// available for comparison.
  ProductionRun call(
    ProductionRun run, {
    required String recipeId,
    required String componentId,
    required Quantity value,
  }) => run.override(
    recipeId: recipeId,
    componentId: componentId,
    value: value,
  );
}

/// Commits a calculated run and the state it carries.
final class SaveProductionRun {
  /// Creates the use case over [_runs].
  const SaveProductionRun(this._runs);

  final ProductionRunRepository _runs;

  /// Writes [run], its acknowledgements, and its overrides in one
  /// transaction, which [ProductionRunRepository.save] already provides.
  ///
  /// `recordAcknowledgement` and `recordOverride` are not called here. Those
  /// exist for state recorded against a run that is already stored; calling
  /// them for a first save would write the same rows twice.
  ///
  /// A run that is not `isFinalizable` is saved all the same. Acknowledgement
  /// is a precondition of finalizing a run, not of storing one, and a screen
  /// that saves a draft is not finalizing it.
  Future<void> call(ProductionRun run) => _runs.save(run);
}
```

- [ ] **Step 3: Run the tests, export, run the gate, commit**

Add `export 'production_run_edits.dart';` to the barrel.

```bash
git add lib/application test/application
git commit -m "feat(application): acknowledge, override, and commit a run"
```

---

### Task 9: History

**Files:**

- Create: `lib/application/production_history.dart`
- Modify: `lib/application/application.dart`
- Test: `test/application/production_history_test.dart`

**Interfaces:**

- Produces: `ListProductionHistory(ProductionRunRepository)` with `Future<List<ProductionRunSummary>> call()`, and `OpenProductionRun(ProductionRunRepository)` with `Future<ProductionRun?> call(String runId)`.

- [ ] **Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';

import 'fakes.dart';

final class _Ids implements RunIdSource {
  _Ids(this._values);
  final List<String> _values;
  var _index = 0;

  @override
  String next() => _values[_index++];
}

final class _Clock implements Clock {
  _Clock(this._values);
  final List<DateTime> _values;
  var _index = 0;

  @override
  DateTime now() => _values[_index++];
}

void main() {
  test('history comes back newest first', () async {
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));
    final runs = FakeProductionRunRepository();
    final start = StartProductionRun(
      recipes,
      _Ids(['older', 'newer']),
      _Clock([
        DateTime.utc(2026, 9, 8, 10),
        DateTime.utc(2026, 9, 8, 11),
      ]),
    );
    final target = Quantity.parse('1000', Unit.gram);
    await SaveProductionRun(
      runs,
    ).call(await start.call(recipeId: 'a', targetYield: target));
    await SaveProductionRun(
      runs,
    ).call(await start.call(recipeId: 'a', targetYield: target));

    final summaries = await ListProductionHistory(runs).call();

    expect(summaries.map((s) => s.id), ['newer', 'older']);
  });

  test('opening a stored run returns what was stored', () async {
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));
    final runs = FakeProductionRunRepository();
    final run = await StartProductionRun(
      recipes,
      _Ids(['run-1']),
      _Clock([DateTime.utc(2026, 9, 8, 10)]),
    ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));
    await SaveProductionRun(runs).call(run);

    final opened = await OpenProductionRun(runs).call('run-1');

    expect(opened!.id, 'run-1');
  });

  test('opening a run that is gone returns null', () async {
    expect(
      await OpenProductionRun(FakeProductionRunRepository()).call('nope'),
      isNull,
    );
  });

  test('a stored run keeps the revision it was computed from', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'Original'));
    final runs = FakeProductionRunRepository();
    final run = await StartProductionRun(
      recipes,
      _Ids(['run-1']),
      _Clock([DateTime.utc(2026, 9, 8, 10)]),
    ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));
    await SaveProductionRun(runs).call(run);

    await SaveRecipeRevision(recipes).call(buildRecipe(id: 'a', name: 'Edited'));

    final reopened = await OpenProductionRun(runs).call('run-1');

    expect(reopened!.recipe.revision, 1);
    expect(reopened.recipe.name, 'Original');
    expect((await recipes.findLatest('a'))!.name, 'Edited');
  });
}
```

The last test is the design document's own invariant — a stored run is never recalculated against the current recipe — and is the reason this task exists as more than two delegating methods.

- [ ] **Step 2: Run to verify failure, then implement**

Create `lib/application/production_history.dart`:

```dart
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Every stored run, newest first.
final class ListProductionHistory {
  /// Creates the use case over [_runs].
  const ListProductionHistory(this._runs);

  final ProductionRunRepository _runs;

  /// Reads the history. The repository already orders it.
  Future<List<ProductionRunSummary>> call() => _runs.listSummaries();
}

/// Reopens one stored run.
final class OpenProductionRun {
  /// Creates the use case over [_runs].
  const OpenProductionRun(this._runs);

  final ProductionRunRepository _runs;

  /// The run stored under [runId], or null when it is gone.
  ///
  /// Never recalculated against the current recipe: the snapshot is what
  /// was stored, and editing or archiving the source recipe afterwards does
  /// not reach it.
  Future<ProductionRun?> call(String runId) => _runs.findById(runId);
}
```

- [ ] **Step 3: Run the tests, export, run the gate, commit**

Add `export 'production_history.dart';` to the barrel.

Run: `flutter analyze && very_good test --coverage` and confirm coverage is at 100 percent for the whole project, not only the new files.

```bash
git add lib/application test/application
git commit -m "feat(application): list and reopen production history"
```

---

## Definition of done

- Every use case in `docs/specs/2026-09-08-application-layer.md` exists and is exported from `lib/application/application.dart`.
- `test/application/application_boundary_test.dart` passes, and its failure was observed once in Task 1.
- `flutter analyze` clean, `very_good test --coverage` at 100 percent.
- `trunk fmt` and `trunk check` clean on every touched path.
- `lib/counter/` is untouched.
