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

    final run = await _useCase(
      recipes,
    ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));

    expect(run.id, 'run-1');
    expect(run.createdAt, DateTime.utc(2026, 9, 8, 12));
    // The use case holds a `RecipeRepository`, which can write
    // (`saveRevision`, `setArchived`) as well as read. Only a read call is
    // legitimate here — asserting that rules out a side effect on the
    // recipe itself, distinct from the "no run is stored" guarantee the
    // constructor's shape already proves on its own.
    expect(recipes.calls, everyElement(startsWith('findLatest')));
  });

  test('the run is calculated from the latest revision', () async {
    // Revision 2 carries a structurally different component (sugar, not
    // flour) so a calculation run against the stale revision 1 would
    // produce a visibly different result, not merely a different `name` or
    // `revision` field on an otherwise-identical recipe. Only checking
    // `run.recipe.revision` would pass an implementation that stores the
    // latest revision on the run but still calculates from whichever
    // revision it happened to fetch first.
    //
    // The target yield (2000 g) is also chosen to differ from every
    // recipe's 1000 g base yield, giving a scale ratio of 2 instead of 1 —
    // otherwise an implementation that calculated against `root.baseYield`
    // instead of the caller's `targetYield`, or that stored the wrong one
    // of the two on the returned run, would be indistinguishable from a
    // correct one.
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'Old'))
      ..seed(
        buildRecipe(
          id: 'a',
          revision: 2,
          name: 'New',
          components: [
            RecipeComponent(
              id: 'sugar',
              target: const IngredientRef('sugar'),
              baseQuantity: Quantity.parse('300', Unit.gram),
              behavior: ScalingBehavior.proportional,
              displayOrder: 0,
            ),
          ],
        ),
      );
    final targetYield = Quantity.parse('2000', Unit.gram);

    final run = await _useCase(
      recipes,
    ).call(recipeId: 'a', targetYield: targetYield);

    expect(run.recipe.revision, 2);
    expect(run.targetYield, targetYield);
    expect(run.result.components, hasLength(1));
    final sugar = run.result.components.single;
    expect(sugar.source.id, 'sugar');
    expect(sugar.total!.displayed, Quantity.parse('600', Unit.gram));
  });

  test(
    'the dependency snapshot holds every sub-recipe, but not the root',
    () async {
      final recipes = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'syrup'))
        ..seed(
          buildRecipe(id: 'a', components: [buildSubRecipeComponent('syrup')]),
        );

      final run = await _useCase(
        recipes,
      ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));

      // `dependencySnapshot` names the sub-recipe...
      expect(run.dependencySnapshot.keys, contains('syrup'));
      // ...and never the root itself: `ProductionRun.recipe` already holds
      // it, and duplicating it into the snapshot would serialize it twice
      // for no reader.
      expect(run.dependencySnapshot.keys, isNot(contains('a')));
      // The call succeeding at all is most of what proves `recipeIndex`
      // was complete: `ProductionCalculator.calculate` runs
      // `assertResolvable` over `recipeIndex` before scaling anything, so a
      // `recipeIndex` missing `syrup` would already throw
      // `MissingDependencyError` here rather than let this assertion run.
      // This checks the remaining case: the sub-recipe component actually
      // expanded into a nested result, not left null by a branch that
      // treats a resolvable-but-absent entry as "nothing to expand".
      expect(run.result.components.single.subRecipe, isNotNull);
    },
  );

  test('a recipe that is not stored throws', () async {
    final recipes = FakeRecipeRepository();

    await expectLater(
      _useCase(
        recipes,
      ).call(recipeId: 'gone', targetYield: Quantity.parse('1', Unit.gram)),
      throwsA(
        isA<MissingDependencyError>().having(
          (e) => e.message,
          'message',
          'recipe gone is not in the index',
        ),
      ),
    );
    expect(
      recipes.calls.where((call) => call.startsWith('saveRevision:')),
      isEmpty,
    );
  });

  test('a missing sub-recipe is the domain error, not a silent gap', () async {
    final recipes = FakeRecipeRepository()
      ..seed(
        buildRecipe(id: 'a', components: [buildSubRecipeComponent('nope')]),
      );

    await expectLater(
      _useCase(
        recipes,
      ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram)),
      throwsA(
        isA<MissingDependencyError>().having(
          (e) => e.message,
          'message',
          'recipe a references missing recipe nope',
        ),
      ),
    );
    expect(
      recipes.calls.where((call) => call.startsWith('saveRevision:')),
      isEmpty,
    );
  });

  test('a zero target yield is the domain error', () async {
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));

    await expectLater(
      _useCase(
        recipes,
      ).call(recipeId: 'a', targetYield: Quantity.parse('0', Unit.gram)),
      throwsA(isA<InvalidTargetYieldError>()),
    );
    expect(
      recipes.calls.where((call) => call.startsWith('saveRevision:')),
      isEmpty,
    );
  });
}
