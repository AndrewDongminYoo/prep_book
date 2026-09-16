import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../../helpers/helpers.dart';
import '../fakes.dart';

const _emptyMessage =
    'No recipes yet. Create your first recipe to get started.';
const _noMatchMessage = 'No recipes match your search or filter.';
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
  LibraryBackupLauncher? libraryBackup,
  ProductionHistoryLauncher? history,
  bool restored = false,
  LibraryBackupFailureKind? restoreFailure,
}) => RecipeLibraryPage(
  listLibrary: ListLibrary(recipes),
  searchLibrary: SearchLibrary(recipes),
  archiveRecipe: ArchiveRecipe(recipes),
  duplicateRecipe: DuplicateRecipe(recipes, const FixedClock()),
  editor: buildEditorLauncher(
    recipes,
    ingredients ?? FakeIngredientRepository(),
  ),
  production: buildProductionLauncher(recipes),
  history: history ?? _historyLauncher(),
  libraryBackup: libraryBackup ?? _backupLauncher(),
  restored: restored,
  restoreFailure: restoreFailure,
);

ProductionHistoryLauncher _historyLauncher() {
  final runs = FakeProductionRunRepository();
  return ProductionHistoryLauncher(
    listHistory: ListProductionHistory(runs),
    openProductionRun: OpenProductionRun(runs),
    productionSheet: ProductionSheetLauncher(platform: _HistorySheetPlatform()),
  );
}

LibraryBackupLauncher _backupLauncher({
  LibraryBackupGateway? gateway,
  LibraryBackupPlatform? platform,
}) {
  final activeGateway = gateway ?? _BackupGateway();
  return LibraryBackupLauncher(
    createBackup: CreateLibraryBackup(activeGateway),
    restoreBackup: RestoreLibraryBackup(activeGateway),
    platform: platform ?? _BackupPlatform(),
  );
}

final class _BackupGateway implements LibraryBackupGateway {
  int createCalls = 0;
  int restoreCalls = 0;

  @override
  Future<LibraryBackupFile> create() async {
    createCalls++;
    return LibraryBackupFile(
      bytes: Uint8List.fromList([1]),
      suggestedName: 'backup.prepbook',
    );
  }

  @override
  Future<void> restore(Uint8List archiveBytes) async {
    restoreCalls++;
  }
}

final class _BackupPlatform implements LibraryBackupPlatform {
  Uint8List? pickedBytes;
  bool saveResult = false;

  @override
  Future<Uint8List?> pickBackup() async => pickedBytes;

  @override
  Future<bool> saveBackup(LibraryBackupFile backup) async => saveResult;
}

final class _HistorySheetPlatform implements ProductionSheetPlatform {
  @override
  Future<Uint8List> loadFontBytes() async => Uint8List(0);

  @override
  Widget preview({
    required Uint8List bytes,
    required Widget loading,
    required Widget Function(Object error) onError,
  }) => const SizedBox.shrink();

  @override
  Future<bool> print({required Uint8List bytes, required String name}) async =>
      true;

  @override
  Future<bool> share({
    required Uint8List bytes,
    required String filename,
  }) async => true;
}

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

Finder _inLibraryList(Finder matching) => find.descendant(
  of: find.byKey(const PageStorageKey<String>('recipe-list-pane')),
  matching: matching,
);

/// The create action the empty state offers, as distinct from the app bar's
/// icon, which is found by its tooltip.
final Finder _emptyLibraryCreateButton = find.widgetWithText(
  FilledButton,
  'New recipe',
);

ListTile _recipeTile(WidgetTester tester, String name) => tester
    .widget<ListTile>(_inLibraryList(find.widgetWithText(ListTile, name)));

ScrollPosition _detailScroll(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('recipe-detail-pane')),
            matching: find.byType(Scrollable),
          )
          .first,
    )
    .position;

/// The row menus, in row order. Told apart from the app bar's backup menu
/// by tooltip, and matched on the button itself rather than through
/// `find.byTooltip`, which lands on the 40-pixel `Tooltip` inside the
/// button and would measure the icon rather than the tap target.
final Finder _rowMenus = _inLibraryList(
  find.byWidgetPredicate(
    (widget) => widget is PopupMenuButton && widget.tooltip == 'More actions',
  ),
);

/// [label] as an item of an open menu, as distinct from the same label on
/// a detail-pane button, which the default viewport is wide enough to show.
Finder _menuItem(String label) => find.descendant(
  of: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
  matching: find.text(label),
);

/// Opens the first row's menu and taps [item] in it.
Future<void> _pickFromFirstRowMenu(WidgetTester tester, String item) async {
  await tester.tap(_rowMenus.first);
  await tester.pumpAndSettle();
  await tester.tap(_menuItem(item));
  await tester.pumpAndSettle();
}

/// A library with two categories, one of them holding an archived recipe,
/// and one recipe with no category at all — the shape every chip case
/// needs at once.
FakeRecipeRepository _categorisedLibrary() => FakeRecipeRepository()
  ..seed(
    buildRecipe(
      id: 'r-loaf',
      name: 'Country loaf',
      category: 'Breads',
      modifiedAt: DateTime.utc(2026, 9, 14),
    ),
  )
  ..seed(
    buildRecipe(
      id: 'r-focaccia',
      name: 'Summer focaccia',
      category: 'Breads',
      isArchived: true,
      modifiedAt: DateTime.utc(2026, 9, 13),
    ),
  )
  ..seed(
    buildRecipe(
      id: 'r-dough',
      name: 'Croissant dough',
      category: 'Doughs',
      modifiedAt: DateTime.utc(2026, 9, 12),
    ),
  )
  ..seed(
    buildRecipe(
      id: 'r-cream',
      name: 'Pastry cream',
      modifiedAt: DateTime.utc(2026, 9, 11),
    ),
  );

/// The chip labelled [label].
Finder _chip(String label) => find.widgetWithText(ChoiceChip, label);

bool _isSelected(WidgetTester tester, String label) =>
    tester.widget<ChoiceChip>(_chip(label)).selected;

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
      expect(_inLibraryList(find.text('24 piece')), findsOneWidget);
      expect(_inLibraryList(find.text('1000 g')), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(find.text(_errorMessage), findsNothing);
    });

    testWidgets('the app-bar history action opens production history', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.tap(find.byTooltip('Production history'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(ProductionHistoryPage), findsOneWidget);
      expect(find.text('No production runs yet.'), findsOneWidget);
    });

    testWidgets('backup menu exposes both library operations', (tester) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.tap(find.byTooltip('Library backup'));
      await tester.pumpAndSettle();

      expect(find.text('Back up library'), findsOneWidget);
      expect(find.text('Restore backup'), findsOneWidget);
      expect(find.byTooltip('New recipe'), findsOneWidget);
    });

    testWidgets('backup keeps query, selection, and scroll position', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(840, 600)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final many = FakeRecipeRepository();
      for (var index = 0; index < 20; index++) {
        many.seed(
          buildRecipe(
            id: 'recipe-$index',
            name: 'Recipe $index',
            modifiedAt: DateTime.utc(
              2026,
              9,
              13,
            ).subtract(Duration(minutes: index)),
          ),
        );
      }
      final gateway = _BackupGateway();
      final platform = _BackupPlatform()..saveResult = true;
      await tester.pumpApp(
        _libraryOver(
          many,
          libraryBackup: _backupLauncher(gateway: gateway, platform: platform),
        ),
      );
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Recipe');
      await tester.pump(_pastTheDebounce);
      await tester.pump();
      await tester.tap(_inLibraryList(find.text('Recipe 1')));
      await tester.pump();
      final scroll = _screenScroll(tester);
      expect(scroll.maxScrollExtent, greaterThan(80));
      scroll.jumpTo(80);
      await tester.pump();
      final beforeOffset = scroll.pixels;

      await tester.tap(find.byTooltip('Library backup'));
      await tester.pumpAndSettle();
      expect(
        _screenScroll(tester).pixels,
        beforeOffset,
        reason: 'opening the backup menu must preserve list position',
      );
      await tester.tap(find.text('Back up library'));
      expect(
        _screenScroll(tester).pixels,
        beforeOffset,
        reason: 'selecting backup must preserve list position',
      );
      await tester.pump();
      expect(
        _screenScroll(tester).pixels,
        beforeOffset,
        reason: 'opening backup dialog must preserve list position',
      );
      await tester.pumpAndSettle();

      expect(gateway.createCalls, 1);
      expect(_screenScroll(tester).pixels, beforeOffset);
      expect(_recipeTile(tester, 'Recipe 1').selected, isTrue);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('recipe-detail-pane')),
          matching: find.text('Recipe 1'),
        ),
        findsOneWidget,
      );
      _screenScroll(tester).jumpTo(0);
      await tester.pump();
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'Recipe',
      );
    });

    testWidgets('restored root shows one completion notice', (tester) async {
      await tester.pumpApp(_libraryOver(recipes, restored: true));
      await tester.pump();
      await tester.pump();

      expect(find.text('Library restored from backup.'), findsOneWidget);
    });

    testWidgets('recovered root shows one restore failure notice', (
      tester,
    ) async {
      await tester.pumpApp(
        _libraryOver(
          recipes,
          restoreFailure: LibraryBackupFailureKind.restoreFailed,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.text(
          'The backup could not be restored. '
          'Your current library is unchanged.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Production Run opens setup over that row', (tester) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      final actions = _inLibraryList(
        find.widgetWithText(FilledButton, 'Production Run'),
      );
      expect(actions, findsNWidgets(2));
      await tester.tap(actions.first);
      await tester.pumpAndSettle();

      // The row's own recipe, not whichever the library happened to read
      // first: the rows list newest first, so the top action is the
      // croissant dough's.
      expect(find.text('Production run'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ProductionSetupPage),
          matching: find.text('Croissant dough'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('an archived row keeps its Production Run action', (
      tester,
    ) async {
      final archivedOnly = FakeRecipeRepository()
        ..seed(
          buildRecipe(id: 'r-c', name: 'Summer focaccia', isArchived: true),
        );

      await tester.pumpApp(_libraryOver(archivedOnly));
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      // Live, not disabled. An archived recipe cannot be run, but the row
      // is the wrong place to say so: the reason may be a sub-recipe no
      // row ever showed, and the production screen is what names it. A row
      // that disabled the action instead would dead-end the operator with
      // nothing telling them why.
      await tester.tap(
        _inLibraryList(find.widgetWithText(FilledButton, 'Production Run')),
      );
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(ProductionSetupPage),
          matching: find.text('Summer focaccia'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('typing filters the rows, then reports no matches', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'cia');
      await tester.pump(_pastTheDebounce);
      await tester.pump();

      expect(_inLibraryList(find.text('Ciabatta')), findsOneWidget);
      expect(find.text('Croissant dough'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(_pastTheDebounce);
      await tester.pump();

      expect(find.text(_noMatchMessage), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(find.text(_onlyArchivedMessage), findsNothing);
      expect(find.text(_errorMessage), findsNothing);
      expect(find.text('Ciabatta'), findsNothing);
      // The next step here is the search field, not a new recipe.
      expect(_emptyLibraryCreateButton, findsNothing);
    });

    testWidgets('clearing a no-match search keeps the create action away '
        'until the read lands', (tester) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(_pastTheDebounce);
      await tester.pump();
      expect(find.text(_noMatchMessage), findsOneWidget);

      // The field is empty at once, but the rows on screen still answer
      // "zzz" until the debounce and the read have run. In that window the
      // library is not unfilled, so the empty state must keep describing
      // the result it shows rather than offer a new recipe over a library
      // that holds two.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      expect(find.text(_noMatchMessage), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(_emptyLibraryCreateButton, findsNothing);

      await tester.pump(_pastTheDebounce);
      await tester.pump();

      expect(_inLibraryList(find.text('Ciabatta')), findsOneWidget);
      expect(find.text(_noMatchMessage), findsNothing);
      expect(_emptyLibraryCreateButton, findsNothing);
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

    testWidgets('an empty library offers the create action under the message', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(FakeRecipeRepository()));
      await tester.pump();

      // A fresh install lands here with nothing to search and nothing to
      // unhide, so the message alone would leave the app bar's icon as the
      // only way forward.
      expect(_emptyLibraryCreateButton, findsOneWidget);
    });

    testWidgets("the empty library's create action stores a recipe and lists "
        'it', (tester) async {
      final recipes = FakeRecipeRepository();
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.tap(_emptyLibraryCreateButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('recipe-name')), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('recipe-name')),
        'First loaf',
      );
      await tester.enterText(find.byKey(const ValueKey('base-yield')), '800');
      await tester.tap(find.byType(DropdownButtonFormField<Unit>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('g').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      // The same launcher as the app bar's icon, so the library reads again
      // when the editor closes: the row is listed and the empty state, with
      // its button, is gone. Scoped to the list because, at this width, the
      // sole recipe is also the detail pane's selection.
      expect(find.byType(RecipeLibraryPage), findsOneWidget);
      expect(_inLibraryList(find.text('First loaf')), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(_emptyLibraryCreateButton, findsNothing);
      expect((await recipes.findLatest('first-loaf'))!.revision, 1);
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
        // The next step here is the switch, not a new recipe.
        expect(_emptyLibraryCreateButton, findsNothing);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pump();

        expect(_inLibraryList(find.text('Summer focaccia')), findsOneWidget);
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
      expect(_inLibraryList(find.text('Ciabatta')), findsOneWidget);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.drag(
        find.byKey(const PageStorageKey<String>('recipe-list-pane')),
        const Offset(0, -1000),
      );
      await tester.pumpAndSettle();

      expect(_inLibraryList(find.text('Summer focaccia')), findsOneWidget);
      expect(_inLibraryList(find.text('Ciabatta')), findsOneWidget);
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

    testWidgets('stacks row actions at 200 percent in a narrow master pane', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(600, 900)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(find.byKey(const ValueKey('recipe-detail-pane')), findsOneWidget);
      expect(_recipeTile(tester, 'Croissant dough').trailing, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('stacks row actions in a narrow master pane', (tester) async {
      tester.view
        ..physicalSize = const Size(600, 900)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(find.byKey(const ValueKey('recipe-detail-pane')), findsOneWidget);
      expect(_recipeTile(tester, 'Croissant dough').trailing, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'responsive layout keeps the selected recipe across width changes',
      (tester) async {
        tester.view
          ..physicalSize = const Size(599, 900)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);

        await tester.pumpApp(_libraryOver(recipes));
        await tester.pump();

        expect(find.byKey(const ValueKey('recipe-detail-pane')), findsNothing);
        expect(_recipeTile(tester, 'Croissant dough').selected, isFalse);

        await tester.tapAt(
          tester.getCenter(_inLibraryList(find.text('Ciabatta'))),
        );
        await tester.pump();
        expect(_recipeTile(tester, 'Ciabatta').selected, isFalse);

        tester.view.physicalSize = const Size(600, 900);
        await tester.pump();

        final detailPane = find.byKey(const ValueKey('recipe-detail-pane'));
        expect(detailPane, findsOneWidget);
        expect(
          find.descendant(
            of: detailPane,
            matching: find.text('Croissant dough'),
          ),
          findsOneWidget,
        );
        expect(_recipeTile(tester, 'Croissant dough').selected, isTrue);

        await tester.tapAt(
          tester.getCenter(_inLibraryList(find.text('Ciabatta'))),
        );
        await tester.pump();

        expect(
          find.descendant(of: detailPane, matching: find.text('Ciabatta')),
          findsOneWidget,
        );
        expect(_recipeTile(tester, 'Ciabatta').selected, isTrue);

        tester.view.physicalSize = const Size(599, 900);
        await tester.pump();
        expect(detailPane, findsNothing);

        tester.view.physicalSize = const Size(840, 900);
        await tester.pump();
        expect(
          find.descendant(of: detailPane, matching: find.text('Ciabatta')),
          findsOneWidget,
        );
      },
    );

    testWidgets('keeps the visible search query across width changes', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(599, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'cia');
      await tester.pump(_pastTheDebounce);
      await tester.pump();
      expect(find.text('Ciabatta'), findsOneWidget);

      tester.view.physicalSize = const Size(600, 900);
      await tester.pump();

      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        'cia',
      );
      expect(find.text('Ciabatta'), findsWidgets);
      expect(find.text('Croissant dough'), findsNothing);
    });

    testWidgets('keeps the library scroll offset across width changes', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(599, 240)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();
      final compactScroll = _screenScroll(tester)..jumpTo(40);
      await tester.pump();
      expect(compactScroll.pixels, 40);

      tester.view.physicalSize = const Size(600, 240);
      await tester.pumpAndSettle();

      expect(_screenScroll(tester).pixels, 40);
    });

    testWidgets('keeps the master pane wide enough for large text', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(1200, 900)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 4;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(find.byKey(const ValueKey('recipe-detail-pane')), findsOneWidget);
      expect(
        tester
            .getSize(
              find.byKey(const PageStorageKey<String>('recipe-list-pane')),
            )
            .width,
        600,
      );
    });

    testWidgets('does not shrink the master pane above 200 percent text', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(840, 900)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpApp(_libraryOver(FakeRecipeRepository()));
      await tester.pump();
      final list = find.byKey(const PageStorageKey<String>('recipe-list-pane'));
      expect(tester.getSize(list).width, 420);

      tester.platformDispatcher.textScaleFactorTestValue = 2.01;
      await tester.pump();

      expect(tester.getSize(list).width, 420);
    });

    testWidgets('starts each selected recipe detail at the top', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(840, 500)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final detailedRecipes = FakeRecipeRepository()
        ..seed(
          Recipe(
            id: 'r-first',
            revision: 1,
            name: 'First recipe',
            baseYield: Quantity.parse('1000', Unit.gram),
            modifiedAt: DateTime.utc(2026, 9, 13),
            preparationNotes: List.generate(30, (index) => 'First note $index'),
            components: const [],
          ),
        )
        ..seed(
          Recipe(
            id: 'r-second',
            revision: 1,
            name: 'Second recipe',
            baseYield: Quantity.parse('1000', Unit.gram),
            modifiedAt: DateTime.utc(2026, 9, 12),
            preparationNotes: List.generate(
              30,
              (index) => 'Second note $index',
            ),
            components: const [],
          ),
        );

      await tester.pumpApp(_libraryOver(detailedRecipes));
      await tester.pump();

      final firstScroll = _detailScroll(tester);
      firstScroll.jumpTo(firstScroll.maxScrollExtent);
      await tester.pump();
      final savedOffset = firstScroll.pixels;
      expect(savedOffset, greaterThan(0));

      await tester.tap(_inLibraryList(find.text('Second recipe')));
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('recipe-detail-pane')),
          matching: find.text('Second recipe'),
        ),
        findsOneWidget,
      );
      expect(_detailScroll(tester).pixels, 0);
    });

    testWidgets('large text keeps a narrow medium window on one pane', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(600, 900)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(find.byKey(const ValueKey('recipe-detail-pane')), findsNothing);
      expect(_recipeTile(tester, 'Croissant dough').selected, isFalse);
    });

    testWidgets('the detail pane shows metadata and keeps both actions', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(840, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final detailed = Recipe(
        id: 'r-detail',
        revision: 1,
        name: 'Country loaf',
        category: 'Bread',
        baseYield: Quantity.parse('1000', Unit.gram),
        maxBatchYield: Quantity.parse('500', Unit.gram),
        modifiedAt: DateTime.utc(2026, 9, 10),
        preparationNotes: const ['Fold gently'],
        components: const [],
      );
      final repository = FakeRecipeRepository()..seed(detailed);

      await tester.pumpApp(_libraryOver(repository));
      await tester.pump();

      final detail = find.byKey(const ValueKey('recipe-detail-pane'));
      expect(
        find.descendant(of: detail, matching: find.text('Bread')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.text('500 g')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: detail, matching: find.text('Fold gently')),
        findsOneWidget,
      );

      await tester.tap(
        find.descendant(
          of: detail,
          matching: find.widgetWithText(FilledButton, 'Production Run'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProductionSetupPage), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: detail,
          matching: find.widgetWithText(OutlinedButton, 'Edit'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Edit recipe'), findsOneWidget);
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
      // A new recipe starts with no base yield unit, so the save needs one.
      await tester.tap(find.byType(DropdownButtonFormField<Unit>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('g').last);
      await tester.pumpAndSettle();
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

      await tester.tap(_inLibraryList(find.byIcon(Icons.edit_outlined)));
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

      expect(_inLibraryList(find.text('Ciabatta loaf')), findsOneWidget);
      expect((await recipes.findLatest('r-a'))!.revision, 2);
    });

    testWidgets('leaving the editor without saving changes nothing', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await tester.tap(_inLibraryList(find.byIcon(Icons.edit_outlined)));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('recipe-name')),
        'Discarded',
      );
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(_inLibraryList(find.text('Ciabatta')), findsOneWidget);
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
      expect(_inLibraryList(find.text('Ciabatta')), findsOneWidget);
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
      expect(_inLibraryList(find.text('Ciabatta')), findsOneWidget);
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
      expect(_inLibraryList(find.text('Ciabatta')), findsOneWidget);
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

      expect(_inLibraryList(find.text('Ciabatta')), findsOneWidget);
      expect(find.text('Croissant dough'), findsNothing);
    });
  });

  group('RecipeLibraryPage, row actions', () {
    late FakeRecipeRepository recipes;

    setUp(() {
      recipes = FakeRecipeRepository()
        ..seed(
          buildRecipe(
            id: 'r-a',
            name: 'Ciabatta',
            modifiedAt: DateTime.utc(2026, 9, 11),
          ),
        )
        ..seed(
          buildRecipe(
            id: 'r-b',
            name: 'Croissant dough',
            category: 'Doughs',
            modifiedAt: DateTime.utc(2026, 9, 13),
          ),
        );
    });

    testWidgets('the row menu offers Duplicate and Archive on a live recipe', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(_rowMenus, findsNWidgets(2));
      // The edit action keeps its leading slot; the menu did not absorb it.
      expect(_recipeTile(tester, 'Croissant dough').leading, isA<IconButton>());
      await tester.tap(_rowMenus.first);
      await tester.pumpAndSettle();

      expect(_menuItem('Duplicate'), findsOneWidget);
      expect(_menuItem('Archive'), findsOneWidget);
      expect(_menuItem('Unarchive'), findsNothing);
    });

    testWidgets('the row menu offers Unarchive on an archived recipe', (
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
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      // Newest first, so the archived row is the top one.
      expect(_rowTitles(tester)[1], 'Summer focaccia');
      await tester.tap(_rowMenus.first);
      await tester.pumpAndSettle();

      expect(_menuItem('Unarchive'), findsOneWidget);
      expect(_menuItem('Archive'), findsNothing);
      expect(_menuItem('Duplicate'), findsOneWidget);
    });

    testWidgets('Archive hides the row at once and Undo brings it back', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await _pickFromFirstRowMenu(tester, 'Archive');

      // No confirmation dialog: the row is gone and the notice offers the
      // reversal instead.
      expect(find.byType(AlertDialog), findsNothing);
      expect((await recipes.findLatest('r-b'))!.isArchived, isTrue);
      expect(_inLibraryList(find.text('Croissant dough')), findsNothing);
      expect(find.text('Recipe archived.'), findsOneWidget);

      await tester.tap(find.widgetWithText(SnackBarAction, 'Undo'));
      await tester.pumpAndSettle();

      expect((await recipes.findLatest('r-b'))!.isArchived, isFalse);
      expect(_inLibraryList(find.text('Croissant dough')), findsOneWidget);
      expect(find.text('Recipe unarchived.'), findsOneWidget);
    });

    testWidgets('Unarchive lists the row among the live ones', (tester) async {
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
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      await _pickFromFirstRowMenu(tester, 'Unarchive');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      expect((await recipes.findLatest('r-c'))!.isArchived, isFalse);
      expect(_inLibraryList(find.text('Summer focaccia')), findsOneWidget);
      expect(find.textContaining('Archived'), findsNothing);
    });

    testWidgets('Duplicate stores the copy and opens the editor on it', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await _pickFromFirstRowMenu(tester, 'Duplicate');

      // Stored before the editor opens, under the localized name and a slug
      // of it, carrying the source's category.
      final copy = await recipes.findLatest('croissant-dough-copy');
      expect(copy, isNotNull);
      expect(copy!.revision, 1);
      expect(copy.name, 'Croissant dough (copy)');
      expect(copy.category, 'Doughs');
      expect(find.text('Edit recipe'), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Croissant dough (copy)'),
        findsOneWidget,
      );

      // Leaving without saving keeps the copy: it was never a draft.
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.byType(RecipeLibraryPage), findsOneWidget);
      expect(
        _inLibraryList(find.text('Croissant dough (copy)')),
        findsOneWidget,
      );
      expect(_inLibraryList(find.text('Croissant dough')), findsOneWidget);
    });

    testWidgets('renaming the copy in the editor lists the new name', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      await _pickFromFirstRowMenu(tester, 'Duplicate');
      await tester.enterText(
        find.byKey(const ValueKey('recipe-name')),
        'Danish dough',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pumpAndSettle();

      // The rename is revision 2 of the copy, not a third recipe.
      expect(_inLibraryList(find.text('Danish dough')), findsOneWidget);
      expect(find.text('Croissant dough (copy)'), findsNothing);
      expect((await recipes.findLatest('croissant-dough-copy'))!.revision, 2);
    });

    testWidgets('a failed archive keeps the row and says which action failed', (
      tester,
    ) async {
      final failing = FailingLifecycleRecipeRepository(recipes);
      await tester.pumpApp(_libraryOver(failing));
      await tester.pump();

      await _pickFromFirstRowMenu(tester, 'Archive');

      expect(find.text('The recipe could not be archived.'), findsOneWidget);
      expect(_inLibraryList(find.text('Croissant dough')), findsOneWidget);
      expect(find.widgetWithText(SnackBarAction, 'Undo'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a failed duplicate says so and opens no editor', (
      tester,
    ) async {
      final failing = FailingLifecycleRecipeRepository(recipes);
      await tester.pumpApp(_libraryOver(failing));
      await tester.pump();

      await _pickFromFirstRowMenu(tester, 'Duplicate');

      expect(find.text('The recipe could not be duplicated.'), findsOneWidget);
      expect(find.text('Edit recipe'), findsNothing);
      expect(_inLibraryList(find.text('Croissant dough')), findsOneWidget);
    });

    testWidgets('a failed unarchive names that action', (tester) async {
      recipes.seed(
        buildRecipe(
          id: 'r-c',
          name: 'Summer focaccia',
          isArchived: true,
          modifiedAt: DateTime.utc(2026, 9, 15),
        ),
      );
      final failing = FailingLifecycleRecipeRepository(recipes);
      await tester.pumpApp(_libraryOver(failing));
      await tester.pump();
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      await _pickFromFirstRowMenu(tester, 'Unarchive');

      expect(find.text('The recipe could not be unarchived.'), findsOneWidget);
    });

    testWidgets('the detail pane offers Duplicate and Archive beside Edit', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(840, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      final detail = find.byKey(const ValueKey('recipe-detail-pane'));
      Finder detailButton(String label) => find.descendant(
        of: detail,
        matching: find.widgetWithText(OutlinedButton, label),
      );
      expect(detailButton('Edit'), findsOneWidget);
      expect(detailButton('Duplicate'), findsOneWidget);
      expect(detailButton('Archive'), findsOneWidget);

      await tester.tap(detailButton('Archive'));
      await tester.pumpAndSettle();

      // The archived recipe left the visible rows, so the pane fell back to
      // the next one; with the switch on it is selectable again and offers
      // the reversal.
      expect(find.text('Recipe archived.'), findsOneWidget);
      expect(
        find.descendant(of: detail, matching: find.text('Croissant dough')),
        findsNothing,
      );
      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();
      await tester.tap(_inLibraryList(find.text('Croissant dough')));
      await tester.pump();
      expect(detailButton('Unarchive'), findsOneWidget);
      expect(detailButton('Archive'), findsNothing);

      await tester.tap(detailButton('Duplicate'));
      await tester.pumpAndSettle();

      expect(find.text('Edit recipe'), findsOneWidget);
      expect(
        (await recipes.findLatest('croissant-dough-copy'))!.isArchived,
        isFalse,
      );
    });

    testWidgets(
      'the detail pane refuses a second Duplicate while the first is stored',
      (tester) async {
        tester.view
          ..physicalSize = const Size(840, 1000)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        // Holds the copy's write open, so there is a window to tap in. This
        // pane is the entry point that stays up for the whole of a real
        // duplicate: the re-read that follows the write shows the list a
        // spinner, but the pane renders from rows the loading state keeps.
        final deferred = DeferredWriteRecipeRepository(recipes);
        await tester.pumpApp(_libraryOver(deferred));
        await tester.pump();
        final detail = find.byKey(const ValueKey('recipe-detail-pane'));
        Finder detailButton(String label) => find.descendant(
          of: detail,
          matching: find.widgetWithText(OutlinedButton, label),
        );

        await tester.tap(detailButton('Duplicate'));
        await tester.pump();

        expect(deferred.written, hasLength(1));
        // Rejects the unconditionally enabled button codex found: greyed
        // out for as long as the write runs, while the archive action,
        // which stores the same thing however often it is asked, is not.
        expect(
          tester.widget<OutlinedButton>(detailButton('Duplicate')).enabled,
          isFalse,
        );
        expect(
          tester.widget<OutlinedButton>(detailButton('Archive')).enabled,
          isTrue,
        );

        // The double tap. A disabled button swallows it, and the cubit
        // would drop it anyway.
        await tester.tap(detailButton('Duplicate'));
        await tester.pump();
        deferred.completeWrite(0);
        await tester.pumpAndSettle();

        // One write, one editor over the one copy, and no failure notice
        // beside it.
        expect(deferred.written, hasLength(1));
        expect(deferred.written.single.id, 'croissant-dough-copy');
        expect(find.byType(RecipeEditorPage), findsOneWidget);
        expect(find.text('The recipe could not be duplicated.'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('the row menu greys Duplicate out while a copy is stored', (
      tester,
    ) async {
      final deferred = DeferredWriteRecipeRepository(recipes);
      await tester.pumpApp(_libraryOver(deferred));
      await tester.pump();

      await _pickFromFirstRowMenu(tester, 'Duplicate');
      expect(deferred.written, hasLength(1));

      // The rows are still up — the write has not landed, so the re-read
      // that replaces them with a spinner has not started — and the menu
      // opens again on the same row.
      await tester.tap(_rowMenus.first);
      await tester.pumpAndSettle();

      PopupMenuItem<Object?> item(String label) => tester.widget(
        find.ancestor(
          of: _menuItem(label),
          matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        ),
      );
      expect(item('Duplicate').enabled, isFalse);
      expect(item('Archive').enabled, isTrue);

      // A tap on the greyed item is swallowed; the menu stays open, so it
      // is dismissed through the barrier before the write is released.
      await tester.tap(_menuItem('Duplicate'));
      await tester.pump();
      expect(_menuItem('Duplicate'), findsOneWidget);
      await tester.tapAt(const Offset(1, 1));
      await tester.pumpAndSettle();
      expect(_menuItem('Duplicate'), findsNothing);

      deferred.completeWrite(0);
      await tester.pumpAndSettle();

      expect(deferred.written, hasLength(1));
      expect(find.byType(RecipeEditorPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a copy that lands under another route opens no editor', (
      tester,
    ) async {
      // Holds the copy's write open, so there is a window in which the
      // operator can open a route of their own before the notice arrives.
      final deferred = DeferredWriteRecipeRepository(recipes);
      await tester.pumpApp(_libraryOver(deferred));
      await tester.pump();

      await _pickFromFirstRowMenu(tester, 'Duplicate');
      expect(deferred.written, hasLength(1));

      // New stays enabled while the copy is stored: only Duplicate is
      // greyed out. It pushes the blank editor over the library.
      await tester.tap(find.byTooltip('New recipe'));
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditorPage), findsOneWidget);

      // The fake records a write without listing it, so the copy is
      // seeded by hand before the write is released: the re-read that
      // follows it then lists the copy as the real store would.
      recipes.seed(deferred.written.single);
      deferred.completeWrite(0);
      await tester.pumpAndSettle();

      // The blank editor is still the one on top, with nothing pushed over
      // it: the copy's name is nowhere in the form. The copy is announced
      // instead, on the screen the operator is looking at, because the
      // editor that did not open was the only other confirmation.
      expect(find.byType(RecipeEditorPage), findsOneWidget);
      expect(
        find.widgetWithText(TextFormField, 'Croissant dough (copy)'),
        findsNothing,
      );
      expect(find.text('Copy saved to the library.'), findsOneWidget);

      // One back lands on the library, not on a second editor, and the
      // copy is stored and listed there: the editor was the convenience,
      // the copy is the outcome.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(RecipeLibraryPage), findsOneWidget);
      expect(find.byType(RecipeEditorPage), findsNothing);
      expect(deferred.written.single.id, 'croissant-dough-copy');
      expect(
        _inLibraryList(find.text('Croissant dough (copy)')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the wide layout starts one tap target past 420', (
      tester,
    ) async {
      // 420 was where a row moved Production Run into the tile's trailing
      // slot. The menu now shares that slot and costs the title 48 pixels
      // of room, so the threshold moved by that much: at 468 the title has
      // the width it had at 420, and one pixel under it the row stacks.
      tester.view
        ..physicalSize = const Size(468, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_recipeTile(tester, 'Croissant dough').trailing, isA<Row>());
      expect(_rowMenus, findsNWidgets(2));

      tester.view.physicalSize = const Size(467, 900);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_recipeTile(tester, 'Croissant dough').trailing, isNull);
      expect(_rowMenus, findsNWidgets(2));
    });

    testWidgets('a wide window gives the master pane single-line rows', (
      tester,
    ) async {
      // The pane is capped at the same width the single-line row needs,
      // so a window twice that wide gets a pane whose rows lay their
      // actions out beside the title.
      tester.view
        ..physicalSize = const Size(936, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(
        tester
            .getSize(
              find.byKey(const PageStorageKey<String>('recipe-list-pane')),
            )
            .width,
        468,
      );
      expect(_recipeTile(tester, 'Croissant dough').trailing, isA<Row>());
    });

    testWidgets('the compact layout keeps the menu on the second line', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 900)
        ..devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpApp(_libraryOver(recipes));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_recipeTile(tester, 'Croissant dough').trailing, isNull);
      // Reachable: on screen, and its 48 pixels are all inside the row.
      final menu = tester.getRect(_rowMenus.first);
      expect(menu.width, greaterThanOrEqualTo(48));
      expect(menu.height, greaterThanOrEqualTo(48));
      expect(menu.right, lessThanOrEqualTo(320));
      await tester.tap(_rowMenus.first);
      await tester.pumpAndSettle();
      expect(_menuItem('Archive'), findsOneWidget);
    });
  });

  group('RecipeLibraryPage, category filter', () {
    testWidgets('no chips are shown when no recipe has a category', (
      tester,
    ) async {
      final uncategorised = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'r-a', name: 'Ciabatta'));
      await tester.pumpApp(_libraryOver(uncategorised));
      await tester.pump();

      // Not even "All": a filter with one setting is not a filter.
      expect(find.byType(ChoiceChip), findsNothing);
    });

    testWidgets('chips list All and each category, and filter the rows', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(_categorisedLibrary()));
      await tester.pump();

      expect(_chip('All'), findsOneWidget);
      expect(_chip('Breads'), findsOneWidget);
      expect(_chip('Doughs'), findsOneWidget);
      // One chip per distinct category: two Breads make one chip.
      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(_isSelected(tester, 'All'), isTrue);
      // The chips sit between the field and the switch, in a wrap rather
      // than a horizontally scrolling row.
      expect(
        find.ancestor(of: _chip('All'), matching: find.byType(Wrap)),
        findsOneWidget,
      );
      expect(
        find.ancestor(
          of: _chip('All'),
          matching: find.byType(SingleChildScrollView),
        ),
        findsNothing,
      );

      await tester.tap(_chip('Doughs'));
      await tester.pump();

      expect(_isSelected(tester, 'Doughs'), isTrue);
      expect(_isSelected(tester, 'All'), isFalse);
      expect(_rowTitles(tester), ['Show archived recipes', 'Croissant dough']);

      await tester.tap(_chip('All'));
      await tester.pump();

      expect(_isSelected(tester, 'All'), isTrue);
      expect(_rowTitles(tester), [
        'Show archived recipes',
        'Country loaf',
        'Croissant dough',
        'Pastry cream',
      ]);
    });

    testWidgets('tapping the selected chip again clears the filter', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(_categorisedLibrary()));
      await tester.pump();

      await tester.tap(_chip('Breads'));
      await tester.pump();
      expect(_rowTitles(tester), ['Show archived recipes', 'Country loaf']);

      await tester.tap(_chip('Breads'));
      await tester.pump();

      expect(_isSelected(tester, 'All'), isTrue);
      expect(_rowTitles(tester), hasLength(4));
    });

    testWidgets('a category with only archived rows points at the switch', (
      tester,
    ) async {
      final library = _categorisedLibrary();
      await library.setArchived('r-loaf', isArchived: true);
      await tester.pumpApp(_libraryOver(library));
      await tester.pump();

      await tester.tap(_chip('Breads'));
      await tester.pump();

      // Both Breads are archived, so the switch is what would show them.
      expect(find.text(_onlyArchivedMessage), findsOneWidget);
      expect(find.text(_noMatchMessage), findsNothing);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      expect(_rowTitles(tester), [
        'Show archived recipes',
        'Country loaf',
        'Summer focaccia',
      ]);
    });

    testWidgets('a category the search empties says no matches, not empty', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(_categorisedLibrary()));
      await tester.pump();

      await tester.tap(_chip('Breads'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'crois');
      await tester.pump(_pastTheDebounce);
      await tester.pump();

      // The read holds a Dough the filter excludes: a filtered nothing, not
      // an unfilled library, so no create button.
      expect(find.text(_noMatchMessage), findsOneWidget);
      expect(find.text(_emptyMessage), findsNothing);
      expect(find.text(_onlyArchivedMessage), findsNothing);
      expect(_emptyLibraryCreateButton, findsNothing);
      // And the selected chip is still there to clear, although no result
      // carries its category any more.
      expect(_chip('Breads'), findsOneWidget);
      expect(_isSelected(tester, 'Breads'), isTrue);

      await tester.tap(_chip('All'));
      await tester.pump();

      expect(_inLibraryList(find.text('Croissant dough')), findsOneWidget);
    });

    testWidgets('the chip row follows the result set, not the library', (
      tester,
    ) async {
      await tester.pumpApp(_libraryOver(_categorisedLibrary()));
      await tester.pump();
      expect(find.byType(ChoiceChip), findsNWidgets(3));

      // The only match carries no category, and no chip is selected to
      // keep. The library still holds Breads and Doughs, and the row goes
      // anyway: the chips are drawn from the rows the search returned, and
      // a chip for a category the results do not hold would filter them
      // down to nothing.
      await tester.enterText(find.byType(TextField), 'cream');
      await tester.pump(_pastTheDebounce);
      await tester.pump();

      expect(_rowTitles(tester), ['Show archived recipes', 'Pastry cream']);
      expect(find.byType(ChoiceChip), findsNothing);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump(_pastTheDebounce);
      await tester.pump();

      expect(find.byType(ChoiceChip), findsNWidgets(3));
      expect(_isSelected(tester, 'All'), isTrue);
      expect(_rowTitles(tester), hasLength(4));
    });

    testWidgets('the selection survives a width-class transition', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(599, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpApp(_libraryOver(_categorisedLibrary()));
      await tester.pump();

      await tester.tap(_chip('Doughs'));
      await tester.pump();
      expect(find.byKey(const ValueKey('recipe-detail-pane')), findsNothing);

      tester.view.physicalSize = const Size(840, 900);
      await tester.pump();

      // Rejects holding the selection in the list widget's own state, which
      // the re-layout from one pane to two rebuilds from scratch.
      expect(find.byKey(const ValueKey('recipe-detail-pane')), findsOneWidget);
      expect(_isSelected(tester, 'Doughs'), isTrue);
      expect(_rowTitles(tester), ['Show archived recipes', 'Croissant dough']);
    });
  });

  group('RecipeLibraryPage, tap targets', () {
    testWidgets('every control meets the 48-pixel minimum at a compact width', (
      tester,
    ) async {
      tester.view
        ..physicalSize = const Size(320, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();

      await tester.pumpApp(_libraryOver(_categorisedLibrary()));
      await tester.pump();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      // The chips are the control most likely to fall short: a chip is 32
      // pixels tall unless its tap target is padded.
      for (final chip in tester.widgetList(find.byType(ChoiceChip))) {
        final size = tester.getSize(find.byWidget(chip));
        expect(size.height, greaterThanOrEqualTo(48));
        expect(size.width, greaterThanOrEqualTo(48));
      }
      expect(tester.getSize(_rowMenus.first), const Size(48, 48));

      await tester.tap(_rowMenus.first);
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });

    testWidgets(
      'every control meets the 48-pixel minimum at an expanded width',
      (tester) async {
        tester.view
          ..physicalSize = const Size(1000, 1000)
          ..devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final handle = tester.ensureSemantics();

        await tester.pumpApp(_libraryOver(_categorisedLibrary()));
        await tester.pump();

        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        final detail = find.byKey(const ValueKey('recipe-detail-pane'));
        expect(detail, findsOneWidget);
        expect(tester.getSize(_rowMenus.first), const Size(48, 48));
        // The detail pane's new buttons are the height of the Edit button
        // they sit beside, and the guideline above has already accepted it.
        Finder detailButton(String label) => find.descendant(
          of: detail,
          matching: find.widgetWithText(OutlinedButton, label),
        );
        final editHeight = tester.getSize(detailButton('Edit')).height;
        expect(tester.getSize(detailButton('Duplicate')).height, editHeight);
        expect(tester.getSize(detailButton('Archive')).height, editHeight);

        // The menu's items are controls too, and only exist while it is
        // open; the compact test opens it as well, so both widths check
        // them.
        await tester.tap(_rowMenus.first);
        await tester.pumpAndSettle();

        expect(_menuItem('Duplicate'), findsOneWidget);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        handle.dispose();
      },
    );
  });
}
