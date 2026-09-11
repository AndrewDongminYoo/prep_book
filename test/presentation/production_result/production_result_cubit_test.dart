import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../fakes.dart';

ProductionResultCubit _cubit(
  ProductionRun run, {
  ProductionRunRepository? runs,
}) => ProductionResultCubit(
  const AcknowledgeWarning(),
  const ApplyOverride(),
  SaveProductionRun(runs ?? FakeProductionRunRepository()),
  run: run,
);

/// The line at [path], collapsed or not.
ResultRow _row(ProductionResultState state, String path) =>
    state.allRows.firstWhere((row) => row.path == path);

/// The warning of type [T] the run raised.
T _warning<T extends ProductionWarning>(ProductionRun run) =>
    run.result.warnings.whereType<T>().single;

/// A count unit no recipe in [buildReviewableRun] uses, so a suite can tell
/// a state that reads the whole expanded tree from one that reads the root.
final _bagUnit = Unit.count('bag');

/// A run whose only count unit sits inside a sub-recipe, under a root
/// carrying the free-form line that needs a word for it.
///
/// Deliberately not the shared fixture, where the counted line and the
/// free-form one are siblings: there, a state gathering units from the
/// root's own components would find `sheet` anyway.
Future<ProductionRun> _runWithNestedCountUnit() {
  final recipes = FakeRecipeRepository()
    ..seed(
      buildRecipe(
        id: 'filling',
        components: [
          RecipeComponent(
            id: 'praline',
            target: const IngredientRef('praline'),
            baseQuantity: Quantity.parse('3', _bagUnit),
            behavior: ScalingBehavior.perBatch,
            displayOrder: 0,
          ),
        ],
      ),
    )
    ..seed(
      buildRecipe(
        id: 'tart',
        components: [
          RecipeComponent(
            id: 'gelatin',
            target: const IngredientRef('gelatin'),
            baseQuantity: null,
            behavior: ScalingBehavior.manual,
            displayOrder: 0,
          ),
          buildSubRecipeComponent('filling'),
        ],
      ),
    );
  return StartProductionRun(
    recipes,
    FakeIngredientRepository(),
    const FixedRunIdSource(),
    const FixedClock(),
  ).call(recipeId: 'tart', targetYield: Quantity.parse('1000', Unit.gram));
}

/// A count unit that reaches the screen through the ingredient snapshot and
/// through nothing else.
final _gelatinSheet = Unit.count('gelatin sheet');

/// A run measured in grams from end to end, whose one free-form line
/// references an ingredient the library records in [_gelatinSheet].
///
/// Issue #19: a manual component has no calculated total, so it contributes
/// no unit of its own, and the fixed table holds no count unit at all.
/// Every other source this screen has is grams here — the target yield, the
/// root's base yield, the sub-recipe's base yield, and every calculated
/// line — so the ingredient's own default unit is the only place the word
/// survives. A fixture that let `gelatin sheet` in through a row or through
/// the dependency snapshot would pass whether or not the ingredient
/// snapshot were read at all.
Future<ProductionRun> _runWithCountUnitOnlyOnAnIngredient() {
  final recipes = FakeRecipeRepository()
    ..seed(buildRecipe(id: 'glaze'))
    ..seed(
      buildRecipe(
        id: 'mousse',
        components: [
          RecipeComponent(
            id: 'gelatin-line',
            target: const IngredientRef('gelatin'),
            baseQuantity: null,
            behavior: ScalingBehavior.manual,
            displayOrder: 0,
          ),
          buildSubRecipeComponent('glaze'),
        ],
      ),
    );
  final ingredients = FakeIngredientRepository()
    ..stored['gelatin'] = Ingredient(
      id: 'gelatin',
      name: 'Leaf gelatin',
      defaultUnit: _gelatinSheet,
    );
  return StartProductionRun(
    recipes,
    ingredients,
    const FixedRunIdSource(),
    const FixedClock(),
  ).call(recipeId: 'mousse', targetYield: Quantity.parse('1000', Unit.gram));
}

/// A yield-only unit that reaches the screen through the dependency
/// snapshot and through nothing else.
final _trayUnit = Unit.namedYield('tray');

/// A run whose free-form line consumes a sub-recipe measured in trays.
///
/// A manual line carries no quantity, so the calculator never expands it:
/// the referenced recipe sits in the run's dependency snapshot and in no
/// row's calculated amount, which makes the snapshot the only place the
/// word `tray` survives.
Future<ProductionRun> _runWithManualSubRecipe() {
  final recipes = FakeRecipeRepository()
    ..seed(
      buildRecipe(id: 'streusel', baseYield: Quantity.parse('4', _trayUnit)),
    )
    ..seed(
      buildRecipe(
        id: 'crumble',
        components: [
          RecipeComponent(
            id: 'streusel-line',
            target: const SubRecipeRef('streusel'),
            baseQuantity: null,
            behavior: ScalingBehavior.manual,
            displayOrder: 0,
          ),
        ],
      ),
    );
  return StartProductionRun(
    recipes,
    FakeIngredientRepository(),
    const FixedRunIdSource(),
    const FixedClock(),
  ).call(recipeId: 'crumble', targetYield: Quantity.parse('1000', Unit.gram));
}

void main() {
  group('what the screen shows', () {
    test('opens with every sub-recipe collapsed', () async {
      final cubit = _cubit(await buildReviewableRun());

      // The root's own lines and nothing else, which is the design
      // document's "the result view initially keeps sub-recipes
      // collapsed". A screen that flattened the whole expansion would
      // open on eight lines instead of five.
      expect(cubit.state.visibleRows.map((row) => row.path), [
        '0',
        '1',
        '2',
        '3',
        '4',
      ]);
      expect(cubit.state.allRows.length, 9);
    });

    test('the tree is walked once per state, not once per read', () async {
      final cubit = _cubit(await buildReviewableRun());
      final state = cubit.state;

      // Identity, not equality: two walks of the same run produce equal
      // lists, so only the same instance coming back proves the recursion
      // did not run again. Every override control on screen reaches it
      // through unitChoicesFor.
      expect(identical(state.allRows, state.allRows), isTrue);

      // And the cache belongs to the instance, so the next state walks
      // afresh rather than serving rows the run may have moved past.
      cubit.expansionToggled('1');
      expect(identical(cubit.state.allRows, state.allRows), isFalse);
    });

    test('the rows are not a list a caller can reorder', () async {
      final cubit = _cubit(await buildReviewableRun());

      // One walk now has many readers. Sorting the returned list in place
      // used to spoil the caller's own copy and would now spoil the order
      // every later reader sees, so the list refuses.
      expect(
        () => cubit.state.allRows.sort((a, b) => b.path.compareTo(a.path)),
        throwsUnsupportedError,
      );
    });

    test('opening a line reveals the recipe under it, one level', () async {
      final cubit = _cubit(await buildReviewableRun())..expansionToggled('1');

      // Dough's own two lines appear; the starter nested inside Dough does
      // not, because nothing has opened it.
      expect(cubit.state.visibleRows.map((row) => row.path), [
        '0',
        '1',
        '1/0',
        '1/1',
        '2',
        '3',
        '4',
      ]);
    });

    test('a closed ancestor hides what is open beneath it', () async {
      final cubit = _cubit(await buildReviewableRun())
        ..expansionToggled('1')
        ..expansionToggled('1/1');

      expect(cubit.state.visibleRows.map((row) => row.path), contains('1/1/0'));

      cubit.expansionToggled('1');
      expect(
        cubit.state.visibleRows.map((row) => row.path),
        isNot(contains('1/1/0')),
      );

      // And the state the operator had comes back, rather than the nested
      // line having been forgotten while its parent was shut. An
      // implementation that removed descendants on collapse passes the
      // line above and fails this one.
      cubit.expansionToggled('1');
      expect(cubit.state.visibleRows.map((row) => row.path), contains('1/1/0'));
    });

    test('a rounded line keeps the exact value beside it', () async {
      final state = _cubit(await buildReviewableRun()).state;

      final total = _row(state, '0').total!;
      // 200 g, 200 g and 100 g per batch, each rounded up to the next 30 g
      // and then summed — not the exact 500 g total rounded once, which
      // would read 510 g.
      expect(total.displayed, Quantity.parse('540', Unit.gram));
      expect(total.exact, Quantity.parse('500', Unit.gram));
      expect(total.wasRounded, isTrue);
    });

    test('consecutive batches taking the same amount are one group', () async {
      final state = _cubit(await buildReviewableRun()).state;

      final groups = _row(state, '0').batches;

      expect(groups.length, 2);
      expect((groups.first.firstBatch, groups.first.lastBatch), (1, 2));
      expect(groups.first.isRange, isTrue);
      expect(groups.first.amount!.displayed, Quantity.parse('210', Unit.gram));
      expect(groups.first.amount!.exact, Quantity.parse('200', Unit.gram));
      expect((groups.last.firstBatch, groups.last.lastBatch), (3, 3));
      expect(groups.last.isRange, isFalse);
      expect(groups.last.amount!.displayed, Quantity.parse('120', Unit.gram));
    });

    test('batches that round alike from unlike amounts stay apart', () {
      // The discriminating case, and the shared fixture cannot supply it:
      // there, every boundary where the exact amounts change is also a
      // boundary where the displayed ones do, so a grouping that compared
      // only what is displayed would produce the same lines. Here both
      // batches display 200 g and only one of them is 200 g, and merging
      // them would hide an exact value the spec keeps visible.
      final rule = RoundingRule.upToIncrement(Decimal.parse('200'));
      final row = ResultRow(
        path: '0',
        depth: 0,
        recipeId: 'r',
        component: ScaledComponent(
          source: RecipeComponent(
            id: 'flour',
            target: const IngredientRef('flour'),
            baseQuantity: Quantity.parse('300', Unit.gram),
            behavior: ScalingBehavior.proportional,
            rounding: rule,
            displayOrder: 0,
          ),
          total: ScaledQuantity.unrounded(Quantity.parse('300', Unit.gram)),
          perBatch: [
            ScaledQuantity.rounded(
              exact: Quantity.parse('200', Unit.gram),
              rule: rule,
            ),
            ScaledQuantity.rounded(
              exact: Quantity.parse('100', Unit.gram),
              rule: rule,
            ),
          ],
        ),
      );

      final groups = row.batches;
      expect(groups.map((group) => group.amount!.displayed), [
        Quantity.parse('200', Unit.gram),
        Quantity.parse('200', Unit.gram),
      ]);
      expect(groups.map((group) => group.amount!.exact), [
        Quantity.parse('200', Unit.gram),
        Quantity.parse('100', Unit.gram),
      ]);
    });

    test('a per-batch line is one group over every batch', () async {
      final state = _cubit(await buildReviewableRun()).state;

      final groups = _row(state, '4').batches;

      expect(groups.length, 1);
      expect((groups.single.firstBatch, groups.single.lastBatch), (1, 3));
      expect(groups.single.amount!.displayed, Quantity.parse('2', sheetUnit));
      expect(_row(state, '4').total!.displayed, Quantity.parse('6', sheetUnit));
    });

    test('a free-form line has no amount in any batch', () async {
      final state = _cubit(await buildReviewableRun()).state;

      final row = _row(state, '3');

      expect(row.isManual, isTrue);
      expect(row.total, isNull);
      expect(row.batches.single.amount, isNull);
      expect(
        (row.batches.single.firstBatch, row.batches.single.lastBatch),
        (1, 3),
      );
    });

    test('a line is named out of the run own snapshot', () async {
      final state = _cubit(await buildReviewableRun()).state;

      // Both kinds of line by the name the run's own snapshots hold,
      // never by anything read from today's library — that would put a
      // name on a stored run that was never part of it.
      expect(state.labelOf(_row(state, '1')), 'Dough');
      // The ingredient's own name, not the identifier `flour` the
      // component references. Issue #20: an ingredient created as "Bread
      // flour" reached the production sheet as its slug, on the same list
      // where a sub-recipe row read "Dough".
      expect(state.labelOf(_row(state, '0')), 'Bread flour');
      expect(state.recipeNameOf('bun'), 'Bun');
      expect(state.recipeNameOf('starter'), 'Starter');
      expect(state.componentLabelOf(('bun', 'flour')), 'Bread flour');
      // A key naming nothing in the tree falls back to the component id
      // rather than rendering blank.
      expect(state.componentLabelOf(('bun', 'nothing')), 'nothing');
    });

    test(
      'a line whose ingredient the library never held keeps its id',
      () async {
        // `rye`, in the `Starter` sub-recipe, is the one ingredient
        // `buildReviewableIngredients` deliberately does not stock. Nothing
        // validates a component's ingredient reference against storage, so
        // a run can reference an ingredient the library does not hold, and
        // the screen has to render that line rather than break on it.
        expect(
          buildReviewableIngredients().stored.containsKey('rye'),
          isFalse,
          reason: 'the fixture must leave this one ingredient unstocked',
        );

        final state = _cubit(await buildReviewableRun()).state;

        expect(state.labelOf(_row(state, '2/0')), 'rye');
        // Its named sibling on the same run, so a state that lost every
        // name would not pass this test by passing the line above.
        expect(state.labelOf(_row(state, '0')), 'Bread flour');
      },
    );

    test('a run stored before the snapshot renders by identifier', () async {
      // What a run decoded out of a payload written before the ingredient
      // snapshot existed carries: an empty map. The screen renders the
      // identifier for every line of it, which is what it did for every
      // ingredient before this change — an implementation that raised, or
      // that rendered blank, would take an older stored run off the
      // screen entirely.
      final calculated = await buildReviewableRun();
      final older = ProductionRun(
        id: calculated.id,
        createdAt: calculated.createdAt,
        recipe: calculated.recipe,
        dependencySnapshot: calculated.dependencySnapshot,
        targetYield: calculated.targetYield,
        result: calculated.result,
      );

      final state = _cubit(older).state;

      expect(older.ingredientSnapshot, isEmpty);
      expect(state.labelOf(_row(state, '0')), 'flour');
      expect(state.labelOf(_row(state, '3')), 'salt');
      // The sub-recipe half is unaffected, which is what says the fallback
      // is the ingredient path alone and not a screen that stopped
      // reading its snapshots.
      expect(state.labelOf(_row(state, '1')), 'Dough');
    });

    test('a renamed ingredient does not reach a run already made', () async {
      // The property snapshotting exists for. The library moves on; the
      // run does not. An implementation reading the library at render
      // time would show "Rye flour" here — and would also have to invent
      // a load state on a screen that has none, since the run arrives
      // already calculated.
      final library = buildReviewableIngredients();
      final run = await buildReviewableRun(ingredients: library);

      await library.upsert(
        Ingredient(
          id: 'flour',
          name: 'Renamed after the run',
          defaultUnit: Unit.gram,
        ),
      );

      final state = _cubit(run).state;

      expect(state.labelOf(_row(state, '0')), 'Bread flour');
    });

    test('an override offers the unit its line is measured in', () async {
      final state = _cubit(await buildReviewableRun()).state;

      final row = _row(state, '4');

      // `sheet` is not in the built-in table, so a picker built from that
      // table alone would open on a value missing from its own items.
      expect(state.unitChoicesFor(row), contains(sheetUnit));
      expect(state.draftFor(row).unit, sheetUnit);
      // A free-form line has no calculated unit to start from, so it
      // starts where every draft in this app starts.
      expect(state.draftFor(_row(state, '3')).unit, Unit.gram);
      expect(state.draftFor(_row(state, '3')).amount, isEmpty);
    });

    test('a free-form line offers a unit its own recipe uses', () async {
      final state = _cubit(await buildReviewableRun()).state;

      // `salt` is free-form and has no calculated unit of its own, while
      // `liner` beside it is counted in sheets. The built-in table holds
      // no count unit at all, so a control offered that table alone would
      // make an operator record sheets of something in grams — into a
      // snapshot no screen can amend afterwards.
      expect(state.unitChoicesFor(_row(state, '3')), contains(sheetUnit));
    });

    test(
      'a free-form line offers a count unit only a sub-recipe uses',
      () async {
        final state = _cubit(await _runWithNestedCountUnit()).state;

        final manual = _row(state, '0');
        expect(manual.isManual, isTrue);
        // What widens is the choice, not the seed: the control still opens
        // on grams, because a free-form line has no calculated unit to
        // start from.
        expect(state.draftFor(manual).unit, Unit.gram);
        // `bag` is nowhere in the root recipe — it is in the sub-recipe the
        // domain expanded underneath it — so a state that gathered the
        // run's units from `run.result.components` alone would offer none
        // of it and still pass the test above.
        expect(state.unitChoicesFor(manual), contains(_bagUnit));
      },
    );

    test("a free-form line offers its own ingredient's count unit", () async {
      final state = _cubit(await _runWithCountUnitOnlyOnAnIngredient()).state;

      final manual = _row(state, '0');
      expect(manual.isManual, isTrue);
      // Nothing else in this run is measured in anything but grams, so a
      // state that read only the target yield, the dependency snapshot,
      // and the calculated rows would leave the operator recording
      // sheets of gelatin in grams — into a snapshot no screen can amend
      // afterwards. That is issue #19.
      expect(state.unitChoicesFor(manual), contains(_gelatinSheet));
      // The seed is unchanged: a free-form line still has no calculated
      // unit to start from, so the control opens on grams and the wider
      // choice is what the operator reaches for.
      expect(state.draftFor(manual).unit, Unit.gram);
      // And the run really is grams everywhere else, so the assertion
      // above cannot be satisfied by any other source.
      expect(
        state.unitChoicesFor(manual).where((unit) => unit == _gelatinSheet),
        hasLength(1),
      );
      expect(
        state.allRows.map((row) => row.total?.displayed.unit).toSet(),
        isNot(contains(_gelatinSheet)),
      );
    });

    test('a free-form sub-recipe line offers the yield it takes', () async {
      final state = _cubit(await _runWithManualSubRecipe()).state;

      final manual = _row(state, '0');
      expect(manual.isManual, isTrue);
      // Nothing expanded the sub-recipe, so no row carries `tray` and the
      // run's own dependency snapshot is the only source of it. A state
      // built from [ProductionResultState.allRows] alone would leave the
      // operator recording trays of streusel in grams.
      expect(state.unitChoicesFor(manual), contains(_trayUnit));
    });

    test('a unit the run repeats is offered once', () async {
      final state = _cubit(await buildReviewableRun()).state;

      final choices = state.unitChoicesFor(_row(state, '4'));

      // Grams are in the fixed table and in the run; sheets are in the
      // run and are this line's own draft unit. A dropdown asserts when
      // two of its items match its value, so the three sources have to
      // meet in a set rather than in a concatenation.
      expect(choices.length, choices.toSet().length);
      expect(choices.where((unit) => unit == Unit.gram), hasLength(1));
      expect(choices.where((unit) => unit == sheetUnit), hasLength(1));
    });
  });

  group('finding the line a warning names', () {
    test('a component reached by two routes reports the first', () async {
      final state = _cubit(await buildReviewableRun()).state;

      // Starter is referenced twice — from inside Dough and again from the
      // root — so its one ingredient is two lines under one key. Which of
      // them to show is a choice with no better answer, and it is written
      // down rather than left to fall out of the walk.
      expect(
        state.allRows
            .where((row) => row.key == ('starter', 'rye'))
            .map((row) => row.path),
        ['1/1/0', '2/0'],
      );
      expect(state.pathOf(('starter', 'rye')), '1/1/0');
    });

    test('a component no line carries has no path', () async {
      final state = _cubit(await buildReviewableRun()).state;

      expect(state.pathOf(('bun', 'not-a-component')), isNull);
    });

    test('revealing a nested line opens every sub-recipe above it', () async {
      final cubit = _cubit(await buildReviewableRun());
      expect(
        cubit.state.visibleRows.map((row) => row.path),
        isNot(contains('1/1/0')),
      );

      cubit.componentRevealed(('starter', 'rye'));

      // Both levels at once. Opening one at a time is what the operator
      // was doing by hand, and it is what this exists to replace.
      expect(cubit.state.expandedPaths, {'1', '1/1'});
      expect(cubit.state.visibleRows.map((row) => row.path), contains('1/1/0'));
    });

    test('revealing leaves the tree the operator already opened', () async {
      final cubit = _cubit(await buildReviewableRun())..expansionToggled('2');
      expect(cubit.state.expandedPaths, {'2'});

      cubit.componentRevealed(('starter', 'rye'));

      // The reveal adds and never removes, so the second route into
      // Starter is still open afterwards.
      expect(cubit.state.expandedPaths, {'2', '1', '1/1'});
    });

    test('revealing a line already in view opens nothing', () async {
      final cubit = _cubit(await buildReviewableRun());
      expect(cubit.state.pathOf(('bun', 'salt')), '3');

      cubit.componentRevealed(('bun', 'salt'));

      // A root line has no ancestors. The screen still scrolls to it,
      // which is not this layer's half of the job.
      expect(cubit.state.expandedPaths, isEmpty);
    });

    test('a component no line carries opens nothing', () async {
      final cubit = _cubit(await buildReviewableRun())..expansionToggled('1');
      expect(cubit.state.pathOf(('bun', 'not-a-component')), isNull);

      cubit.componentRevealed(('bun', 'not-a-component'));

      expect(cubit.state.expandedPaths, {'1'});
    });

    test('a stored run can still be opened up', () async {
      final cubit = _cubit(await buildReviewableRun());
      await cubit.save();
      expect(cubit.state.isEditable, isFalse);

      cubit.componentRevealed(('starter', 'rye'));

      // Unlike acknowledging and overriding, which the test below pins as
      // refused once a run is stored. This moves view state alone, and a
      // stored run has to stay reviewable.
      expect(cubit.state.expandedPaths, {'1', '1/1'});
    });
  });

  group('overrides', () {
    test('a typed amount is recorded, calculation untouched', () async {
      final cubit = _cubit(await buildReviewableRun());
      final row = _row(cubit.state, '0');

      cubit.overrideAmountChanged(row, '600');

      expect(cubit.state.overrideFor(row), Quantity.parse('600', Unit.gram));
      // The calculated total is still what the domain produced. The spec
      // keeps the original available for comparison, so an implementation
      // that rewrote the result would fail here.
      expect(
        _row(cubit.state, '0').total!.displayed,
        Quantity.parse('540', Unit.gram),
      );
    });

    test('an amount that is not a number reaches the field only', () async {
      final cubit = _cubit(await buildReviewableRun());
      final row = _row(cubit.state, '0');

      cubit.overrideAmountChanged(row, '1.2.3');

      expect(cubit.state.draftFor(row).amount, '1.2.3');
      expect(cubit.state.draftFor(row).amountIsInvalid, isTrue);
      expect(cubit.state.overrideFor(row), isNull);
    });

    test('zero is not an amount, and neither is an empty field', () async {
      final cubit = _cubit(await buildReviewableRun());
      final row = _row(cubit.state, '0');

      cubit.overrideAmountChanged(row, '0');
      expect(cubit.state.draftFor(row).amountIsInvalid, isTrue);
      expect(cubit.state.overrideFor(row), isNull);

      // An empty field says nothing rather than blaming the operator for
      // not having had a turn — the rule the production setup screen's
      // amount field states.
      cubit.overrideAmountChanged(row, '');
      expect(cubit.state.draftFor(row).amountIsInvalid, isFalse);
    });

    test('clearing the field leaves a recorded value in place', () async {
      final cubit = _cubit(await buildReviewableRun());
      final row = _row(cubit.state, '0');

      cubit
        ..overrideAmountChanged(row, '600')
        ..overrideAmountChanged(row, '');

      // The documented consequence of the domain having no word for
      // withdrawing an override: the field empties, the value stays.
      expect(cubit.state.draftFor(row).amount, isEmpty);
      expect(cubit.state.overrideFor(row), Quantity.parse('600', Unit.gram));
      // And an emptied field is not a half-typed one, so it does not hold
      // the save: the value the run carries is the value the line above
      // the field still reports.
      expect(cubit.state.canSave, isTrue);
    });

    test('the unit is part of what is recorded', () async {
      final cubit = _cubit(await buildReviewableRun());
      final row = _row(cubit.state, '0');

      cubit
        ..overrideAmountChanged(row, '600')
        ..overrideUnitChanged(row, Unit.kilogram);

      // 600 kg, not 600 g and not 0.6 kg: an override replaces the amount
      // outright, and nothing converts it.
      expect(
        cubit.state.overrideFor(row),
        Quantity.parse('600', Unit.kilogram),
      );
      expect(cubit.state.draftFor(row).unit, Unit.kilogram);
    });

    test('a free-form line takes its amount the same way', () async {
      final cubit = _cubit(await buildReviewableRun());
      final row = _row(cubit.state, '3');

      cubit.overrideAmountChanged(row, '12');

      expect(cubit.state.overrideFor(row), Quantity.parse('12', Unit.gram));
      // Entering the amount is not acknowledging the warning: the run is
      // still not finalizable until the operator says they have seen it.
      expect(cubit.state.savesAsDraft, isTrue);
    });

    test('an override reaches every occurrence of a component', () async {
      final cubit = _cubit(await buildReviewableRun())
        ..expansionToggled('1')
        ..expansionToggled('1/1')
        ..expansionToggled('2');
      final nested = _row(cubit.state, '1/1/0');
      final direct = _row(cubit.state, '2/0');

      cubit.overrideAmountChanged(nested, '25');

      // Both lines are the rye of the Starter recipe, reached by two
      // routes, and the domain keys an override by that pair rather than
      // by where it sits in the tree — so one entry covers both.
      expect(direct.key, nested.key);
      expect(cubit.state.overrideFor(direct), Quantity.parse('25', Unit.gram));
      // Their calculated amounts stay different, which is what makes this
      // a real sharing rather than two lines that were the same anyway.
      expect(nested.total!.displayed, Quantity.parse('16', Unit.gram));
      expect(direct.total!.displayed, Quantity.parse('40', Unit.gram));
    });
  });

  group('warnings', () {
    test('component warnings stay with the row they name', () async {
      final run = await buildReviewableRun();
      final state = _cubit(run).state;

      expect(state.warningsFor(_row(state, '0')), [
        _warning<RoundingAdjustedWarning>(run),
      ]);
      expect(state.warningsFor(_row(state, '3')), [
        _warning<ManualComponentWarning>(run),
      ]);
      expect(state.warningsFor(_row(state, '1')), isEmpty);
    });

    test('a warning stays listed once it has been acknowledged', () async {
      final run = await buildReviewableRun();
      final cubit = _cubit(run);
      final manual = _warning<ManualComponentWarning>(run);

      cubit.warningAcknowledged(manual);

      expect(cubit.state.isAcknowledged(manual), isTrue);
      // Still on the list. "Visible until acknowledged" is a floor, not a
      // ceiling: an operator who accepted a warning has to be able to
      // check what they accepted.
      expect(cubit.state.warnings, contains(manual));
      expect(cubit.state.warnings.length, 2);
    });

    test('only a blocking warning stands before finalizing', () async {
      final run = await buildReviewableRun();
      final cubit = _cubit(run);

      expect(cubit.state.savesAsDraft, isTrue);
      expect(cubit.state.blockingWarningsOutstanding, 1);

      cubit.warningAcknowledged(_warning<ManualComponentWarning>(run));

      // The rounding warning is still unacknowledged and the run is
      // finalizable anyway, because it does not block. An implementation
      // that counted every warning instead of reading `isFinalizable`
      // would still report a draft here.
      expect(
        cubit.state.isAcknowledged(_warning<RoundingAdjustedWarning>(run)),
        isFalse,
      );
      expect(cubit.state.savesAsDraft, isFalse);
      expect(cubit.state.blockingWarningsOutstanding, 0);
    });

    test('an archived dependency is a warning like any other', () async {
      final run = await buildArchivedRun();
      final cubit = _cubit(run);

      final archived = _warning<ArchivedDependencyWarning>(run);
      expect(cubit.state.savesAsDraft, isTrue);

      cubit.warningAcknowledged(archived);
      expect(cubit.state.savesAsDraft, isFalse);
    });
  });

  group('saving', () {
    test('a run that is not finalizable is stored all the same', () async {
      final runs = FakeProductionRunRepository();
      final cubit = _cubit(await buildReviewableRun(), runs: runs);

      expect(cubit.state.savesAsDraft, isTrue);
      await cubit.save();

      // Acknowledgement is a precondition of finalizing a run, not of
      // storing one — the application layer's ruling, which this screen
      // must not tighten.
      expect(runs.stored.keys, ['run-1']);
      expect(cubit.state.status, ProductionResultStatus.saved);
    });

    test('what is stored carries the overrides and acknowledgements', () async {
      final runs = FakeProductionRunRepository();
      final run = await buildReviewableRun();
      final cubit = _cubit(run, runs: runs);
      final manual = _warning<ManualComponentWarning>(run);

      cubit
        ..overrideAmountChanged(_row(cubit.state, '3'), '12')
        ..warningAcknowledged(manual);
      await cubit.save();

      final stored = runs.stored['run-1']!;
      expect(
        stored.overrides[('bun', 'salt')],
        Quantity.parse('12', Unit.gram),
      );
      expect(stored.acknowledgedWarnings, contains(manual));
      expect(stored.isFinalizable, isTrue);
    });

    test('a half-typed override holds the save back', () async {
      final runs = FakeProductionRunRepository();
      final cubit = _cubit(await buildReviewableRun(), runs: runs);
      final row = _row(cubit.state, '0');

      cubit
        ..overrideAmountChanged(row, '600')
        ..overrideAmountChanged(row, '1.2.3');
      await cubit.save();

      // The run still carries 600 g while the field reports an error, so
      // storing it here would freeze a value the operator was part-way
      // through replacing — into a snapshot no screen can amend. A guard
      // that read `isEditable` alone, as both this method and the button
      // did, stores it.
      expect(runs.stored, isEmpty);
      expect(cubit.state.status, ProductionResultStatus.reviewing);
      expect(cubit.state.canSave, isFalse);
      expect(cubit.state.invalidOverrideLabels, 'Bread flour');
      // And the controls stay live, which is why this is a second
      // predicate rather than a narrower `isEditable`: the field the
      // operator has to correct is the field this would otherwise
      // disable.
      expect(cubit.state.isEditable, isTrue);
    });

    test('correcting the amount lets the run be stored', () async {
      final runs = FakeProductionRunRepository();
      final cubit = _cubit(await buildReviewableRun(), runs: runs);
      final row = _row(cubit.state, '0');

      cubit
        ..overrideAmountChanged(row, '1.2.3')
        ..overrideAmountChanged(row, '700');
      await cubit.save();

      // Held back while the draft was half-typed, not condemned by it: an
      // implementation that remembered a line had ever been invalid would
      // leave the run unsaveable for good.
      expect(
        runs.stored['run-1']!.overrides[('bun', 'flour')],
        Quantity.parse('700', Unit.gram),
      );
      expect(cubit.state.status, ProductionResultStatus.saved);
    });

    test('a second press stores nothing more', () async {
      final runs = FakeProductionRunRepository();
      final cubit = _cubit(await buildReviewableRun(), runs: runs);

      await cubit.save();
      await cubit.save();

      // The repository's write is a bare insert against a primary key, so
      // a second one would throw rather than replace. Refused here, and
      // the first save's outcome is left standing.
      expect(runs.stored.length, 1);
      expect(cubit.state.status, ProductionResultStatus.saved);
    });

    test('two presses inside one frame store once', () async {
      final runs = FakeProductionRunRepository();
      final cubit = _cubit(await buildReviewableRun(), runs: runs);

      // Neither awaited before the other starts, which is what a double
      // tap is. A guard that only read the status after the write had
      // returned would let both through.
      await Future.wait([cubit.save(), cubit.save()]);

      expect(runs.stored.length, 1);
      expect(cubit.state.status, ProductionResultStatus.saved);
    });

    test('a stored run can no longer be changed from here', () async {
      final run = await buildReviewableRun();
      final runs = FakeProductionRunRepository();
      final cubit = _cubit(run, runs: runs);

      expect(cubit.state.isEditable, isTrue);
      await cubit.save();

      // Recording state against a run that is already stored is a
      // different use case, on a screen this slice does not build. An
      // editable control here would let the screen and the stored
      // snapshot disagree with nothing to reconcile them — so the
      // mutators are asked, not only the flag the controls read.
      expect(cubit.state.isEditable, isFalse);
      cubit
        ..warningAcknowledged(_warning<ManualComponentWarning>(run))
        ..overrideAmountChanged(_row(cubit.state, '3'), '12');
      expect(cubit.state.run, same(runs.stored['run-1']));
      expect(cubit.state.draftFor(_row(cubit.state, '3')).amount, isEmpty);
    });

    test('a change landing while the write is in flight is refused', () async {
      final run = await buildReviewableRun();
      final runs = PendingRunRepository();
      final cubit = _cubit(run, runs: runs);
      final row = _row(cubit.state, '3');

      final saving = cubit.save();

      // The fixture reached the state under test: the write has been
      // handed the run and has not returned. Without this the two
      // mutations below would be running against an ordinary reviewing
      // state and would prove nothing.
      expect(cubit.state.status, ProductionResultStatus.saving);

      cubit
        ..warningAcknowledged(_warning<ManualComponentWarning>(run))
        ..overrideAmountChanged(row, '12');

      // The snapshot the repository is writing is the one the screen
      // still shows. A mutator that ran here would leave the state
      // carrying a change the stored run does not have, and a production
      // run snapshot is immutable, so nothing afterwards could reconcile
      // the two.
      expect(cubit.state.run, same(runs.received.single));
      expect(cubit.state.draftFor(row).amount, isEmpty);

      runs.release();
      await saving;
      expect(cubit.state.status, ProductionResultStatus.saved);
    });

    test('a failed save is reported and may be retried', () async {
      final cubit = _cubit(
        await buildReviewableRun(),
        runs: UnwritableRunRepository(),
      );

      await cubit.save();

      expect(cubit.state.status, ProductionResultStatus.failure);
      expect(cubit.state.error, isA<StateError>());
      expect(cubit.state.isEditable, isTrue);
    });

    test('a save that lands after the screen is gone emits nothing', () async {
      final cubit = _cubit(await buildReviewableRun());

      final saving = cubit.save();
      await cubit.close();
      await saving;

      // The cubit closed while the write was in flight. Emitting into a
      // closed cubit throws, which would surface as an unhandled error out
      // of a screen the operator has already left.
      expect(cubit.state.status, ProductionResultStatus.saving);
    });

    test('a failure landing after the screen is gone emits nothing', () async {
      final cubit = _cubit(
        await buildReviewableRun(),
        runs: UnwritableRunRepository(),
      );

      final saving = cubit.save();
      await cubit.close();
      await saving;

      expect(cubit.state.status, ProductionResultStatus.saving);
    });
  });
}
