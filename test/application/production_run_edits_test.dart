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
  // `return await` for the reason Task 5 records: `async_return_with_no_await`
  // rejects an `async` body that returns a future without awaiting it.
  return await StartProductionRun(
    recipes,
    _FixedIds(),
    _FixedClock(),
  ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));
}

/// A recipe with two independently manual components.
///
/// A fixture with only one blocking warning cannot tell "acknowledges the
/// one warning passed in" apart from "acknowledges every blocking warning
/// the run carries" — this one can.
Recipe _recipeWithTwoManualComponents({required String id}) => buildRecipe(
  id: id,
  components: [
    RecipeComponent(
      id: 'salt',
      target: const IngredientRef('salt'),
      baseQuantity: null,
      behavior: ScalingBehavior.manual,
      displayOrder: 0,
    ),
    RecipeComponent(
      id: 'pepper',
      target: const IngredientRef('pepper'),
      baseQuantity: null,
      behavior: ScalingBehavior.manual,
      displayOrder: 1,
    ),
  ],
);

void main() {
  test(
    'acknowledging the blocking warning makes the run finalizable',
    () async {
      final run = await _buildRun();
      expect(run.isFinalizable, isFalse);

      final blocking = run.result.warnings.firstWhere((w) => w.isBlocking);
      final acknowledged = const AcknowledgeWarning().call(run, blocking);

      // Passing this requires the fixture to carry exactly one blocking
      // warning: a second, unacknowledged blocking warning would leave
      // `isFinalizable` false.
      expect(acknowledged.isFinalizable, isTrue);
    },
  );

  test(
    'acknowledging one blocking warning leaves the other outstanding',
    () async {
      final recipes = FakeRecipeRepository()
        ..seed(_recipeWithTwoManualComponents(id: 'a'));
      final run = await StartProductionRun(
        recipes,
        _FixedIds(),
        _FixedClock(),
      ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));
      final blocking = run.result.warnings.where((w) => w.isBlocking).toList();
      expect(blocking, hasLength(2));

      final firstOnly = const AcknowledgeWarning().call(run, blocking[0]);
      expect(
        firstOnly.isFinalizable,
        isFalse,
        reason: 'the second blocking warning was never acknowledged',
      );

      final both = const AcknowledgeWarning().call(firstOnly, blocking[1]);
      expect(both.isFinalizable, isTrue);
    },
  );

  test(
    'an override records the operator value without rewriting the result',
    () async {
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
    },
  );

  test('overrides on the same component id in different recipes '
      'do not collide', () async {
    // `ApplyOverride` writes into the overrides map without consulting the
    // result, so this needs no second recipe: 'b' does not have to exist in
    // the run for the key pairing to matter. What is under test is only
    // the two halves of `OverrideKey`.
    final run = await _buildRun();

    final firstOverridden = const ApplyOverride().call(
      run,
      recipeId: 'a',
      componentId: 'flour',
      value: Quantity.parse('600', Unit.gram),
    );
    final bothOverridden = const ApplyOverride().call(
      firstOverridden,
      recipeId: 'b',
      componentId: 'flour',
      value: Quantity.parse('700', Unit.gram),
    );

    expect(
      bothOverridden.overrides[('a', 'flour')],
      Quantity.parse('600', Unit.gram),
    );
    expect(
      bothOverridden.overrides[('b', 'flour')],
      Quantity.parse('700', Unit.gram),
    );
    expect(bothOverridden.overrides, hasLength(2));
  });

  test('saving stores the run with its acknowledgements', () async {
    final runs = FakeProductionRunRepository();
    final run = await _buildRun();
    final blocking = run.result.warnings.firstWhere((w) => w.isBlocking);
    final acknowledged = const AcknowledgeWarning().call(run, blocking);

    await SaveProductionRun(runs).call(acknowledged);

    // `ProductionRun` has identity equality (no `==` override), and every
    // domain mutator returns a fresh instance via `_copyWith`, so `same`
    // proves `SaveProductionRun` wrote exactly this object once: a second
    // write via `recordAcknowledgement`/`recordOverride` issued *after*
    // `save` would replace the stored value with a new instance and fail
    // this check.
    final stored = await runs.findById('run-1');
    expect(stored, same(acknowledged));
    expect(stored!.acknowledgedWarnings, contains(blocking));
  });

  test('a run that is not finalizable is still saved', () async {
    final runs = FakeProductionRunRepository();
    final run = await _buildRun();
    expect(run.isFinalizable, isFalse);

    await SaveProductionRun(runs).call(run);

    expect(await runs.findById('run-1'), same(run));
  });
}
