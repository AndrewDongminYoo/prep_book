import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

import 'fakes.dart';

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 8, 12);
}

/// A library where another writer stores [occupant] the moment its id is
/// first read as free, reading and writing through [reads] otherwise.
///
/// That is the window between [CreateRecipe]'s occupancy check and its
/// insert, which [FakeRecipeRepository] answers too quickly to open.
final class _OccupiedAfterCheck implements RecipeRepository {
  new(this.reads, this.occupant);

  final FakeRecipeRepository reads;
  final Recipe occupant;

  @override
  Future<Recipe?> findLatest(String id) async {
    final latest = await reads.findLatest(id);
    if (id == occupant.id && latest == null) reads.seed(occupant);
    return latest;
  }

  @override
  Future<void> saveRevision(Recipe recipe) => reads.saveRevision(recipe);

  @override
  Future<List<Recipe>> listLatestRevisions() => throw UnsupportedError('a save never lists the library');

  @override
  Future<Recipe?> findRevision(String id, int revision) => throw UnsupportedError('a save never reads one revision');

  @override
  Future<void> setArchived(String id, {required bool isArchived}) => throw UnsupportedError('a save never archives');

  @override
  Future<List<Recipe>> listLatestRevisionsUsingIngredient(
    String ingredientId,
  ) => throw UnsupportedError('a save never reads by ingredient');
}

void main() {
  test('a first save becomes revision 1', () async {
    final recipes = FakeRecipeRepository();
    final saved = await SaveRecipeRevision(
      recipes,
      _FixedClock(),
    ).call(buildRecipe(id: 'a'));

    expect(saved.revision, 1);
    expect((await recipes.findLatest('a'))!.revision, 1);
  });

  test(
    'an edit becomes the next revision and leaves the old one readable',
    () async {
      final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a', name: 'Old'));

      final saved = await SaveRecipeRevision(
        recipes,
        _FixedClock(),
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
      _FixedClock(),
    ).call(buildRecipe(id: 'a', revision: 99));

    expect(saved.revision, 2);
  });

  test('category, maxBatchYield, preparationNotes, and isArchived survive onto '
      'the new revision', () async {
    final recipes = FakeRecipeRepository();
    final edited = Recipe(
      id: 'a',
      revision: 1,
      name: 'Test recipe',
      baseYield: Quantity.parse('1000', Unit.gram),
      modifiedAt: DateTime.utc(2026, 9, 8),
      category: 'Pastry',
      maxBatchYield: Quantity.parse('5000', Unit.gram),
      preparationNotes: const ['Preheat oven', 'Rest dough'],
      isArchived: true,
      components: [
        RecipeComponent(
          id: 'flour',
          target: const IngredientRef('flour'),
          baseQuantity: Quantity.parse('500', Unit.gram),
          behavior: ScalingBehavior.proportional,
          displayOrder: 0,
        ),
      ],
    );

    final saved = await SaveRecipeRevision(recipes, _FixedClock()).call(edited);

    expect(saved.category, 'Pastry');
    expect(saved.maxBatchYield, edited.maxBatchYield);
    expect(saved.preparationNotes, ['Preheat oven', 'Rest dough']);
    expect(saved.isArchived, isTrue);
  });

  test(
    'the saved revision is stamped from the clock, not the caller',
    () async {
      final recipes = FakeRecipeRepository();
      final clock = _FixedClock();
      final edited = Recipe(
        id: 'a',
        revision: 1,
        name: 'Test recipe',
        baseYield: Quantity.parse('1000', Unit.gram),
        // Deliberately far from what the clock returns, so a passing test
        // could only mean the clock's instant was used.
        modifiedAt: DateTime.utc(2020),
        components: [
          RecipeComponent(
            id: 'flour',
            target: const IngredientRef('flour'),
            baseQuantity: Quantity.parse('500', Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
      );

      final saved = await SaveRecipeRevision(recipes, clock).call(edited);

      expect(saved.modifiedAt, clock.now());
      expect(saved.modifiedAt, isNot(edited.modifiedAt));
    },
  );

  test('a missing sub-recipe is rejected and nothing is written', () async {
    final recipes = FakeRecipeRepository();
    final edited = buildRecipe(
      id: 'a',
      components: [buildSubRecipeComponent('nope')],
    );

    await expectLater(
      SaveRecipeRevision(recipes, _FixedClock()).call(edited),
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
        SaveRecipeRevision(recipes, _FixedClock()).call(edited),
        throwsA(
          isA<RecipeCycleError>().having((e) => e.path, 'path', [
            'cake',
            'syrup',
            'cake',
          ]),
        ),
      );
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
    },
  );

  group('CreateRecipe', () {
    test('stores revision 1, stamped from the clock, whatever it was given', () async {
      final recipes = FakeRecipeRepository();
      final clock = _FixedClock();

      final created = await CreateRecipe(
        recipes,
        clock,
      ).call(buildRecipe(id: 'a', revision: 7, modifiedAt: DateTime.utc(2020)));

      expect(created.revision, 1);
      expect(created.modifiedAt, clock.now());
      expect((await recipes.findLatest('a'))!.revision, 1);
    });

    test('an occupied id is refused and the occupant is untouched', () async {
      final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a', name: 'Occupant'));

      await expectLater(
        CreateRecipe(
          recipes,
          _FixedClock(),
        ).call(buildRecipe(id: 'a', name: 'New')),
        throwsA(
          isA<RecipeIdOccupiedError>().having(
            (e) => e.recipeId,
            'recipeId',
            'a',
          ),
        ),
      );
      // `SaveRecipeRevision` would have stored this as revision 2 of `a`,
      // replacing the occupant in the library under its own id.
      expect((await recipes.findLatest('a'))!.name, 'Occupant');
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
    });

    test(
      'an occupant stored after the check is kept, not revised over',
      () async {
        final reads = FakeRecipeRepository();
        final recipes = _OccupiedAfterCheck(
          reads,
          buildRecipe(id: 'a', name: 'Occupant'),
        );

        // Refused by the fake the way the real repository refuses a second
        // insert of one `(id, revision)` pair; which error that is belongs
        // to the repository, not to this use case.
        await expectLater(
          CreateRecipe(
            recipes,
            _FixedClock(),
          ).call(buildRecipe(id: 'a', name: 'New')),
          throwsA(isA<StateError>()),
        );
        // A create that re-read the latest revision before its insert would
        // find the occupant here and store revision 2 over it.
        expect(await reads.findRevision('a', 2), isNull);
        expect((await reads.findLatest('a'))!.name, 'Occupant');
      },
    );

    test('a missing sub-recipe is rejected and nothing is written', () async {
      final recipes = FakeRecipeRepository();

      await expectLater(
        CreateRecipe(recipes, _FixedClock()).call(
          buildRecipe(id: 'a', components: [buildSubRecipeComponent('nope')]),
        ),
        throwsA(isA<MissingDependencyError>()),
      );
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
    });
  });
}
