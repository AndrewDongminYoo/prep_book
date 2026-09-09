import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../../helpers/helpers.dart';
import '../fakes.dart';

/// Longer than the window the page's cubit runs with, so a pump of this
/// length is "the target has gone quiet and the calculation has run". The
/// page builds its own cubit, so these tests take the production window;
/// the test binding's clock advances for free.
const _pastTheDebounce = Duration(milliseconds: 300);

const ValueKey<String> _amountField = ValueKey('target-amount');

final _piece = Unit.count('piece');

/// A recipe whose 400 g maximum splits a run into batches.
Recipe _sheeted() => Recipe(
  id: 'dough',
  revision: 1,
  name: 'Dough',
  baseYield: Quantity.parse('1000', Unit.gram),
  maxBatchYield: Quantity.parse('400', Unit.gram),
  modifiedAt: DateTime.utc(2026, 9, 8),
  components: const [],
);

/// A recipe consuming [dependency]'s output.
Recipe _filled(String dependency) => buildRecipe(
  id: 'filled',
  name: 'Filled bun',
  baseYield: Quantity.parse('1000', Unit.gram),
  components: [buildSubRecipeComponent(dependency)],
);

Widget _screenOver(RecipeRepository storage, {required Recipe recipe}) =>
    ProductionSetupPage(
      startProductionRun: StartProductionRun(
        storage,
        const FixedRunIdSource(),
        const FixedClock(),
      ),
      recipe: recipe,
    );

/// Types [amount] into the target field and waits the calculation out.
Future<void> _enterTarget(WidgetTester tester, String amount) async {
  await tester.enterText(find.byKey(_amountField), amount);
  await tester.pump(_pastTheDebounce);
  await tester.pump();
}

void main() {
  group('ProductionSetupPage', () {
    testWidgets('names the recipe and asks for a target', (tester) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));

      expect(find.text('Dough'), findsOneWidget);
      expect(
        find.text('Enter a target yield to see the batches it takes.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the batches a target takes', (tester) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await _enterTarget(tester, '1000');

      // Two full batches of 400 g and a 200 g remainder, which is three
      // batches. A screen that read the target and not the recipe's
      // maximum would say one.
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2 × 400 g'), findsOneWidget);
      expect(find.text('200 g'), findsOneWidget);
    });

    testWidgets('a target under one batch reports no full batches', (
      tester,
    ) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await _enterTarget(tester, '300');

      // Scaled down: 300 g against a 400 g maximum is one batch and no
      // full one. A row rendered unconditionally reads "0 × 400 g" over
      // the single batch it contradicts, so the label goes with it.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('Full batches'), findsNothing);
      expect(find.text('0 × 400 g'), findsNothing);
      expect(find.text('Last batch'), findsOneWidget);
    });

    testWidgets('compares the run against the base recipe', (tester) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await _enterTarget(tester, '2500');

      expect(find.text('1000 g'), findsOneWidget);
      expect(find.text('2500 g'), findsOneWidget);
      expect(find.text('× 2.5'), findsOneWidget);
    });

    testWidgets('shows a ratio that has no finite decimal', (tester) async {
      final thirds = buildRecipe(
        id: 'dough',
        name: 'Dough',
        baseYield: Quantity.parse('3000', Unit.gram),
      );
      final storage = FakeRecipeRepository()..seed(thirds);

      await tester.pumpApp(_screenOver(storage, recipe: thirds));
      await _enterTarget(tester, '1000');

      // A third of the base recipe. `Rational.toDecimal()` throws on a
      // ratio with no finite decimal form unless it is told how far to go,
      // so a screen that asked for the exact decimal crashes here rather
      // than rounding.
      expect(find.text('× 0.3333'), findsOneWidget);
    });

    testWidgets('reports an amount that is not a number', (tester) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await _enterTarget(tester, 'a lot');

      expect(find.text('Enter an amount above zero.'), findsOneWidget);
    });

    testWidgets('reports a target too large to calculate', (tester) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      // 1001 batches of the recipe's own 400 g maximum.
      await _enterTarget(tester, '400001');

      expect(
        find.text(
          'That target would take more than 1000 batches. '
          'Enter a smaller amount.',
        ),
        findsOneWidget,
      );
      // And not the prompt in its place: a screen that stopped the
      // calculation without saying so tells an operator who has just typed
      // a target to type one.
      expect(
        find.text('Enter a target yield to see the batches it takes.'),
        findsNothing,
      );
    });

    testWidgets('reports a sub-recipe too large in the same words', (
      tester,
    ) async {
      final storage = FakeRecipeRepository()
        ..seed(_filled('grain'))
        ..seed(buildGrainSubRecipe());

      await tester.pumpApp(_screenOver(storage, recipe: _filled('grain')));
      // The root takes this in one batch, so nothing the screen can check
      // by itself refuses it; a tenth of it reaches a sub-recipe produced
      // one gram at a time, which is 1001 batches.
      await _enterTarget(tester, '10001');

      // The same sentence the root's own limit produces above. An arm
      // missing from `_errorMessage` renders the generic failure instead.
      expect(
        find.text(
          'That target would take more than 1000 batches. '
          'Enter a smaller amount.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('offers only units the yield converts to', (tester) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await tester.tap(find.byType(DropdownButtonFormField<Unit>));
      await tester.pumpAndSettle();

      // The whole mass dimension, and none of the other three: a target in
      // millilitres or in portions is one the calculation throws on, and a
      // picker offering it would make the operator find that out by
      // choosing it.
      expect(find.text('kg'), findsOneWidget);
      expect(find.text('mg'), findsOneWidget);
      expect(find.text('ml'), findsNothing);
      expect(find.text('portion'), findsNothing);
    });

    testWidgets('choosing a unit recalculates the run', (tester) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await _enterTarget(tester, '2');
      // 2 g against a 1000 g base yield, until the unit says kilograms.
      expect(find.text('× 0.002'), findsOneWidget);

      await tester.tap(find.byType(DropdownButtonFormField<Unit>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('kg').last);
      await tester.pump(_pastTheDebounce);
      await tester.pump();

      // The comparison is written in the recipe's own unit, so the two
      // rows can be read against each other; the field keeps the
      // kilograms that were chosen.
      expect(find.text('× 2'), findsOneWidget);
      expect(find.text('2000 g'), findsOneWidget);
      expect(find.text('1000 g'), findsOneWidget);
    });

    testWidgets('reports a unit the recipe cannot take', (tester) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      // Through the cubit rather than the picker, which offers no
      // incompatible unit to choose. The rule still has to hold: this is
      // the entry point a later screen, or a unit declared during an edit,
      // would come through.
      unawaited(
        tester
            .element(find.byType(ProductionSetupView))
            .read<ProductionSetupCubit>()
            .targetUnitChanged(_piece),
      );
      await tester.pump(_pastTheDebounce);

      expect(
        find.text(
          'This recipe is measured in g. Choose a unit that '
          'converts to it.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('says a calculation is running', (tester) async {
      final storage = DeferredLookupRecipeRepository(
        FakeRecipeRepository()..seed(_sheeted()),
      );

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await tester.enterText(find.byKey(_amountField), '1000');
      await tester.pump(_pastTheDebounce);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await storage.complete(0);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('2 × 400 g'), findsOneWidget);
    });

    testWidgets('reports a recipe that is no longer stored', (tester) async {
      await tester.pumpApp(
        _screenOver(FakeRecipeRepository(), recipe: _sheeted()),
      );
      await _enterTarget(tester, '1000');

      expect(
        find.text('This recipe is no longer in the library.'),
        findsOneWidget,
      );
    });

    testWidgets('names a sub-recipe that is not stored', (tester) async {
      final storage = FakeRecipeRepository()..seed(_filled('ghost'));

      await tester.pumpApp(_screenOver(storage, recipe: _filled('ghost')));
      await _enterTarget(tester, '2000');

      expect(
        find.text('The sub-recipe "ghost" is not in the library.'),
        findsOneWidget,
      );
    });

    testWidgets('shows the path of a cycle', (tester) async {
      final storage = FakeRecipeRepository()
        ..seed(_filled('cream'))
        ..seed(
          buildRecipe(
            id: 'cream',
            name: 'Cream',
            components: [buildSubRecipeComponent('filled')],
          ),
        );

      await tester.pumpApp(_screenOver(storage, recipe: _filled('cream')));
      await _enterTarget(tester, '2000');

      expect(
        find.text('A recipe cannot depend on itself: filled → cream → filled'),
        findsOneWidget,
      );
    });

    testWidgets('names an archived recipe over its own numbers', (
      tester,
    ) async {
      final storage = FakeRecipeRepository()
        ..seed(_filled('cream'))
        ..seed(buildRecipe(id: 'cream', name: 'Cream', isArchived: true));

      await tester.pumpApp(_screenOver(storage, recipe: _filled('cream')));
      await _enterTarget(tester, '2000');

      // The calculation succeeded, so the numbers are on screen; the run
      // still may not start, and the screen says which recipe is why.
      expect(
        find.text('Cream is archived. Restore it before running production.'),
        findsOneWidget,
      );
      expect(find.text('2000 g'), findsOneWidget);
    });

    testWidgets('reports a stored recipe measured in another unit', (
      tester,
    ) async {
      // The form was laid out from a revision yielding grams; the stored
      // revision yields trays. Nothing the screen can pre-empt — it is the
      // calculation that reads the current revision.
      final storage = FakeRecipeRepository()
        ..seed(
          buildRecipe(
            id: 'dough',
            name: 'Dough',
            baseYield: Quantity.parse('2', Unit.namedYield('tray')),
          ),
        );

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await _enterTarget(tester, '1000');

      expect(
        find.text('The saved recipe is measured in tray, not g.'),
        findsOneWidget,
      );
    });

    testWidgets('reports a read it cannot explain', (tester) async {
      final storage = DeferredLookupRecipeRepository(
        FakeRecipeRepository()..seed(_sheeted()),
      );

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await tester.enterText(find.byKey(_amountField), '1000');
      await tester.pump(_pastTheDebounce);
      storage.fail(0);
      await tester.pump();

      // Nothing the operator can act on, so the screen says only that it
      // failed; `AppBlocObserver` is where the reason is logged.
      expect(
        find.text('The production run could not be calculated.'),
        findsOneWidget,
      );
    });

    testWidgets('renders Continue with nowhere to go', (tester) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await _enterTarget(tester, '1000');

      // Pins the rendering this slice chose, not a validation rule: the
      // production result screen does not exist, so the action is disabled
      // whatever the target says — the way the library screen's Production
      // Run action was rendered before it became live. What decides
      // whether it may be pressed is `ProductionSetupState.canContinue`,
      // which `production_setup_cubit_test.dart` pins.
      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Continue'),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('seeds the target field from the state it re-enters on', (
      tester,
    ) async {
      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await _enterTarget(tester, '1000');

      // The mechanism the scroll test below exercises, asserted where no
      // layout arithmetic can hide it: the field carries what to show when
      // it is built from nothing, so the cubit's target is what a rebuilt
      // element comes back holding. A field that only kept the text in its
      // own element state has no `initialValue` to read at all.
      final field = tester.widget<TextFormField>(find.byKey(_amountField));
      expect(field.initialValue, '1000');
      expect(field.controller, isNull);
    });

    testWidgets('keeps the typed target when the field scrolls away', (
      tester,
    ) async {
      // A narrow, short window at a large text scale — a landscape phone
      // with the keyboard up, at the accessibility sizes this project
      // supports. It only makes the form taller than the viewport
      // deterministically; the same destruction happens on any window the
      // form outgrows.
      tester.view
        ..physicalSize = const Size(320, 400)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      final storage = FakeRecipeRepository()..seed(_sheeted());

      await tester.pumpApp(_screenOver(storage, recipe: _sheeted()));
      await _enterTarget(tester, '1000');
      expect(find.text('2 × 400 g'), findsOneWidget);

      // Load-bearing. `EditableTextState.wantKeepAlive` is the field's own
      // focus, so a focused field is held mounted however far it scrolls
      // and this test would prove nothing.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await tester.pumpAndSettle();

      // The fixture reached the state under test: the element is gone, not
      // merely off screen. Without this the test passes on a window the
      // field never left.
      expect(find.byKey(_amountField), findsNothing);

      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pumpAndSettle();

      // What the operator typed is still there. It has to be: the run
      // below it was calculated from that target and is still on screen,
      // so an empty field would put a blank target over a live batch plan.
      expect(find.byKey(_amountField), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
      expect(find.text('2 × 400 g'), findsOneWidget);
    });
  });
}
