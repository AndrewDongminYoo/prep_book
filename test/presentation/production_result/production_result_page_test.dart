import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../../helpers/helpers.dart';
import '../fakes.dart';

/// Tall enough that the whole run renders.
///
/// A `ListView` builds only what is inside its viewport and cache extent,
/// and a finder cannot reach a child that was never built — so a short
/// viewport would turn "the screen does not show this" and "the screen has
/// not built this yet" into the same result. The one test below that cares
/// about a small window sets its own.
const _roomyViewport = Size(800, 2400);

Widget _screenOver(ProductionRun run, {ProductionRunRepository? runs}) =>
    ProductionResultPage(
      acknowledgeWarning: const AcknowledgeWarning(),
      applyOverride: const ApplyOverride(),
      saveProductionRun: SaveProductionRun(
        runs ?? FakeProductionRunRepository(),
      ),
      run: run,
    );

Future<void> _open(
  WidgetTester tester,
  ProductionRun run, {
  ProductionRunRepository? runs,
  Size viewport = _roomyViewport,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpApp(_screenOver(run, runs: runs));
  await tester.pump();
}

/// Opens or closes the line at [path].
Future<void> _toggle(WidgetTester tester, String path) async {
  await tester.tap(find.byKey(ValueKey('expand-$path')));
  await tester.pump();
}

/// The warning of type [T] the run raised.
T _warning<T extends ProductionWarning>(ProductionRun run) =>
    run.result.warnings.whereType<T>().single;

/// The override amount field on the line at [path].
///
/// Reached through its control rather than by its own key: the key sits on
/// the control, which is what holds the field's text across the rebuilds
/// its own row causes.
TextFormField _amountField(WidgetTester tester, String path) =>
    tester.widget<TextFormField>(
      find.descendant(
        of: find.byKey(ValueKey('override-amount-$path')),
        matching: find.byType(TextFormField),
      ),
    );

/// The path of the chained run's line at [depth].
///
/// Every link holds one component, so the line at each level is index zero
/// of the level above it.
String _chainPath(int depth) => List.filled(depth + 1, '0').join('/');

/// The path of the free-form line `warnAtTheDeepest` adds.
///
/// The sibling of the deepest ingredient line: both belong to the last
/// link, so they hang off the line one level up, at index one rather than
/// zero.
String _deepWarningPath(int depth) => '${_chainPath(depth - 1)}/1';

/// A run whose sub-recipes chain [depth] levels below the root.
///
/// Local to this suite rather than in `fakes.dart`, which is the fixture
/// both result suites share: this one has a single caller, and nothing
/// about it is arithmetic worth asserting twice.
///
/// Each link is one recipe holding one component that references the next
/// link, until the last, whose component is an ingredient. The line at
/// depth [depth] is therefore the deepest the screen can show, and it takes
/// opening every line above it to reach.
///
/// Every link asks for exactly its own yield and states no maximum, so each
/// scales 1:1 into a single batch and nothing decays down the chain.
///
/// With [warnAtTheDeepest] the last link carries a second, free-form
/// component beside its ingredient line. That raises a component warning
/// against a component the run keeps at the bottom of the tree, which is
/// what a reveal has to reach — the shared fixture's two warnings both name
/// root components, which are on screen whether anything reveals them or
/// not. Its path is [_deepWarningPath].
Future<ProductionRun> _buildChainedRun({
  required int depth,
  bool warnAtTheDeepest = false,
}) {
  final recipes = FakeRecipeRepository();
  for (var level = 0; level <= depth; level++) {
    recipes.seed(
      Recipe(
        id: 'link-$level',
        revision: 1,
        name: 'Link $level',
        baseYield: Quantity.parse('1000', Unit.gram),
        modifiedAt: DateTime.utc(2026, 9, 8),
        components: [
          RecipeComponent(
            id: 'line-$level',
            target: level == depth
                ? const IngredientRef('flour')
                : SubRecipeRef('link-${level + 1}'),
            baseQuantity: Quantity.parse('1000', Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
          if (warnAtTheDeepest && level == depth)
            RecipeComponent(
              id: 'taste',
              target: const IngredientRef('salt'),
              baseQuantity: null,
              behavior: ScalingBehavior.manual,
              displayOrder: 1,
            ),
        ],
      ),
    );
  }
  return StartProductionRun(
    recipes,
    FakeIngredientRepository(),
    const FixedRunIdSource(),
    const FixedClock(),
  ).call(recipeId: 'link-0', targetYield: Quantity.parse('1000', Unit.gram));
}

void main() {
  group('ProductionResultPage', () {
    testWidgets('names the run and what each line takes', (tester) async {
      await _open(tester, await buildReviewableRun());

      expect(find.text('Bun'), findsOneWidget);
      expect(find.text('1000 g'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      // The rounded line carries both values, the free-form one carries
      // neither, and a line measured in a recipe-defined unit reads in that
      // unit rather than being converted into something the table knows.
      expect(find.text('540 g · exactly 500 g'), findsOneWidget);
      expect(find.text('100 g'), findsOneWidget);
      expect(find.text('No calculated amount'), findsOneWidget);
      expect(find.text('6 sheet'), findsOneWidget);
    });

    testWidgets('a sub-recipe is collapsed until it is opened', (tester) async {
      await _open(tester, await buildReviewableRun());

      // The nested line reads by the name the run snapshotted for it, not
      // by the `water` identifier its component references — a rendered
      // sheet names a sub-recipe's ingredients the same way it names the
      // root's.
      expect(find.text('Dough'), findsOneWidget);
      expect(find.text('Filtered water'), findsNothing);

      await _toggle(tester, '1');
      expect(find.text('Filtered water'), findsOneWidget);
      expect(find.text('60 g'), findsOneWidget);

      await _toggle(tester, '1');
      expect(find.text('Filtered water'), findsNothing);
    });

    testWidgets('an opened line shows its batches, grouped', (tester) async {
      await _open(tester, await buildReviewableRun());

      await _toggle(tester, '0');

      // Two lines rather than three: the first two batches take the same
      // amount, and a run split into a thousand of them would otherwise
      // render a thousand lines.
      expect(find.text('Batches 1–2'), findsOneWidget);
      expect(find.text('210 g · exactly 200 g'), findsOneWidget);
      expect(find.text('Batch 3'), findsOneWidget);
      expect(find.text('120 g · exactly 100 g'), findsOneWidget);
    });

    testWidgets('a line that is the same in every batch shows them', (
      tester,
    ) async {
      await _open(tester, await buildReviewableRun());

      await _toggle(tester, '4');

      // `liner` is two per batch whatever the run size, so its three
      // batches are one group — and a group count is not a batch count.
      // Gating the section on how many groups the line renders in, rather
      // than how many batches it spans, hides the per-batch amount of
      // every line whose batches are alike: every `perBatch` line always,
      // and every proportional one on a target that divides into full
      // batches. The kitchen weighs out 2 sheet, not 6.
      expect(find.text('Batches 1–3'), findsOneWidget);
      expect(find.text('2 sheet'), findsOneWidget);
      expect(find.text('6 sheet'), findsOneWidget);
    });

    testWidgets('a free-form line shows no batch lines', (tester) async {
      await _open(tester, await buildReviewableRun());

      await _toggle(tester, '3');

      // `salt` spans all three batches and carries an amount in none of
      // them: the calculator fills its per-batch list with nulls. Three
      // lines reading "No calculated amount" under a total that already
      // says so is noise, so a free-form line is skipped by name rather
      // than by its length.
      expect(find.text('Batches 1–3'), findsNothing);
      expect(find.text('No calculated amount'), findsOneWidget);
    });

    testWidgets('a single-batch line shows no batch lines', (tester) async {
      await _open(tester, await buildReviewableRun());

      await _toggle(tester, '1');
      await _toggle(tester, '1/0');

      // Water is one batch of the Dough sub-recipe, so its only batch line
      // would repeat the total immediately above it. It is also why the
      // count cannot come off `run.result.batchPlan`: that is the root's
      // plan, three batches, over a line that has one.
      expect(find.text('Batch 1'), findsNothing);
    });

    testWidgets('a free-form line carries its control unopened', (
      tester,
    ) async {
      await _open(tester, await buildReviewableRun());

      // The one line with no amount at all: an operator who has to open a
      // row to discover that has been told nothing.
      expect(find.byKey(const ValueKey('override-amount-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('override-amount-0')), findsNothing);

      await _toggle(tester, '0');
      expect(find.byKey(const ValueKey('override-amount-0')), findsOneWidget);
    });

    testWidgets('an entered amount sits beside the calculated one', (
      tester,
    ) async {
      await _open(tester, await buildReviewableRun());

      await _toggle(tester, '0');
      await tester.enterText(
        find.byKey(const ValueKey('override-amount-0')),
        '600',
      );
      await tester.pump();

      // Both on screen: the spec keeps the original available for
      // comparison, so the operator's value is added rather than written
      // over the calculation.
      expect(find.text('Using 600 g'), findsOneWidget);
      expect(find.text('540 g · exactly 500 g'), findsOneWidget);
    });

    testWidgets('one override reads alike on both lines that share it', (
      tester,
    ) async {
      // `Starter` is reached twice — once under Dough, once from the run
      // itself — so its `rye` line is two rows under one override key,
      // sharing one draft. Tall enough for both to be built at once.
      await _open(
        tester,
        await buildReviewableRun(),
        viewport: const Size(800, 4000),
      );
      for (final path in ['1', '1/1', '1/1/0', '2', '2/0']) {
        await _toggle(tester, path);
      }
      expect(
        find.byKey(const ValueKey('override-amount-1/1/0')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(const ValueKey('override-amount-2/0')),
        '5',
      );
      await tester.pump();

      // Both lines report the value, and both fields show it. A field
      // seeded from `initialValue` alone reads it once, when its element
      // is created, so the row that was not typed into kept an empty field
      // under a line that said "Using 5 g".
      expect(find.text('Using 5 g'), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('override-amount-1/1/0')),
          matching: find.text('5'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an amount that is not a number is reported', (tester) async {
      await _open(tester, await buildReviewableRun());

      await tester.enterText(
        find.byKey(const ValueKey('override-amount-3')),
        '1.2.3',
      );
      await tester.pump();

      expect(find.text('Enter an amount above zero.'), findsOneWidget);
      expect(find.textContaining('Using'), findsNothing);
    });

    testWidgets('a half-typed amount holds the save back, and names it', (
      tester,
    ) async {
      final runs = FakeProductionRunRepository();
      await _open(tester, await buildReviewableRun(), runs: runs);

      await tester.enterText(
        find.byKey(const ValueKey('override-amount-3')),
        '1.2.3',
      );
      await tester.pump();

      // The action is refused and the notice says which line to fix — a
      // draft outlives the control that shows it, so a notice that only
      // said an amount was wrong would strand an operator who had since
      // collapsed the line.
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save as draft'),
      );
      expect(save.onPressed, isNull);
      expect(
        find.text(
          'Correct the amount entered for Fine sea salt before saving.',
        ),
        findsOneWidget,
      );
      // The field the operator has to correct is still theirs to correct.
      expect(_amountField(tester, '3').enabled, isTrue);

      await tester.enterText(
        find.byKey(const ValueKey('override-amount-3')),
        '12',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save as draft'));
      await tester.pump();
      await tester.pump();

      expect(
        runs.stored['run-1']!.overrides[('bun', 'salt')],
        Quantity.parse('12', Unit.gram),
      );
    });

    testWidgets('a component note is shown without opening its line', (
      tester,
    ) async {
      await _open(tester, await buildReviewableRun());

      // On the free-form line, where it is the only thing that says what
      // the line is for — and on a calculated line too, which is what
      // this second expectation is for: a note rendered only where the
      // override control already is would pass the first and fail here,
      // and two lines can otherwise read the same name over the same
      // ingredient.
      expect(find.text('Season to taste at the end.'), findsOneWidget);
      expect(find.text('Sift before mixing.'), findsOneWidget);
    });

    testWidgets('an override control offers its own line unit', (tester) async {
      await _open(tester, await buildReviewableRun());

      await _toggle(tester, '4');

      // `sheet` is not in the built-in table. A picker built from that
      // table alone would open on a value missing from its own items,
      // which throws.
      expect(find.text('sheet'), findsWidgets);
    });

    testWidgets('choosing a unit re-measures what was entered', (tester) async {
      await _open(tester, await buildReviewableRun());

      await tester.enterText(
        find.byKey(const ValueKey('override-amount-3')),
        '600',
      );
      await tester.pump();
      expect(find.text('Using 600 g'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('override-unit-3')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('kg').last);
      await tester.pumpAndSettle();

      // 600 kg, not 0.6 kg: an override replaces the amount outright, and
      // nothing converts what the operator typed.
      expect(find.text('Using 600 kg'), findsOneWidget);
    });

    testWidgets('warnings are listed until they are acknowledged', (
      tester,
    ) async {
      final run = await buildReviewableRun();
      await _open(tester, run);

      expect(
        find.text('Bread flour in Bun was rounded for display.'),
        findsOneWidget,
      );
      expect(
        find.text('Fine sea salt in Bun has no amount yet.'),
        findsOneWidget,
      );
      expect(
        find.text(
          'One warning has not been acknowledged. Saving now stores a draft.',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(FilledButton, 'Save as draft'),
        findsOneWidget,
      );

      final manual = _warning<ManualComponentWarning>(run);
      await tester.tap(find.byKey(ValueKey('acknowledge-${manual.hashCode}')));
      await tester.pump();

      // Still listed, now marked. And the run is finalizable although the
      // rounding warning has not been acknowledged, because it does not
      // block: the action's own label is where that shows.
      expect(
        find.text('Fine sea salt in Bun has no amount yet.'),
        findsOneWidget,
      );
      expect(find.text('Acknowledged'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Save production run'),
        findsOneWidget,
      );

      // The rounding warning is outstanding on that same screen, in error
      // colour with its action still live. So the notice above the save
      // action may not say the warnings have been dealt with: it reports
      // what saving does and nothing about warnings at all.
      final rounding = _warning<RoundingAdjustedWarning>(run);
      final acknowledge = tester.widget<TextButton>(
        find.byKey(ValueKey('acknowledge-${rounding.hashCode}')),
      );
      expect(acknowledge.onPressed, isNotNull);
      expect(
        find.text('Saving now stores a finished production run.'),
        findsOneWidget,
      );
    });

    testWidgets('an archived dependency is named', (tester) async {
      await _open(tester, await buildArchivedRun());

      expect(find.text('Summer focaccia is archived.'), findsOneWidget);
    });

    testWidgets('a warning naming a recipe offers no line to show', (
      tester,
    ) async {
      await _open(tester, await buildArchivedRun());

      // An archived dependency is raised against the whole recipe, and
      // the line that recipe sits on is one the operator is already
      // looking at. The two component warnings do get the action.
      final archived = _warning<ArchivedDependencyWarning>(
        await buildArchivedRun(),
      );
      expect(find.byKey(ValueKey('reveal-${archived.hashCode}')), findsNothing);
      expect(find.text('Show the line'), findsNothing);
    });

    testWidgets('a warning opens every sub-recipe hiding its line', (
      tester,
    ) async {
      final run = await _buildChainedRun(depth: 8, warnAtTheDeepest: true);
      await _open(tester, run);
      final path = _deepWarningPath(8);
      expect(find.byKey(ValueKey('override-amount-$path')), findsNothing);

      await tester.tap(
        find.byKey(
          ValueKey('reveal-${_warning<ManualComponentWarning>(run).hashCode}'),
        ),
      );
      await tester.pumpAndSettle();

      // Eight levels opened by one tap. Reaching it by hand is eight taps,
      // each on a control the previous tap put on screen.
      expect(find.byKey(ValueKey('override-amount-$path')), findsOneWidget);
    });

    testWidgets('a warning scrolls to the line it names', (tester) async {
      final run = await _buildChainedRun(depth: 8, warnAtTheDeepest: true);
      // A window a run of this size does not fit in, unlike the roomy
      // default: with everything on screen already there is no scrolling
      // to observe, and this is the half of the reveal that the opening
      // above does not cover. Nine levels are not opened by hand here
      // either — in this window the control for each level lands below the
      // fold, which is the operator's own difficulty and would make the
      // setup untappable.
      await _open(tester, run, viewport: const Size(800, 600));
      final target = find.byKey(
        ValueKey('override-amount-${_deepWarningPath(8)}'),
      );

      await tester.tap(
        find.byKey(
          ValueKey('reveal-${_warning<ManualComponentWarning>(run).hashCode}'),
        ),
      );
      await tester.pumpAndSettle();

      // Built *and* in view. Only the first is the widened cache extent's
      // doing — every line exists during a reveal whether or not anything
      // scrolled — so the rect is what says the scroll happened.
      expect(target, findsOneWidget);
      final list = tester.getRect(find.byType(ListView));
      final row = tester.getRect(target);
      expect(row.top, greaterThanOrEqualTo(list.top));
      expect(row.bottom, lessThanOrEqualTo(list.bottom));
    });

    testWidgets('the widened cache extent is put back once it lands', (
      tester,
    ) async {
      final run = await _buildChainedRun(depth: 8, warnAtTheDeepest: true);
      await _open(tester, run, viewport: const Size(800, 600));

      await tester.tap(
        find.byKey(
          ValueKey('reveal-${_warning<ManualComponentWarning>(run).hashCode}'),
        ),
      );
      await tester.pumpAndSettle();

      // Nothing else rebuilds this screen after a reveal — a warning the
      // operator only wanted to look at leaves no edit behind — so an
      // extent that is not put back here is not put back at all. Measured
      // at `cacheExtent=100000.0` on the settled viewport before the reset
      // existed.
      expect(
        tester.widget<ListView>(find.byType(ListView)).scrollCacheExtent,
        isNull,
      );
    });

    testWidgets('saving stores the run and closes the controls', (
      tester,
    ) async {
      final runs = FakeProductionRunRepository();
      await _open(tester, await buildReviewableRun(), runs: runs);

      await tester.tap(find.widgetWithText(FilledButton, 'Save as draft'));
      await tester.pump();
      await tester.pump();

      expect(runs.stored.keys, ['run-1']);
      expect(find.text('This run is stored.'), findsOneWidget);
      // Nothing on screen may still change a run that has been committed:
      // amending a stored snapshot is a use case this screen does not hold.
      expect(_amountField(tester, '3').enabled, isFalse);
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save as draft'),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('a tap in the frame of a save reaches nothing', (tester) async {
      final runs = FakeProductionRunRepository();
      final run = await buildReviewableRun();
      await _open(tester, run, runs: runs);

      final manual = _warning<ManualComponentWarning>(run);
      await tester.tap(find.widgetWithText(FilledButton, 'Save as draft'));
      // Deliberately no pump between the two taps, which is the frame the
      // disabled flags do not yet exist in: the state has moved, the
      // widgets built from it have not, so the acknowledge action on
      // screen is still the enabled one.
      await tester.tap(find.byKey(ValueKey('acknowledge-${manual.hashCode}')));
      await tester.pump();
      await tester.pump();

      // What was stored and what is on screen still say the same thing. A
      // screen that took the second tap would show an acknowledgement the
      // stored snapshot never received, and the snapshot is immutable.
      expect(runs.stored['run-1']!.acknowledgedWarnings, isEmpty);
      expect(find.text('Acknowledged'), findsNothing);
    });

    testWidgets('a failed save is reported and stays pressable', (
      tester,
    ) async {
      await _open(
        tester,
        await buildReviewableRun(),
        runs: UnwritableRunRepository(),
      );

      await tester.tap(find.widgetWithText(FilledButton, 'Save as draft'));
      await tester.pump();
      await tester.pump();

      expect(
        find.text('The production run could not be saved.'),
        findsOneWidget,
      );
      final save = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Save as draft'),
      );
      expect(save.onPressed, isNotNull);
    });

    testWidgets('a deep tree lays out at 320 logical pixels', (tester) async {
      // The narrowest supported window at the largest supported text
      // scale, with two sub-recipes open so a line is indented twice and
      // still carries an override control. A `RenderFlex` that overflows
      // throws here, which is how the warning tile's own overflow — 195
      // pixels of an action the run cannot be finalized without — was
      // found.
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _open(
        tester,
        await buildReviewableRun(),
        viewport: const Size(320, 6000),
      );

      await _toggle(tester, '1');
      await _toggle(tester, '1/1');
      await _toggle(tester, '1/1/0');

      expect(
        find.byKey(const ValueKey('override-amount-1/1/0')),
        findsOneWidget,
      );
    });

    testWidgets('a deeply nested line keeps its expand control', (
      tester,
    ) async {
      // Fifteen sub-recipes deep on the narrowest supported window, which
      // is where an indent that stepped once per level stopped leaving the
      // row anything: 15 levels of 16 pixels is 240 of the 288 the list's
      // padding leaves of 320, and the 12-pixel gap and 48-pixel button
      // that follow no longer fit. A `RenderFlex` that overflows throws
      // here, which is what this asserts — the button on the deepest line
      // is how the operator would open whatever is under it.
      //
      // No text scale set, unlike the depth-3 case above, and deliberately:
      // the depth this breaks at does not move with it. Both `Expanded`
      // halves grow taller rather than wider, and `IconButton`'s 48-pixel
      // minimum is not scaled by text at all.
      await _open(
        tester,
        await _buildChainedRun(depth: 15),
        // Tall enough to build every opened line. A `ListView` lays out
        // nothing past its viewport and cache extent, and a row that was
        // never built cannot overflow — on a short viewport this would
        // pass against either version of the padding.
        viewport: const Size(320, 20000),
      );

      for (var depth = 0; depth < 15; depth++) {
        await _toggle(tester, _chainPath(depth));
      }

      expect(find.byKey(ValueKey('expand-${_chainPath(15)}')), findsOneWidget);
    });

    testWidgets('a typed amount survives the field scrolling away', (
      tester,
    ) async {
      // A window the run outgrows, which is any ordinary one: the
      // free-form line's control sits below five components and two
      // warnings, and a `ListView` destroys a child's element once it
      // scrolls past the cache extent.
      await _open(
        tester,
        await buildReviewableRun(),
        viewport: const Size(400, 600),
      );
      const control = ValueKey('override-amount-3');
      await tester.scrollUntilVisible(find.byKey(control), 200);

      await tester.enterText(find.byKey(control), '12');
      await tester.pump();

      // Load-bearing, the way the production setup screen's twin states
      // it: a focused field keeps itself alive however far it scrolls, so
      // without this the test would prove nothing.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, 2000));
      await tester.pumpAndSettle();

      // The fixture reached the state under test: the element is gone,
      // not merely off screen.
      expect(find.byKey(control), findsNothing);

      await tester.scrollUntilVisible(find.byKey(control), 200);

      // What the operator typed comes back. It has to: the value they
      // entered is the amount the kitchen will actually weigh out, and an
      // emptied field over a run that still carries it is a lie. Read off
      // the controller, which the rebuilt element seeded from the draft:
      // the draft is the durable copy, the controller is not.
      expect(_amountField(tester, '3').controller?.text, '12');
      expect(find.text('Using 12 g'), findsOneWidget);
    });
  });
}
