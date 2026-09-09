import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/repositories.dart';

import 'fakes.dart';

final class _FixedIds implements RunIdSource {
  @override
  String next() => 'run-1';
}

/// A [Random] that hands out [_draws] in order, cycling when it runs out.
///
/// Only [nextInt] is implemented: an identifier has to be built out of whole
/// draws, and a source reaching for [nextDouble] would be spelling one out of
/// a float's mantissa instead. The throwing members are what says so.
final class _ScriptedRandom implements Random {
  _ScriptedRandom(this._draws);

  final List<int> _draws;

  /// Every bound [nextInt] was called with, so a test can assert each draw
  /// is 32 bits wide rather than some narrower number that happens to
  /// render the same for the small values a script hands out.
  final List<int> bounds = [];

  int _index = 0;

  @override
  int nextInt(int max) {
    bounds.add(max);
    return _draws[_index++ % _draws.length];
  }

  @override
  bool nextBool() => throw UnsupportedError('a run id is drawn as integers');

  @override
  double nextDouble() =>
      throw UnsupportedError('a run id is drawn as integers');
}

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 8, 12);
}

/// An ingredient library whose reads fail the way a damaged row does.
///
/// `SqfliteIngredientRepository.findById` raises [CorruptDatabaseError] for
/// a row whose stored unit symbol is unknown, or whose column holds the
/// wrong type. Only `findById` is implemented, because the use case calls
/// nothing else — the throwing members are what says so.
final class _CorruptIngredientRepository implements IngredientRepository {
  @override
  Future<Ingredient?> findById(String id) async =>
      throw CorruptDatabaseError('unknown unit symbol in ingredient $id: qq');

  @override
  Future<List<Ingredient>> listAll() =>
      throw UnsupportedError('a run reads one ingredient at a time');

  @override
  Future<void> upsert(Ingredient ingredient) =>
      throw UnsupportedError('a run never writes to the library');

  @override
  Future<void> delete(String id) =>
      throw UnsupportedError('a run never writes to the library');
}

StartProductionRun _useCase(
  FakeRecipeRepository recipes, [
  IngredientRepository? ingredients,
]) => StartProductionRun(
  recipes,
  ingredients ?? FakeIngredientRepository(),
  _FixedIds(),
  _FixedClock(),
);

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

  test(
    'the ingredient snapshot holds every referenced ingredient, root included',
    () async {
      // The root's own ingredient is the one `dependencySnapshot` cannot
      // speak for — the root is exactly the recipe it drops — so a use case
      // that gathered ingredients from the dependency map instead of the
      // whole closure would snapshot `syrup-sugar` and miss `bread-flour`.
      final recipes = FakeRecipeRepository()
        ..seed(
          buildRecipe(
            id: 'syrup',
            components: [
              RecipeComponent(
                id: 'sugar-line',
                target: const IngredientRef('syrup-sugar'),
                baseQuantity: Quantity.parse('100', Unit.gram),
                behavior: ScalingBehavior.proportional,
                displayOrder: 0,
              ),
            ],
          ),
        )
        ..seed(
          buildRecipe(
            id: 'a',
            components: [
              RecipeComponent(
                id: 'flour-line',
                target: const IngredientRef('bread-flour'),
                baseQuantity: Quantity.parse('500', Unit.gram),
                behavior: ScalingBehavior.proportional,
                displayOrder: 0,
              ),
              buildSubRecipeComponent('syrup'),
            ],
          ),
        );
      // Names no identifier spells, so a snapshot that stored the id under
      // the name would read the same as one that stored nothing.
      final ingredients = FakeIngredientRepository()
        ..stored['bread-flour'] = buildIngredient(
          id: 'bread-flour',
          name: 'Bread flour',
        )
        ..stored['syrup-sugar'] = buildIngredient(
          id: 'syrup-sugar',
          name: 'Caster sugar',
        );

      final run = await _useCase(
        recipes,
        ingredients,
      ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));

      expect(run.ingredientSnapshot['bread-flour']!.name, 'Bread flour');
      expect(run.ingredientSnapshot['syrup-sugar']!.name, 'Caster sugar');
    },
  );

  test('an ingredient the library does not hold gets no entry', () async {
    // Nothing validates a component's ingredient reference against
    // storage, so a recipe can outlive the ingredient it names. The run
    // records that there was nothing to record rather than raising or
    // inventing a placeholder — a use case that threw here would take the
    // whole calculation down over a name.
    final recipes = FakeRecipeRepository()
      ..seed(
        buildRecipe(
          id: 'a',
          components: [
            RecipeComponent(
              id: 'known-line',
              target: const IngredientRef('bread-flour'),
              baseQuantity: Quantity.parse('500', Unit.gram),
              behavior: ScalingBehavior.proportional,
              displayOrder: 0,
            ),
            RecipeComponent(
              id: 'deleted-line',
              target: const IngredientRef('gone'),
              baseQuantity: Quantity.parse('10', Unit.gram),
              behavior: ScalingBehavior.proportional,
              displayOrder: 1,
            ),
          ],
        ),
      );
    final ingredients = FakeIngredientRepository()
      ..stored['bread-flour'] = buildIngredient(
        id: 'bread-flour',
        name: 'Bread flour',
      );

    final run = await _useCase(
      recipes,
      ingredients,
    ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));

    expect(run.ingredientSnapshot.containsKey('gone'), isFalse);
    // Its stocked sibling still arrives, so the absent one is one missing
    // entry rather than a lookup that gave up on the first miss.
    expect(run.ingredientSnapshot['bread-flour']!.name, 'Bread flour');
  });

  test('a run over no ingredients at all snapshots none', () async {
    // The empty-map default, reached by a recipe whose only component is a
    // sub-recipe reference. Nothing is fabricated for it.
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'syrup', components: const []))
      ..seed(
        buildRecipe(id: 'a', components: [buildSubRecipeComponent('syrup')]),
      );

    final run = await _useCase(
      recipes,
    ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));

    expect(run.ingredientSnapshot, isEmpty);
  });

  test('a corrupt ingredient row is not read as an absent one', () async {
    // The sibling test above proves a `null` read is tolerated. A read that
    // throws is a damaged row rather than a missing one, and the use case
    // lets it out: catching it would file the damage under the same empty
    // entry a deleted ingredient produces, so a row nobody can decode would
    // render as a line showing its identifier and nothing would say why.
    // A `CorruptDatabaseError` names the row instead. The same error has
    // always reached this caller from the recipe rows; the snapshot widens
    // that path to the ingredient rows rather than opening it.
    //
    // Add the catch to `_ingredientsOf` and this test is what fails.
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));

    await expectLater(
      _useCase(
        recipes,
        _CorruptIngredientRepository(),
      ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram)),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });

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

  test('the caller decides whether a batch bound applies', () async {
    // 1000 g against a 100 g maximum is ten batches.
    final batched = Recipe(
      id: 'a',
      revision: 1,
      name: 'Batched',
      baseYield: Quantity.parse('1000', Unit.gram),
      maxBatchYield: Quantity.parse('100', Unit.gram),
      modifiedAt: DateTime.utc(2026, 9, 8),
      components: const [],
    );
    final recipes = FakeRecipeRepository()..seed(batched);
    final target = Quantity.parse('1000', Unit.gram);

    await expectLater(
      _useCase(
        recipes,
      ).call(recipeId: 'a', targetYield: target, maxPlannedBatches: 5),
      throwsA(isA<BatchLimitExceededError>()),
    );

    // The identical call without the bound. A use case that hard-coded one,
    // or dropped the argument on the way to the calculator, fails one half
    // of this test or the other.
    final run = await _useCase(
      recipes,
    ).call(recipeId: 'a', targetYield: target);
    expect(run.result.batchPlan.batchCount, 10);
  });

  group('RandomRunIdSource', () {
    test('two sources built independently do not agree on an id', () {
      // Two instances rather than two calls on one, which is the whole
      // requirement: a run id is a primary key written by a bare insert, so
      // it has to survive a relaunch. A per-instance counter, or anything
      // seeded from a fixed value, passes "two calls differ" and collides on
      // the first run of the next launch. Drawn from the default source, so
      // this is the generator the app actually binds.
      final first = RandomRunIdSource().next();
      final second = RandomRunIdSource().next();

      expect(first, isNot(second));
    });

    test('an id is 32 lowercase hexadecimal digits', () {
      final id = RandomRunIdSource().next();

      expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('a draw of zero is padded, and every draw is 32 bits wide', () {
      // The one case a hand-written hexadecimal join gets wrong: zero
      // renders as a single `0`, so an unpadded identifier is 25 digits
      // rather than 32 — and, worse, two different pairs of draws can then
      // spell the same string. Scripted rather than sampled because
      // `Random.secure()` will not produce this in a test's lifetime.
      final random = _ScriptedRandom([0]);

      final id = RandomRunIdSource(random).next();

      expect(id, '0' * 32);
      // Four draws of the full 32-bit range. A source that asked for a
      // narrower bound would still render `0` here, so the bound is
      // asserted rather than inferred from the digits.
      expect(random.bounds, [4294967296, 4294967296, 4294967296, 4294967296]);
    });

    test('an id is the draws in order, not a set or a sum of them', () {
      // Ordered draws, each distinct and each needing its own padding
      // width, so a source that reversed them, sorted them, or folded them
      // together renders something else.
      final random = _ScriptedRandom([0xdeadbeef, 0x1, 0x0, 0xffffffff]);

      expect(
        RandomRunIdSource(random).next(),
        'deadbeef0000000100000000ffffffff',
      );
    });
  });
}
