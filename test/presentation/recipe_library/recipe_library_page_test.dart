import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../../helpers/helpers.dart';
import '../fakes.dart';

const _emptyMessage = 'No recipes yet.';
const _noMatchMessage = 'No recipes match your search.';
const _onlyArchivedMessage =
    'Every recipe here is archived. Turn the switch on to see them.';
const _errorMessage = 'The recipe library could not be loaded.';

/// Longer than the debounce the page's cubit runs with, so a pump of this
/// length is "the field has gone quiet and the search has read".
///
/// The page constructs its own cubit, so these tests take the production
/// window rather than a collapsed one — which is the point: the clock here
/// is the test binding's, so waiting it out is free, and a default of
/// `Duration.zero` would fail the test below that types across three bare
/// pumps.
const _pastTheDebounce = Duration(milliseconds: 300);

/// An iPhone SE in landscape, in physical pixels, paired with a device
/// pixel ratio of one so the numbers below are logical pixels too.
const _shortViewport = Size(568, 320);

/// Roughly what a software keyboard takes off the bottom of that screen.
const _keyboardInset = 190.0;

/// The lowest point on it the operator can still see.
final double _aboveTheKeyboard = _shortViewport.height - _keyboardInset;

/// A display cutout down one long edge, as landscape reports it on both
/// sides, and the home indicator along the bottom.
const _cutoutInset = 44.0;
const _homeIndicatorInset = 21.0;

Widget _libraryOver(
  RecipeRepository recipes, {
  IngredientRepository? ingredients,
}) => RecipeLibraryPage(
  listLibrary: ListLibrary(recipes),
  searchLibrary: SearchLibrary(recipes),
  editor: buildEditorLauncher(
    recipes,
    ingredients ?? FakeIngredientRepository(),
  ),
);

/// The screen's own scroll position.
///
/// `.first` because the search field carries a scrollable of its own; the
/// screen's is the outer one.
ScrollPosition _screenScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// The rows the list is showing, in the order they are laid out.
List<String> _rowTitles(WidgetTester tester) => [
  for (final tile in tester.widgetList<ListTile>(find.byType(ListTile)))
    if (tile.title case final Text title) title.data!,
];

void main() {
  group('RecipeLibraryPage', () {
    late FakeRecipeRepository recipes;

    setUp(() {
      recipes = FakeRecipeRepository()
        ..seed(
          buildRecipe(
            id: 'r-a',
            name: 'Ciabatta',
            modifiedAt: DateTime.utc(2026, 9, 11),
            baseYield: Quantity.parse('1000', Unit.gram),
          ),
        )
        ..seed(
          buildRecipe(
            id: 'r-b',
            name: 'Croissant dough',
            modifiedAt: DateTime.utc(2026, 9, 13),
            baseYield: Quantity.parse('24', Unit.count('piece')),
          ),
        );
    });

    testWidgets('lists each recipe with its base yield, newest first', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      // The switch is a ListTile too, so the recipe rows are the tail.
      expect(_rowTitles(tester), [
        'Show archived recipes',
        'Croissant dough',
        'Ciabatta',
      ]);
      expect(find.text('24 piece'), findsOneWidget);
      expect(find.text('1000 g'), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(find.text(_errorMessage), findsNothing);
    });

    testWidgets('renders Production Run per row, disabled', (tester) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      final actions = tester.widgetList<FilledButton>(
        find.widgetWithText(FilledButton, 'Production Run'),
      );
      expect(actions, hasLength(2));
      expect(actions.every((button) => button.onPressed == null), isTrue);
    });

    testWidgets('typing filters the rows, then reports no matches', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'cia');
      await tester.pump(_pastTheDebounce);
      await tester.pump();

      expect(find.text('Ciabatta'), findsOneWidget);
      expect(find.text('Croissant dough'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(_pastTheDebounce);
      await tester.pump();

      expect(find.text(_noMatchMessage), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(find.text(_onlyArchivedMessage), findsNothing);
      expect(find.text(_errorMessage), findsNothing);
      expect(find.text('Ciabatta'), findsNothing);
    });

    testWidgets('shows the empty message when the library holds nothing', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(FakeRecipeRepository()));
      await tester.pump();

      expect(find.text(_emptyMessage), findsOneWidget);
      expect(find.text(_noMatchMessage), findsNothing);
      expect(find.text(_onlyArchivedMessage), findsNothing);
      expect(find.text(_errorMessage), findsNothing);
    });

    testWidgets(
      'a library holding only archived recipes points at the switch',
      (tester) async {
        final archivedOnly = FakeRecipeRepository()
          ..seed(
            buildRecipe(id: 'r-c', name: 'Summer focaccia', isArchived: true),
          );

        await tester.pumpApp(_libraryOver(archivedOnly));
        await tester.pump();

        // Rejects picking the message on `query.isEmpty` alone: that reads
        // "No recipes yet." over a library that holds one, and points away
        // from the switch that would show it.
        expect(find.text(_onlyArchivedMessage), findsOneWidget);
        expect(find.text(_emptyMessage), findsNothing);
        expect(find.text(_noMatchMessage), findsNothing);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();

        expect(find.text('Summer focaccia'), findsOneWidget);
        expect(find.text(_onlyArchivedMessage), findsNothing);
      },
    );

    testWidgets('a search whose only match is archived says the same', (
      tester,
    ) async {
      recipes.seed(
        buildRecipe(
          id: 'r-c',
          name: 'Summer focaccia',
          isArchived: true,
          modifiedAt: DateTime.utc(2026, 9, 15),
        ),
      );

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'focaccia');
      await tester.pump(_pastTheDebounce);
      await tester.pump();

      // The hidden rows are the query's own matches, so this must be
      // decided before the query is, or the screen claims nothing matched
      // when something did.
      expect(find.text(_onlyArchivedMessage), findsOneWidget);
      expect(find.text(_noMatchMessage), findsNothing);
    });

    testWidgets(
      'the whole screen scrolls when the keyboard leaves it almost no room',
      (tester) async {
        // An iPhone SE in landscape with the keyboard up. The scaffold
        // takes the inset off the body, so what is left is shorter than
        // the search field, the switch and the divider stacked — the
        // arrangement this screen puts above its rows.
        tester.view.physicalSize = _shortViewport;
        tester.view.devicePixelRatio = 1;
        tester.view.viewInsets = const FakeViewPadding(bottom: _keyboardInset);
        addTearDown(tester.view.reset);

        await tester.pumpApp(_libraryOver(recipes));
        await tester.pump();

        // Rejects a fixed column with the list in an `Expanded`: the three
        // rows above it are taller than the body, so the list is clamped to
        // nothing and the column overflows.
        expect(tester.takeException(), isNull);

        final scroll = _screenScroll(tester);
        expect(scroll.maxScrollExtent, greaterThan(0));

        scroll.jumpTo(scroll.maxScrollExtent);
        await tester.pump();

        // Measured against the keyboard's edge, not the scroll view's own
        // bottom, and that is the half that does the work here. Adding
        // `resizeToAvoidBottomInset: false` also stops the overflow and
        // also leaves a scrolling list — it keeps the body at full height
        // and parks the last rows underneath the keyboard, where the
        // operator cannot see them. Measured this way, that variant fails.
        final row = tester.getRect(find.widgetWithText(ListTile, 'Ciabatta'));
        expect(row.top, greaterThanOrEqualTo(0));
        expect(row.bottom, lessThanOrEqualTo(_aboveTheKeyboard));
      },
    );

    testWidgets('keeps the field and the rows clear of the display insets', (
      tester,
    ) async {
      // The same landscape phone, this time with a cutout down its long
      // edges and the home indicator along the bottom, and no keyboard.
      tester.view.physicalSize = _shortViewport;
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(
        left: _cutoutInset,
        right: _cutoutInset,
        bottom: _homeIndicatorInset,
      );
      addTearDown(tester.view.reset);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      // Rejects a body that is a bare `CustomScrollView`: the scaffold
      // takes only the top padding out of the body's media query — the app
      // bar consumes that one — and neither a scroll view nor the field's
      // own `EdgeInsets` applies what is left, so the field would lay out
      // 16 pixels in, under the cutout.
      final field = tester.getRect(find.byType(TextField));
      expect(field.left, greaterThanOrEqualTo(_cutoutInset));
      expect(
        field.right,
        lessThanOrEqualTo(_shortViewport.width - _cutoutInset),
      );

      final scroll = _screenScroll(tester);
      // Without this the bottom assertion below would also hold for a list
      // short enough to end above the indicator on its own.
      expect(scroll.maxScrollExtent, greaterThan(0));
      scroll.jumpTo(scroll.maxScrollExtent);
      await tester.pump();

      // Scrolled to the end, so the last row sits against the bottom of the
      // viewport. Where that edge is is the whole question: inset, it is
      // above the home indicator; not inset, the row is underneath it.
      final row = tester.getRect(find.widgetWithText(ListTile, 'Ciabatta'));
      expect(row.left, greaterThanOrEqualTo(_cutoutInset));
      expect(row.right, lessThanOrEqualTo(_shortViewport.width - _cutoutInset));
      expect(
        row.bottom,
        lessThanOrEqualTo(_shortViewport.height - _homeIndicatorInset),
      );
    });

    testWidgets('hides archived recipes until the switch is on', (
      tester,
    ) async {
      recipes.seed(
        buildRecipe(
          id: 'r-c',
          name: 'Summer focaccia',
          isArchived: true,
          modifiedAt: DateTime.utc(2026, 9, 15),
        ),
      );

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(find.text('Summer focaccia'), findsNothing);
      expect(find.text('Ciabatta'), findsOneWidget);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      expect(find.text('Summer focaccia'), findsOneWidget);
      expect(find.text('Ciabatta'), findsOneWidget);
      expect(find.textContaining('Archived'), findsOneWidget);
    });

    testWidgets('a row still lays out at a split-window width', (tester) async {
      // The narrow end of what the design document asks the screen to
      // survive: an Android split-screen pane, an iPad Slide Over, an
      // iPhone SE in portrait. Every other viewport in this file is 568
      // wide or more, which is above where this breaks.
      //
      // Rejects a `ListTile` whose `trailing` holds the edit action beside
      // the Production Run button. `ListTile` measures its trailing slot
      // against the whole tile width and asserts when it fills it, and a
      // `Row` that overflows clamps to exactly that width — so the second
      // control cannot be made to shrink out of the way, and its 48 pixels
      // come straight off the row's headroom.
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Moved slot, not dropped action: the row still offers a labelled
      // edit control, which is what the design document asks of every
      // secondary action.
      expect(find.byTooltip('Edit'), findsNWidgets(2));
    });
  });

  group('RecipeLibraryPage, opening the editor', () {
    late FakeRecipeRepository recipes;

    setUp(() {
      recipes = FakeRecipeRepository()
        ..seed(
          buildRecipe(
            id: 'r-a',
            name: 'Ciabatta',
            modifiedAt: DateTime.utc(2026, 9, 11),
          ),
        );
    });

    testWidgets('the create action stores a recipe and lists it', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.tap(find.byTooltip('New recipe'));
      await tester.pumpAndSettle();

      expect(find.text('New recipe'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('recipe-name')),
        'Summer focaccia',
      );
      await tester.enterText(find.byKey(const ValueKey('base-yield')), '2000');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      // Back on the library, listing what the editor stored: the row is
      // only there if the screen read again when the editor closed.
      expect(find.byType(RecipeLibraryPage), findsOneWidget);
      expect(find.text('Summer focaccia'), findsOneWidget);
      expect((await recipes.findLatest('summer-focaccia'))!.revision, 1);
    });

    testWidgets('a row opens its own recipe and saves the next revision', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit_outlined).last);
      await tester.pumpAndSettle();

      // The row's own recipe, filled in — the same editor the create
      // action opens, because the save is the same call either way.
      expect(find.text('Edit recipe'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Ciabatta'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('recipe-name')),
        'Ciabatta loaf',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('Ciabatta loaf'), findsOneWidget);
      expect((await recipes.findLatest('r-a'))!.revision, 2);
    });

    testWidgets('leaving the editor without saving changes nothing', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.edit_outlined).last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recipe-name')),
        'Discarded',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Ciabatta'), findsOneWidget);
      expect(find.text('Discarded'), findsNothing);
      expect((await recipes.findLatest('r-a'))!.revision, 1);
    });
  });

  group('RecipeLibraryPage, against reads completed by hand', () {
    late DeferredRecipeRepository repository;

    setUp(() => repository = DeferredRecipeRepository());

    testWidgets('shows a spinner until the first read answers', (tester) async {
      await tester.pumpApp(_libraryOver(repository));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(find.text(_errorMessage), findsNothing);

      repository.complete(0, [buildRecipe(id: 'r-a', name: 'Ciabatta')]);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Ciabatta'), findsOneWidget);
    });

    testWidgets('shows the error message, and retry reads again', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(repository));
      await tester.pump();
      repository.fail(0);
      await tester.pump();

      expect(find.text(_errorMessage), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(find.text(_noMatchMessage), findsNothing);
      expect(find.text(_onlyArchivedMessage), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();
      repository.complete(1, [buildRecipe(id: 'r-a', name: 'Ciabatta')]);
      await tester.pump();

      expect(find.text(_errorMessage), findsNothing);
      expect(find.text('Ciabatta'), findsOneWidget);
    });

    testWidgets('retry re-runs the search, not the whole library', (
      tester,
    ) async {
      final ciabatta = buildRecipe(id: 'r-a', name: 'Ciabatta');
      final croissant = buildRecipe(id: 'r-b', name: 'Croissant dough');

      await tester.pumpApp(_libraryOver(repository));
      await tester.pump();
      repository.complete(0, [ciabatta, croissant]);
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'cia');
      await tester.pump(_pastTheDebounce);
      repository.fail(1);
      // Two frames: the emit the failed read produces lands on the first,
      // the draw happens on the second. The tests above get away with one
      // because they are sitting on a spinner, which keeps a frame
      // scheduled; this one is sitting on a static list.
      await tester.pump();
      await tester.pump();
      expect(find.text(_errorMessage), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();

      // A retry that reads is a retry that should say so.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      repository.complete(2, [ciabatta, croissant]);
      await tester.pump();

      // The field is uncontrolled, so it still shows what was typed. A
      // retry through `load()` would list the whole library underneath it.
      expect(find.widgetWithText(TextField, 'cia'), findsOneWidget);
      expect(find.text('Ciabatta'), findsOneWidget);
      expect(find.text('Croissant dough'), findsNothing);
    });

    testWidgets('a word typed into the field reads once, not per letter', (
      tester,
    ) async {
      final ciabatta = buildRecipe(id: 'r-a', name: 'Ciabatta');
      final croissant = buildRecipe(id: 'r-b', name: 'Croissant dough');

      await tester.pumpApp(_libraryOver(repository));
      await tester.pump();
      repository.complete(0, [ciabatta, croissant]);
      await tester.pump();

      // Three keystrokes with no clock advance between them: a bare `pump`
      // draws a frame without elapsing the window.
      await tester.enterText(find.byType(TextField), 'c');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'ci');
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'cia');
      await tester.pump();

      // Rejects both the undebounced screen and a zero-length default: the
      // opening read is the only one so far, because every letter's read
      // was still waiting when the next letter replaced it.
      expect(repository.readCount, 1);

      await tester.pump(_pastTheDebounce);

      expect(repository.readCount, 2);
      repository.complete(1, [ciabatta, croissant]);
      await tester.pump();
      await tester.pump();

      expect(find.text('Ciabatta'), findsOneWidget);
      expect(find.text('Croissant dough'), findsNothing);
    });
  });
}
