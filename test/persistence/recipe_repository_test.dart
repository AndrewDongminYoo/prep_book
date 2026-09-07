import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/recipe_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Builds a valid `Recipe` through the domain's real factory, so its own
/// validation runs on every fixture this file constructs.
///
/// Each id in [componentIds] becomes a component targeting the ingredient of
/// the same name; each id in [subRecipeIds] becomes one targeting the
/// *recipe* of that name, under a `sub-` prefixed component id so the two
/// lists can name the same target without colliding on the component id
/// `Recipe`'s factory requires to be unique.
Recipe buildRecipe({
  required String id,
  required int revision,
  String name = 'Test recipe',
  List<String> componentIds = const [],
  List<String> subRecipeIds = const [],
  DateTime? modifiedAt,
}) => Recipe(
  id: id,
  revision: revision,
  name: name,
  baseYield: Quantity.parse('1000', Unit.gram),
  modifiedAt: modifiedAt ?? DateTime.utc(2026, 9, 7),
  components: [
    for (var i = 0; i < componentIds.length; i++)
      RecipeComponent(
        id: componentIds[i],
        target: IngredientRef(componentIds[i]),
        baseQuantity: Quantity.parse('100', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: i,
      ),
    for (var i = 0; i < subRecipeIds.length; i++)
      RecipeComponent(
        id: 'sub-${subRecipeIds[i]}',
        target: SubRecipeRef(subRecipeIds[i]),
        baseQuantity: Quantity.parse('100', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: componentIds.length + i,
      ),
  ],
);

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late SqfliteRecipeRepository repository;

  setUp(() async {
    db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repository = SqfliteRecipeRepository(db);
  });

  tearDown(() => db.close());

  test('saving an edit creates a new revision and keeps the old one', () async {
    final first = buildRecipe(id: 'sourdough', revision: 1, name: 'Sourdough');
    final second = buildRecipe(
      id: 'sourdough',
      revision: 2,
      name: 'Sourdough v2',
    );
    await repository.saveRevision(first);
    await repository.saveRevision(second);

    expect((await repository.findRevision('sourdough', 1))!.name, 'Sourdough');
    expect((await repository.findLatest('sourdough'))!.revision, 2);
    expect(await repository.listLatestRevisions(), hasLength(1));
  });

  test('components belong to their revision', () async {
    final one = buildRecipe(id: 'r', revision: 1, componentIds: ['flour']);
    final two = buildRecipe(
      id: 'r',
      revision: 2,
      componentIds: ['flour', 'salt'],
    );
    await repository.saveRevision(one);
    await repository.saveRevision(two);

    expect((await repository.findRevision('r', 1))!.components, hasLength(1));
    expect((await repository.findRevision('r', 2))!.components, hasLength(2));
  });

  // The brief's own suggested test — a Recipe built with two components
  // sharing the id 'a' — cannot reach `saveRevision` at all: `Recipe`'s
  // factory rejects a repeated component id synchronously while
  // `buildRecipe` is still constructing the fixture (see
  // `lib/domain/recipe/recipe.dart`), so persistence never sees it. This
  // plants a `recipe_components` row occupying the primary key
  // `('r', 1, 'a')` before the recipe row exists — which itself requires
  // disabling foreign-key enforcement for the plant, because a row with no
  // matching `recipes` parent is otherwise rejected on insert. With the
  // parent absent, `saveRevision`'s own `recipes` insert succeeds first;
  // its `recipe_components` insert for component 'a' then collides with the
  // planted row and throws, and the transaction must undo the recipe insert
  // that already ran.
  test('a failed component insert rolls back the recipe row', () async {
    await db.execute('PRAGMA foreign_keys = OFF');
    await db.insert('recipe_components', <String, Object?>{
      'recipe_id': 'r',
      'recipe_revision': 1,
      'component_id': 'a',
      'target_kind': 'ingredient',
      'target_id': 'flour',
      'behavior': 'manual',
      'display_order': 0,
    });
    await db.execute('PRAGMA foreign_keys = ON');

    final broken = buildRecipe(id: 'r', revision: 1, componentIds: ['a']);

    await expectLater(repository.saveRevision(broken), throwsA(anything));
    expect(await repository.findRevision('r', 1), isNull);
  });

  // `RecipeRepository.saveRevision` documents that it "never updates an
  // existing" revision. `recipes`' primary key is `(id, revision)` and the
  // insert carries no conflict algorithm, so writing the same pair twice
  // must throw rather than silently overwrite — the guarantee a stored
  // production run relies on.
  test('saving the same id and revision twice throws', () async {
    final first = buildRecipe(id: 'r', revision: 1, name: 'Original');
    final resaved = buildRecipe(id: 'r', revision: 1, name: 'Overwritten');

    await repository.saveRevision(first);
    await expectLater(repository.saveRevision(resaved), throwsA(anything));

    expect((await repository.findRevision('r', 1))!.name, 'Original');
  });

  test('a missing revision reads as null', () async {
    await repository.saveRevision(buildRecipe(id: 'r', revision: 1));

    expect(await repository.findRevision('r', 2), isNull);
    expect(await repository.findRevision('absent', 1), isNull);
  });

  test('a missing recipe has no latest revision', () async {
    expect(await repository.findLatest('absent'), isNull);
  });

  test('listing latest revisions with no recipes stored is empty', () async {
    expect(await repository.listLatestRevisions(), isEmpty);
  });

  test('listLatestRevisions groups by id across many recipes', () async {
    await repository.saveRevision(buildRecipe(id: 'x', revision: 1));
    await repository.saveRevision(buildRecipe(id: 'x', revision: 2));
    await repository.saveRevision(buildRecipe(id: 'x', revision: 3));
    await repository.saveRevision(buildRecipe(id: 'y', revision: 1));

    final latest = await repository.listLatestRevisions();
    expect(latest, hasLength(2));
    expect(latest.map((r) => r.revision), containsAll([1, 3]));
  });

  test(
    'setArchived flips every revision of the id, and listLatestRevisions '
    'still includes it',
    () async {
      await repository.saveRevision(buildRecipe(id: 'r', revision: 1));
      await repository.saveRevision(buildRecipe(id: 'r', revision: 2));

      await repository.setArchived('r', isArchived: true);

      expect((await repository.findRevision('r', 1))!.isArchived, isTrue);
      expect((await repository.findRevision('r', 2))!.isArchived, isTrue);
      expect(await repository.listLatestRevisions(), hasLength(1));

      await repository.setArchived('r', isArchived: false);
      expect((await repository.findRevision('r', 1))!.isArchived, isFalse);
    },
  );

  // `Recipe` and `RecipeComponent` have no `operator ==` (Task 3 found the
  // same for `Ingredient`), so the round trip is checked field by field.
  // `Unit.namedYield('tray')` is deliberately not one of the eight fixed
  // units `unitToStorage` special-cases: writing `unit.symbol` directly
  // would store the bare string `tray`, which `unitFromStorage` rejects as
  // corrupt rather than a unit `Unit.portion` (a fixed unit whose symbol is
  // also its storage form) could not have caught. `Unit.count('egg')` on
  // the component covers the same trap for a component's own quantity.
  test(
    'a recipe with a named-yield base and max yield and a count-unit '
    'component round-trips',
    () async {
      final recipe = Recipe(
        id: 'batch-recipe',
        revision: 1,
        name: 'Batch recipe',
        category: 'Bread',
        baseYield: Quantity.parse('10', Unit.namedYield('tray')),
        maxBatchYield: Quantity.parse('5', Unit.namedYield('tray')),
        preparationNotes: const ['Mix', 'Bake'],
        modifiedAt: DateTime.utc(2026, 9, 7, 12),
        components: [
          RecipeComponent(
            id: 'eggs',
            target: const IngredientRef('egg'),
            baseQuantity: Quantity.parse('4', Unit.count('egg')),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
            rounding: RoundingRule.upToIncrement(Decimal.one),
            note: 'room temperature',
          ),
          RecipeComponent(
            id: 'starter',
            target: const SubRecipeRef('sourdough-starter'),
            baseQuantity: null,
            behavior: ScalingBehavior.manual,
            displayOrder: 1,
          ),
        ],
      );

      await repository.saveRevision(recipe);
      final found = await repository.findRevision('batch-recipe', 1);

      expect(found?.id, recipe.id);
      expect(found?.name, recipe.name);
      expect(found?.category, recipe.category);
      expect(found?.baseYield, recipe.baseYield);
      expect(found?.maxBatchYield, recipe.maxBatchYield);
      expect(found?.preparationNotes, recipe.preparationNotes);
      expect(found?.modifiedAt, recipe.modifiedAt);
      expect(found?.isArchived, recipe.isArchived);
      expect(found?.components, hasLength(2));

      final eggs = found!.components.firstWhere((c) => c.id == 'eggs');
      expect(eggs.target, const IngredientRef('egg'));
      expect(eggs.baseQuantity, Quantity.parse('4', Unit.count('egg')));
      expect(eggs.behavior, ScalingBehavior.proportional);
      expect(eggs.rounding?.increment, Decimal.one);
      expect(eggs.note, 'room temperature');
      expect(eggs.displayOrder, 0);

      final starter = found.components.firstWhere((c) => c.id == 'starter');
      expect(starter.target, const SubRecipeRef('sourdough-starter'));
      expect(starter.baseQuantity, isNull);
      expect(starter.behavior, ScalingBehavior.manual);
      expect(starter.rounding, isNull);
      expect(starter.note, isNull);
    },
  );

  // Every other fixture in this suite builds its `modifiedAt` with
  // `DateTime.utc`, so the suite exercised only the form that already
  // serializes with a `Z`. The application will hand this layer
  // `DateTime.now()`, which is local and serializes without one — and a
  // stored timestamp that sometimes carries the suffix and sometimes does
  // not cannot be compared as text, which is how `production_runs` orders
  // its history. Normalizing on write is the only moment an offset is
  // still known; a naive value already in the file cannot be assigned one
  // afterwards.
  test('a local modifiedAt is stored normalized to UTC', () async {
    final local = DateTime(2026, 9, 7, 21, 30);
    expect(local.isUtc, isFalse);

    await repository.saveRevision(
      buildRecipe(id: 'r', revision: 1, modifiedAt: local),
    );

    final stored =
        (await db.query(
              'recipes',
              columns: ['modified_at'],
            )).single['modified_at']!
            as String;
    expect(stored, endsWith('Z'));

    final found = await repository.findRevision('r', 1);
    expect(found!.modifiedAt.isUtc, isTrue);
    expect(found.modifiedAt.isAtSameMomentAs(local), isTrue);
  });

  // --- the in-use query that precedes an ingredient deletion --------------
  //
  // `listLatestRevisionsUsingIngredient` exists so the application layer can
  // warn before calling `IngredientRepository.delete`, naming the recipes
  // that would be left referencing a row that is about to disappear. It
  // never blocks the deletion, so nothing here asserts a refusal.

  test('an ingredient no recipe uses reports no recipes', () async {
    await repository.saveRevision(
      buildRecipe(id: 'r', revision: 1, componentIds: ['rye']),
    );

    expect(
      await repository.listLatestRevisionsUsingIngredient('flour'),
      isEmpty,
    );
  });

  // `recipe_components.target_id` carries no foreign key and holds both
  // ingredient ids and recipe ids, so the query has to filter on
  // `target_kind` as well. This plants exactly that collision: a recipe whose
  // sub-recipe reference names `flour`, the same string as the ingredient
  // under test. Both fixtures go through `saveRevision` rather than a
  // hand-written row, so the planted `target_kind` is the value the writer
  // actually produces.
  test(
    'a sub-recipe whose id collides with the ingredient is not a use',
    () async {
      await repository.saveRevision(
        buildRecipe(id: 'real-user', revision: 1, componentIds: ['flour']),
      );
      await repository.saveRevision(
        buildRecipe(id: 'impostor', revision: 1, subRecipeIds: ['flour']),
      );

      final using = await repository.listLatestRevisionsUsingIngredient(
        'flour',
      );
      expect(using.map((r) => r.id), ['real-user']);
      // A whole `Recipe`, components included — the same shape
      // `listLatestRevisions` returns, so a caller can name the component.
      expect(using.single.components, hasLength(1));
    },
  );

  // "Used in 3 recipes" counting three revisions of one recipe answers a
  // question nobody asked, so only the latest revision of each recipe is
  // examined. This is the direction where an older revision still holds the
  // reference the current one dropped.
  test(
    'a recipe whose latest revision dropped the ingredient is not a use',
    () async {
      await repository.saveRevision(
        buildRecipe(id: 'r', revision: 1, componentIds: ['flour']),
      );
      await repository.saveRevision(
        buildRecipe(id: 'r', revision: 2, componentIds: ['rye']),
      );

      expect(
        await repository.listLatestRevisionsUsingIngredient('flour'),
        isEmpty,
      );
    },
  );

  // The reverse: the ingredient was added in the current revision, so the
  // recipe is a use even though its first revision never mentioned it. A
  // query that scanned every revision would answer this one correctly by
  // accident, which is why the test above exists beside it.
  test(
    'a recipe whose latest revision added the ingredient is a use',
    () async {
      await repository.saveRevision(
        buildRecipe(id: 'r', revision: 1, componentIds: ['rye']),
      );
      await repository.saveRevision(
        buildRecipe(id: 'r', revision: 2, componentIds: ['rye', 'flour']),
      );

      final using = await repository.listLatestRevisionsUsingIngredient(
        'flour',
      );
      expect(using.map((r) => r.id), ['r']);
      expect(using.single.revision, 2);
    },
  );

  // The ruling this pins: an archived recipe is still a use. It can be
  // restored, and deleting the ingredient now would leave the dangling
  // reference to surface then. A later `AND is_archived = 0` in the query
  // fails here rather than passing a coverage gate.
  test('an archived recipe still counts as a use', () async {
    await repository.saveRevision(
      buildRecipe(id: 'r', revision: 1, componentIds: ['flour']),
    );
    await repository.setArchived('r', isArchived: true);

    final using = await repository.listLatestRevisionsUsingIngredient('flour');
    expect(using.single.id, 'r');
    expect(using.single.isArchived, isTrue);
  });

  // One recipe is one answer however many of its components name the
  // ingredient. `EXISTS` gives that; a join to `recipe_components` would
  // return the recipe once per matching component.
  test('a recipe using the ingredient twice is reported once', () async {
    await repository.saveRevision(
      Recipe(
        id: 'r',
        revision: 1,
        name: 'Twice',
        baseYield: Quantity.parse('1000', Unit.gram),
        modifiedAt: DateTime.utc(2026, 9, 7),
        components: [
          RecipeComponent(
            id: 'flour-a',
            target: const IngredientRef('flour'),
            baseQuantity: Quantity.parse('100', Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
          RecipeComponent(
            id: 'flour-b',
            target: const IngredientRef('flour'),
            baseQuantity: Quantity.parse('200', Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 1,
          ),
        ],
      ),
    );

    expect(
      await repository.listLatestRevisionsUsingIngredient('flour'),
      hasLength(1),
    );
  });

  test('an unrecognised component target kind is a corrupt row', () async {
    await repository.saveRevision(
      buildRecipe(id: 'corrupt-target', revision: 1),
    );
    await db.insert('recipe_components', <String, Object?>{
      'recipe_id': 'corrupt-target',
      'recipe_revision': 1,
      'component_id': 'x',
      'target_kind': 'bogus',
      'target_id': 'whatever',
      'behavior': 'manual',
      'display_order': 0,
    });

    await expectLater(
      repository.findRevision('corrupt-target', 1),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

  test('an unrecognised component behavior is a corrupt row', () async {
    await repository.saveRevision(
      buildRecipe(id: 'corrupt-behavior', revision: 1),
    );
    await db.insert('recipe_components', <String, Object?>{
      'recipe_id': 'corrupt-behavior',
      'recipe_revision': 1,
      'component_id': 'x',
      'target_kind': 'ingredient',
      'target_id': 'flour',
      'behavior': 'bogus',
      'display_order': 0,
    });

    await expectLater(
      repository.findRevision('corrupt-behavior', 1),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });
}
