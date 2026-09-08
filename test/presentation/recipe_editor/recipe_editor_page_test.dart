import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../../helpers/helpers.dart';
import '../fakes.dart';

final _piece = Unit.count('piece');
final _tray = Unit.namedYield('tray');

/// A screen that opens the editor the way the library screen does, so every
/// test here goes through [RecipeEditorLauncher] and the editor is a pushed
/// route — which is what makes the pop after a save observable.
class _EditorHost extends StatelessWidget {
  const _EditorHost({required this.launcher, this.recipe});

  final RecipeEditorLauncher launcher;
  final Recipe? recipe;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Builder(
      builder: (context) => TextButton(
        onPressed: () => launcher.open(context, recipe: recipe),
        child: const Text('open the editor'),
      ),
    ),
  );
}

/// A viewport tall and wide enough to hold the whole form.
///
/// Most tests here are about what the editor does, not how it folds up: the
/// list is lazy, so on the default 800-pixel screen the actions below the
/// components are not built at all and a finder for them reports nothing
/// rather than something off-screen. It is also wide enough to hide any
/// horizontal overflow, which is why the one test that is about narrow
/// widths passes a viewport of its own.
const _roomyViewport = Size(1200, 4000);

/// Pumps the host and pushes the editor, without settling: a pending read
/// leaves a spinner on screen, and `pumpAndSettle` never returns on one.
Future<void> _openEditor(
  WidgetTester tester, {
  required RecipeRepository recipes,
  required IngredientRepository ingredients,
  Recipe? recipe,
  Size viewport = _roomyViewport,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpApp(
    _EditorHost(
      launcher: buildEditorLauncher(recipes, ingredients),
      recipe: recipe,
    ),
  );
  await tester.tap(find.text('open the editor'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Taps the app bar's save action and lets the write land.
Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(TextButton, 'Save'));
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

/// Fills the two fields a save needs before it will write.
Future<void> _fillRequiredFields(
  WidgetTester tester, {
  String name = 'Ciabatta',
}) async {
  await tester.enterText(find.byKey(const ValueKey('recipe-name')), name);
  await tester.enterText(find.byKey(const ValueKey('base-yield')), '1000');
  await tester.pump();
}

/// Scrolls [finder] into view and taps it.
///
/// The form is taller than the test viewport as soon as it holds a card, so
/// an unscrolled tap on the actions below the list misses entirely.
Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// The text field inside the open dialog.
///
/// Not `find.byType(TextField).first`: every field on the form behind the
/// dialog is a `TextFormField`, which builds a `TextField` of its own, and
/// the unscoped finder reaches the recipe name.
Finder _dialogField() => find
    .descendant(of: find.byType(AlertDialog), matching: find.byType(TextField))
    .first;

/// Where the card naming [target] sits vertically.
double _cardTop(WidgetTester tester, String target) =>
    tester.getTopLeft(find.widgetWithText(Card, target)).dy;

void main() {
  late FakeRecipeRepository recipes;
  late FakeIngredientRepository ingredients;

  setUp(() async {
    recipes = FakeRecipeRepository();
    ingredients = FakeIngredientRepository();
    await ingredients.upsert(buildIngredient(id: 'flour'));
    await ingredients.upsert(buildIngredient(id: 'water', name: 'Water'));
  });

  group('opening the editor', () {
    testWidgets('shows a spinner until the libraries answer', (tester) async {
      final deferred = DeferredIngredientRepository();

      await _openEditor(tester, recipes: recipes, ingredients: deferred);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const ValueKey('recipe-name')), findsNothing);

      deferred.complete(0, []);
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const ValueKey('recipe-name')), findsOneWidget);
    });

    testWidgets('a failed read offers a retry rather than an empty form', (
      tester,
    ) async {
      final deferred = DeferredIngredientRepository();

      await _openEditor(tester, recipes: recipes, ingredients: deferred);
      deferred.fail(0);
      await tester.pump();

      // Rejects showing the form with empty pickers: an operator cannot
      // tell an empty ingredient library from one that could not be read.
      expect(
        find.text('The ingredient and recipe libraries could not be loaded.'),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('recipe-name')), findsNothing);

      await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
      await tester.pump();
      deferred.complete(1, []);
      await tester.pump();

      expect(find.byKey(const ValueKey('recipe-name')), findsOneWidget);
    });

    testWidgets('a new recipe opens on an empty form', (tester) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);

      expect(find.text('New recipe'), findsOneWidget);
      expect(find.text('No ingredients yet.'), findsOneWidget);
      expect(find.byType(Card), findsNothing);
    });

    testWidgets('a stored recipe opens filled in', (tester) async {
      final stored = Recipe(
        id: 'croissant-dough',
        revision: 2,
        name: 'Croissant dough',
        category: 'Doughs',
        baseYield: Quantity.parse('24', _piece),
        maxBatchYield: Quantity.parse('12', _piece),
        modifiedAt: DateTime.utc(2026, 9, 3),
        preparationNotes: const ['Laminate cold'],
        components: [
          RecipeComponent(
            id: 'flour',
            target: const IngredientRef('flour'),
            baseQuantity: Quantity.parse('1000', Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
      );
      recipes.seed(stored);

      await _openEditor(
        tester,
        recipes: recipes,
        ingredients: ingredients,
        recipe: stored,
      );

      expect(find.text('Edit recipe'), findsOneWidget);
      expect(find.text('Croissant dough'), findsOneWidget);
      expect(find.text('Doughs'), findsOneWidget);
      expect(find.text('Laminate cold'), findsOneWidget);
      // The component's target is named, not identified: the ingredient
      // record is what the editor reads that name from.
      expect(find.text('Flour'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    });

    testWidgets('a component whose ingredient has no record shows its id', (
      tester,
    ) async {
      final stored = buildRecipe(
        id: 'mystery',
        components: [
          RecipeComponent(
            id: 'c1',
            target: const IngredientRef('unrecorded-thing'),
            baseQuantity: Quantity.parse('1', Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
      );

      await _openEditor(
        tester,
        recipes: recipes..seed(stored),
        ingredients: ingredients,
        recipe: stored,
      );

      // The seed's components referenced ingredients no record existed for,
      // which is the state this slice fixes; a blank line would have hidden
      // it instead of naming what is missing.
      expect(find.text('unrecorded-thing'), findsOneWidget);
    });
  });

  group('field validation', () {
    testWidgets('save reports what is missing rather than writing', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);

      // Nothing is red before the first save: a form that reports what is
      // missing before anything is typed reports everything at once.
      expect(find.text('Enter a name.'), findsNothing);

      await _save(tester);

      expect(find.text('Enter a name.'), findsOneWidget);
      expect(find.text('Enter an amount above zero.'), findsOneWidget);
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
    });

    testWidgets('a maximum batch yield in the wrong dimension is refused', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await tester.enterText(
        find.byKey(const ValueKey('max-batch-yield')),
        '12',
      );
      await tester.pump();

      // The base yield is in grams; pick pieces for the maximum, which
      // `Recipe` rejects and the form can decide on its own.
      await _tap(tester, find.byType(DropdownButtonFormField<Unit>).last);
      await tester.tap(find.text('portion').last);
      await tester.pumpAndSettle();
      await _save(tester);

      expect(
        find.text('Use a unit the base yield converts to.'),
        findsOneWidget,
      );
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
    });

    testWidgets('a sub-recipe line in the wrong unit is refused too', (
      tester,
    ) async {
      final cake = buildRecipe(
        id: 'cake',
        name: 'Cake',
        components: [
          RecipeComponent(
            id: 'sub-dough',
            target: const SubRecipeRef('dough'),
            baseQuantity: null,
            behavior: ScalingBehavior.manual,
            displayOrder: 0,
          ),
        ],
      );
      recipes
        ..seed(
          buildRecipe(
            id: 'dough',
            name: 'Croissant dough',
            baseYield: Quantity.parse('4', _tray),
          ),
        )
        ..seed(cake);

      await _openEditor(
        tester,
        recipes: recipes,
        ingredients: ingredients,
        recipe: cake,
      );
      // A stored manual line carries no quantity and therefore no unit, so
      // the form starts it at the fallback — grams, under a recipe that
      // yields trays. Giving it a scaling behavior is how a line reaches a
      // unit the narrowed picker would never have offered.
      await _tap(tester, find.byType(DropdownButtonFormField<ScalingBehavior>));
      await tester.tap(find.text('Proportional').last);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('sub-dough-amount')),
        '2',
      );
      await tester.pump();

      await _save(tester);

      expect(
        find.text("Use a unit this sub-recipe's own yield converts to."),
        findsOneWidget,
      );
      // Stored, it would throw on every production run of Cake, and nothing
      // between the form and the run would have said so.
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
      expect(find.byType(RecipeEditorPage), findsOneWidget);
    });

    testWidgets('a base yield unit the recipes above it cannot use is named', (
      tester,
    ) async {
      final cream = buildRecipe(
        id: 'cream',
        name: 'Pastry cream',
        baseYield: Quantity.parse('2000', Unit.gram),
      );
      recipes
        ..seed(cream)
        ..seed(
          buildRecipe(
            id: 'croissant',
            name: 'Almond croissant',
            components: [
              RecipeComponent(
                id: 'sub-cream',
                target: const SubRecipeRef('cream'),
                baseQuantity: Quantity.parse('400', Unit.gram),
                behavior: ScalingBehavior.proportional,
                displayOrder: 0,
              ),
            ],
          ),
        );

      await _openEditor(
        tester,
        recipes: recipes,
        ingredients: ingredients,
        recipe: cream,
      );
      // The base yield's own unit dropdown is the first on the form; the
      // maximum batch yield's is the one after it.
      await _tap(tester, find.byType(DropdownButtonFormField<Unit>).first);
      await tester.tap(find.text('L').last);
      await tester.pumpAndSettle();

      await _save(tester);

      // The message names what the operator has to go and look at: the
      // breakage is in Almond croissant, which is not on this screen.
      expect(
        find.text(
          'Almond croissant uses this recipe in a unit this yield cannot '
          'convert to.',
        ),
        findsOneWidget,
      );
      // Stored, every future production run of Almond croissant would throw
      // `IncompatibleYieldUnitError`, with nothing here having said so.
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
      expect(find.byType(RecipeEditorPage), findsOneWidget);
    });

    testWidgets('an amount that is not a number blocks the save', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await tester.enterText(find.byKey(const ValueKey('base-yield')), 'lots');
      await tester.pump();

      await _save(tester);

      expect(find.text('Enter an amount above zero.'), findsOneWidget);
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
    });
  });

  group('components', () {
    Future<void> addFlour(WidgetTester tester) async {
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));
      await tester.tap(find.widgetWithText(ListTile, 'Flour'));
      await tester.pumpAndSettle();
    }

    testWidgets('an ingredient picked from the library becomes a line', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);

      await addFlour(tester);

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('No ingredients yet.'), findsNothing);
      expect(find.widgetWithText(Card, 'Flour'), findsOneWidget);
    });

    testWidgets('the picker proposes matches before creating a new one', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));

      await tester.enterText(_dialogField(), 'flo');
      await tester.pumpAndSettle();

      // The near-duplicate guard: the operator sees what is already stored
      // before deciding to add another entry that means the same thing.
      expect(
        find.text(
          'Similar ingredients are already in the library. '
          'Pick one, or create a new one.',
        ),
        findsOneWidget,
      );
      expect(find.widgetWithText(ListTile, 'Flour'), findsOneWidget);

      await tester.enterText(_dialogField(), 'Flour');
      await tester.pumpAndSettle();

      // An exact match is not a near-duplicate but the same thing, so
      // creating is refused outright rather than merely discouraged.
      final create = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Create new ingredient'),
      );
      expect(create.onPressed, isNull);
    });

    testWidgets('a name matching nothing creates the ingredient', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));

      await tester.enterText(_dialogField(), 'Almond flakes');
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create new ingredient'),
      );
      await tester.pumpAndSettle();

      // Ingredients are reusable library entries with no screen of their
      // own, so the editor is where they come from.
      expect(ingredients.stored['almond-flakes']!.name, 'Almond flakes');
      expect(find.text('Almond flakes'), findsOneWidget);
    });

    testWidgets('a created ingredient keeps the unit chosen for it', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));
      await tester.enterText(_dialogField(), 'Eggs');
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<Unit>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('kg').last);
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create new ingredient'),
      );
      await tester.pumpAndSettle();

      // The stored record carries it, and so does the line the picker
      // added: a component starts in its ingredient's own unit.
      expect(ingredients.stored['eggs']!.defaultUnit, Unit.kilogram);
      expect(find.widgetWithText(Card, 'Eggs'), findsOneWidget);
    });

    testWidgets('leaving the picker adds nothing', (tester) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNothing);
    });

    testWidgets('a sub-recipe is picked from the library', (tester) async {
      recipes
        ..seed(
          buildRecipe(
            id: 'dough',
            name: 'Croissant dough',
            baseYield: Quantity.parse('24', _piece),
          ),
        )
        ..seed(buildRecipe(id: 'old', name: 'Shelved', isArchived: true));

      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add sub-recipe'));

      // An archived dependency blocks a production run, so offering one
      // would build a recipe that cannot be run.
      expect(find.textContaining('Shelved'), findsNothing);

      await tester.tap(find.textContaining('Croissant dough'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Card, 'Croissant dough'), findsOneWidget);
    });

    testWidgets("a sub-recipe line's unit picker offers only its yield", (
      tester,
    ) async {
      recipes.seed(
        buildRecipe(
          id: 'dough',
          name: 'Croissant dough',
          baseYield: Quantity.parse('24', _piece),
        ),
      );

      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add sub-recipe'));
      await tester.tap(find.textContaining('Croissant dough'));
      await tester.pumpAndSettle();

      final choices = tester
          .widget<DropdownButton<Unit>>(
            find.descendant(
              of: find.widgetWithText(Card, 'Croissant dough'),
              matching: find.byType(DropdownButton<Unit>),
            ),
          )
          .items!
          .map((item) => item.value);

      // This line's quantity is the target yield the referenced recipe is
      // run against, so anything the recipe's own yield does not convert to
      // stores a recipe whose every production run throws. The metadata
      // rows are not narrowed: they measure this recipe, not that one.
      expect(choices, [_piece]);
      expect(
        tester
            .widget<DropdownButton<Unit>>(
              find.byType(DropdownButton<Unit>).first,
            )
            .items!
            .map((item) => item.value),
        containsAll([Unit.gram, Unit.liter]),
      );
    });

    testWidgets('the sub-recipe picker says when it has nothing to offer', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add sub-recipe'));

      expect(find.text('No recipe is available to reference.'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNothing);
    });

    testWidgets('a manual line offers no amount, unit or rounding', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await addFlour(tester);

      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('Round up to (optional)'), findsOneWidget);

      await _tap(tester, find.byType(DropdownButtonFormField<ScalingBehavior>));
      await tester.tap(find.text('Manual').last);
      await tester.pumpAndSettle();

      // A free-form amount is a manual component, never a numeric zero, so
      // the controls are absent rather than showing a zero to ignore.
      expect(find.text('Amount'), findsNothing);
      expect(find.text('Round up to (optional)'), findsNothing);
      expect(find.text('Note (optional)'), findsOneWidget);

      await _save(tester);

      final stored = (await recipes.findLatest('ciabatta'))!;
      expect(stored.components.single.baseQuantity, isNull);
      expect(stored.components.single.behavior, ScalingBehavior.manual);
    });

    testWidgets('every field on a line reaches the stored revision', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await addFlour(tester);

      await tester.enterText(
        find.byKey(const ValueKey('component-1-amount')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('component-1-rounding')),
        '0.5',
      );
      await tester.enterText(
        find.byKey(const ValueKey('component-1-note')),
        'Sift first',
      );
      await tester.pump();
      await _tap(tester, find.byType(DropdownButtonFormField<Unit>).last);
      await tester.tap(find.text('kg').last);
      await tester.pumpAndSettle();
      await _tap(tester, find.byType(DropdownButtonFormField<ScalingBehavior>));
      await tester.tap(find.text('Per batch').last);
      await tester.pumpAndSettle();
      await _save(tester);

      final component = (await recipes.findLatest(
        'ciabatta',
      ))!.components.single;
      expect(component.baseQuantity, Quantity.parse('2', Unit.kilogram));
      expect(component.rounding!.increment, Decimal.parse('0.5'));
      expect(component.note, 'Sift first');
      expect(component.behavior, ScalingBehavior.perBatch);
    });

    testWidgets('a line reports its own missing amount and bad increment', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await addFlour(tester);
      await tester.enterText(
        find.byKey(const ValueKey('component-1-rounding')),
        '0',
      );
      await tester.pump();

      await _save(tester);

      // Both are field errors the form can decide on its own, so neither
      // reaches storage as a failure the operator cannot read.
      expect(find.text('Enter an amount above zero.'), findsNWidgets(2));
      expect(
        recipes.calls.where((call) => call.startsWith('saveRevision:')),
        isEmpty,
      );
    });

    testWidgets('a line can be removed', (tester) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await addFlour(tester);

      await _tap(tester, find.byIcon(Icons.delete_outline));

      expect(find.byType(Card), findsNothing);
      expect(find.text('No ingredients yet.'), findsOneWidget);
    });
  });

  group('changing what a line consumes', () {
    /// Opens the picker behind the target of the line named [target].
    Future<void> changeTarget(WidgetTester tester, String target) => _tap(
      tester,
      find.descendant(of: find.byType(Card), matching: find.text(target)),
    );

    Future<void> addFlour(WidgetTester tester) async {
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));
      await tester.tap(find.widgetWithText(ListTile, 'Flour'));
      await tester.pumpAndSettle();
    }

    testWidgets('a line is pointed at another ingredient, keeping its fields', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await addFlour(tester);
      await tester.enterText(
        find.byKey(const ValueKey('component-1-amount')),
        '250',
      );
      await tester.pump();

      await changeTarget(tester, 'Flour');
      await tester.tap(find.widgetWithText(ListTile, 'Water'));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      await _save(tester);

      // Read from the stored revision rather than from the card: the
      // amount field is keyed by component id, so its own state survives
      // the rebuild whether or not the draft kept the amount. Rejects a
      // retarget that starts the line over, and rejects one that does
      // nothing at all.
      final stored = await recipes.findLatest('ciabatta');
      final component = stored!.components.single;
      expect(component.target, const IngredientRef('water'));
      expect(component.baseQuantity, Quantity.parse('250', Unit.gram));
    });

    testWidgets('a new name in the target picker retargets rather than adds', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await addFlour(tester);

      await changeTarget(tester, 'Flour');
      await tester.enterText(_dialogField(), 'Rye flour');
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create new ingredient'),
      );
      await tester.pumpAndSettle();

      expect(ingredients.stored['rye-flour']!.name, 'Rye flour');
      // One card, not two: rejects a creation path that appends its line
      // regardless of which component asked for it.
      expect(find.byType(Card), findsOneWidget);
      expect(find.widgetWithText(Card, 'Rye flour'), findsOneWidget);
    });

    testWidgets('leaving the target picker changes nothing', (tester) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await addFlour(tester);

      await changeTarget(tester, 'Flour');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.widgetWithText(Card, 'Flour'), findsOneWidget);
    });

    testWidgets('a sub-recipe line is pointed at another recipe', (
      tester,
    ) async {
      // The two recipes yield different units on purpose: a fixture where
      // both yield grams cannot tell a retarget that carries the unit
      // across from one that leaves it behind.
      recipes
        ..seed(
          buildRecipe(
            id: 'dough',
            name: 'Croissant dough',
            baseYield: Quantity.parse('24', _piece),
          ),
        )
        ..seed(
          buildRecipe(
            id: 'filling',
            name: 'Almond filling',
            baseYield: Quantity.parse('1000', Unit.gram),
          ),
        );
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add sub-recipe'));
      await tester.tap(find.textContaining('Croissant dough'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('component-1-amount')),
        '6',
      );
      await tester.pump();

      await changeTarget(tester, 'Croissant dough');
      // The picker offered is the one this line's target came from: an
      // ingredient line cannot become a sub-recipe line by accident.
      expect(find.byType(AlertDialog), findsNothing);
      await tester.tap(find.textContaining('Almond filling'));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.widgetWithText(Card, 'Almond filling'), findsOneWidget);

      await _save(tester);
      final component = (await recipes.findLatest(
        'ciabatta',
      ))!.components.single;
      expect(component.target, const SubRecipeRef('filling'));
      // The unit follows the recipe *because the old one cannot carry
      // across*: pieces do not convert to grams. `subRecipeTargetChanged`
      // owns when that substitution happens and when the typed unit is kept
      // instead. Rejects a retarget that moves the target and leaves an
      // unusable unit behind.
      expect(component.baseQuantity, Quantity.parse('6', Unit.gram));
    });

    testWidgets('leaving the sub-recipe target picker changes nothing', (
      tester,
    ) async {
      recipes.seed(buildRecipe(id: 'dough', name: 'Croissant dough'));
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add sub-recipe'));
      await tester.tap(find.textContaining('Croissant dough'));
      await tester.pumpAndSettle();

      await changeTarget(tester, 'Croissant dough');
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.widgetWithText(Card, 'Croissant dough'), findsOneWidget);
    });
  });

  group('at a split-window width', () {
    testWidgets('the form lays out at 320 logical pixels', (tester) async {
      // The narrow end the design document asks the app to survive: an
      // Android split-screen pane, an iPad Slide Over, an iPhone SE in
      // portrait. Every other test in this file runs at 1200 wide, which
      // is why nothing else here can see this.
      //
      // Rejects a unit dropdown left at `isExpanded: false`. Each one sits
      // in an `Expanded`, and by default a dropdown lays its own row out at
      // the widest menu item's intrinsic width instead of the width it was
      // handed, so it overflows the column it was given.
      await _openEditor(
        tester,
        recipes: recipes,
        ingredients: ingredients,
        recipe: buildRecipe(id: 'r-a'),
        viewport: const Size(320, 2400),
      );

      expect(tester.takeException(), isNull);
      // Reached the form rather than stopping at the spinner, which is what
      // makes the assertion above a statement about the form.
      expect(find.byType(Card), findsOneWidget);
      // The target is a control now, so it owes the 48 logical pixels the
      // design document asks of every touch target — and this is the width
      // where a control that grows its own height from its label is most
      // likely to fall short.
      expect(
        tester.getSize(find.byTooltip('Change what this line uses')).height,
        greaterThanOrEqualTo(48),
      );
    });
  });

  group('reordering', () {
    Future<void> addTwoLines(WidgetTester tester) async {
      for (final name in ['Flour', 'Water']) {
        await _tap(
          tester,
          find.widgetWithText(OutlinedButton, 'Add ingredient'),
        );
        await tester.tap(find.widgetWithText(ListTile, name));
        await tester.pumpAndSettle();
      }
    }

    testWidgets('the labelled move actions carry the typed text along', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await addTwoLines(tester);
      await tester.enterText(
        find.byKey(const ValueKey('component-1-amount')),
        '500',
      );
      await tester.enterText(
        find.byKey(const ValueKey('component-2-amount')),
        '300',
      );
      await tester.pump();

      // Every action needs a labelled alternative to its gesture, and a
      // screen reader cannot drag.
      await _tap(tester, find.byIcon(Icons.arrow_upward).last);
      await _save(tester);

      // Both halves matter: `displayOrder` alone passes even when the rows
      // swapped and the typed amounts stayed where they were.
      final stored = (await recipes.findLatest('ciabatta'))!;
      expect(
        stored.components.map(
          (c) => (c.target, c.displayOrder, c.baseQuantity!.toDecimal()),
        ),
        [
          (const IngredientRef('water'), 0, Decimal.parse('300')),
          (const IngredientRef('flour'), 1, Decimal.parse('500')),
        ],
      );
    });

    testWidgets('the move-down action sends a line the other way', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await addTwoLines(tester);

      await _tap(tester, find.byIcon(Icons.arrow_downward).first);

      expect(_cardTop(tester, 'Water'), lessThan(_cardTop(tester, 'Flour')));
    });

    testWidgets('dragging the handle moves the line too', (tester) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await addTwoLines(tester);

      final handle = find.byIcon(Icons.drag_handle).last;
      await tester.ensureVisible(handle);
      await tester.pumpAndSettle();
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(0, -20));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -300));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(_cardTop(tester, 'Water'), lessThan(_cardTop(tester, 'Flour')));
    });

    testWidgets('the ends of the list cannot move further out', (tester) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await addTwoLines(tester);

      final up = tester.widgetList<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.icon is Icon &&
              (widget.icon as Icon).icon == Icons.arrow_upward,
        ),
      );
      final down = tester.widgetList<IconButton>(
        find.byWidgetPredicate(
          (widget) =>
              widget is IconButton &&
              widget.icon is Icon &&
              (widget.icon as Icon).icon == Icons.arrow_downward,
        ),
      );

      expect(up.first.onPressed, isNull);
      expect(up.last.onPressed, isNotNull);
      expect(down.first.onPressed, isNotNull);
      expect(down.last.onPressed, isNull);
    });
  });

  group('custom units', () {
    testWidgets('a declared unit is offered everywhere on the screen', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);

      await _tap(tester, find.widgetWithText(TextButton, 'Add a custom unit'));
      await tester.enterText(_dialogField(), 'tray');
      await tester.tap(find.text('Recipe output'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      await _tap(tester, find.byType(DropdownButtonFormField<Unit>).first);

      // `Unit.namedYield` builds a unit from any symbol, so a picker
      // limited to the fixed table could not express a recipe measured in
      // trays — which the development seed already stores.
      expect(find.text('tray'), findsWidgets);
    });

    testWidgets('a counted unit reaches the stored recipe', (tester) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester);

      await _tap(tester, find.widgetWithText(TextButton, 'Add a custom unit'));
      await tester.enterText(_dialogField(), 'sheet');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Add'));
      await tester.pumpAndSettle();

      await _tap(tester, find.byType(DropdownButtonFormField<Unit>).first);
      await tester.tap(find.text('sheet').last);
      await tester.pumpAndSettle();
      await _save(tester);

      expect(
        (await recipes.findLatest('ciabatta'))!.baseYield.unit,
        Unit.count('sheet'),
      );
    });

    testWidgets('an unnamed unit cannot be added, and leaving adds none', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(TextButton, 'Add a custom unit'));

      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Add'))
            .onPressed,
        isNull,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New unit'), findsNothing);
    });
  });

  group('saving', () {
    testWidgets('a completed form is stored and the editor closes', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _fillRequiredFields(tester, name: 'Summer focaccia');
      await tester.enterText(
        find.byKey(const ValueKey('recipe-category')),
        'Breads',
      );
      await tester.enterText(
        find.byKey(const ValueKey('preparation-notes')),
        'Rest overnight',
      );
      await tester.pump();

      await _save(tester);
      await tester.pumpAndSettle();

      final stored = (await recipes.findLatest('summer-focaccia'))!;
      expect(stored.name, 'Summer focaccia');
      expect(stored.category, 'Breads');
      expect(stored.preparationNotes, ['Rest overnight']);
      // The editor closes over what was stored, so the screen underneath
      // can list it without guessing whether anything changed.
      expect(find.byType(RecipeEditorPage), findsNothing);
      // The pop the save performs reaches the same guard that refuses one
      // during a write, and a pop that happened has nothing to explain.
      expect(find.text('The change is still being saved.'), findsNothing);
    });

    testWidgets('the save is refused a second press while it is running', (
      tester,
    ) async {
      final deferred = DeferredWriteRecipeRepository(recipes);

      await _openEditor(tester, recipes: deferred, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      // A second press would write a second revision of the same edit.
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNull,
      );

      deferred.completeWrite(0);
      await tester.pumpAndSettle();
      expect(find.byType(RecipeEditorPage), findsNothing);
    });

    testWidgets('leaving is refused for as long as the save runs', (
      tester,
    ) async {
      final deferred = DeferredWriteRecipeRepository(recipes);

      await _openEditor(tester, recipes: deferred, ingredients: ingredients);
      await _fillRequiredFields(tester, name: 'Summer focaccia');
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      // Nothing cancels the write, so leaving here does not abandon the
      // edit: the revision lands, and the library underneath goes on
      // listing the recipe as it was, because it reads again only when this
      // route hands it back what was stored.
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump();

      expect(find.byType(RecipeEditorPage), findsOneWidget);
      expect(find.text('The change is still being saved.'), findsOneWidget);

      // The platform's back gesture is the other way out, and the one the
      // operator reaches without looking at the app bar. Both go through
      // `Navigator.maybePop`, so one guard covers them — which is the
      // claim this second half checks rather than assumes.
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byType(RecipeEditorPage), findsOneWidget);

      deferred.completeWrite(0);
      await tester.pumpAndSettle();

      // The refusal lasts exactly as long as the write. Once it lands the
      // screen leaves on its own, carrying what was stored, and the
      // library is told to read again.
      expect(find.byType(RecipeEditorPage), findsNothing);
      expect(deferred.written.single.name, 'Summer focaccia');
    });

    testWidgets('nothing typed or tapped while the save runs reaches it', (
      tester,
    ) async {
      final deferred = DeferredWriteRecipeRepository(recipes);

      await _openEditor(tester, recipes: deferred, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));
      await tester.tap(find.widgetWithText(ListTile, 'Flour'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('component-1-amount')),
        '500',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();

      await tester.enterText(
        find.byKey(const ValueKey('recipe-name')),
        'Renamed mid-save',
      );
      await tester.pump();

      // `enterText` sends no pointer events: it focuses the field and writes
      // through the test keyboard. A guard that only absorbed pointers would
      // let this land in the state the finishing write is about to
      // overwrite, and the screen pops before the operator sees it go.
      expect(find.text('Renamed mid-save'), findsNothing);
      expect(find.text('Ciabatta'), findsOneWidget);

      // The other half of the same guard: a tap reaches the form through a
      // different route than typed text, and removing a line here would
      // leave the operator watching a component disappear out of a recipe
      // that was stored with it.
      // `warnIfMissed` is off because missing is the point: the button is on
      // screen and the hit test stops above it.
      await tester.tap(find.byTooltip('Remove'), warnIfMissed: false);
      await tester.pump();

      expect(find.widgetWithText(Card, 'Flour'), findsOneWidget);

      deferred.completeWrite(0);
      await tester.pumpAndSettle();

      // What the write carried is what the form held when it started, and
      // the screen closes over it, so a late edit had nowhere to go.
      expect(deferred.written.single.name, 'Ciabatta');
      expect(deferred.written.single.components, hasLength(1));
      expect(find.byType(RecipeEditorPage), findsNothing);
    });

    testWidgets('the save is refused while an ingredient is being stored', (
      tester,
    ) async {
      final deferred = DeferredIngredientRepository()..deferWrites = true;

      await _openEditor(tester, recipes: recipes, ingredients: deferred);
      deferred.complete(0, []);
      await tester.pump();
      await _fillRequiredFields(tester);

      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));
      await tester.enterText(_dialogField(), 'Poolish');
      await tester.pump();
      await tester.tap(
        find.widgetWithText(FilledButton, 'Create new ingredient'),
      );
      await tester.pumpAndSettle();

      // The picker has closed and the write is still running. A save here
      // would store the recipe without the line that write is adding, and
      // the screen would pop over it.
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNull,
      );

      deferred.completeWrite(0);
      await tester.pumpAndSettle();

      expect(find.widgetWithText(Card, 'Poolish'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Save'))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a failed write is reported and the form stays up', (
      tester,
    ) async {
      final deferred = DeferredWriteRecipeRepository(recipes);

      await _openEditor(tester, recipes: deferred, ingredients: ingredients);
      await _fillRequiredFields(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Save'));
      await tester.pump();
      deferred.failWrite(0);
      await tester.pump();
      await tester.pump();

      expect(find.text('The change could not be saved.'), findsOneWidget);
      expect(find.byType(RecipeEditorPage), findsOneWidget);
      expect(find.byKey(const ValueKey('recipe-name')), findsOneWidget);
    });

    testWidgets('a cycle is reported with the path the domain found', (
      tester,
    ) async {
      final cake = buildRecipe(id: 'cake', name: 'Cake', components: const []);
      recipes
        ..seed(cake)
        ..seed(
          buildRecipe(
            id: 'syrup',
            name: 'Syrup',
            components: [buildSubRecipeComponent('cake')],
          ),
        );

      await _openEditor(
        tester,
        recipes: recipes,
        ingredients: ingredients,
        recipe: cake,
      );
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add sub-recipe'));
      await tester.tap(find.textContaining('Syrup'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('component-1-amount')),
        '100',
      );
      await tester.pump();
      await _save(tester);

      // The screen renders what the error carries rather than a generic
      // failure: the operator has to know which reference to remove.
      expect(
        find.text('A recipe cannot depend on itself: cake → syrup → cake'),
        findsOneWidget,
      );
      expect(find.byType(RecipeEditorPage), findsOneWidget);
    });

    testWidgets('a sub-recipe that has since been deleted is named', (
      tester,
    ) async {
      final ghost = buildRecipe(id: 'ghost', name: 'Ghost');
      final withGhost = buildRecipe(
        id: 'cake',
        name: 'Cake',
        components: [buildSubRecipeComponent('ghost')],
      );
      recipes.seed(withGhost);

      await _openEditor(
        tester,
        recipes: recipes,
        ingredients: ingredients,
        recipe: withGhost,
      );
      // The picker only offers what is stored, so the reference has to
      // arrive from a recipe saved before the dependency was removed.
      expect(ghost.id, 'ghost');

      await _save(tester);

      expect(
        find.text('The sub-recipe "ghost" is not in the library.'),
        findsOneWidget,
      );
    });
  });

  group('with the software keyboard up on a short viewport', () {
    // A landscape phone with the keyboard open. Every other viewport in
    // this file is 2400 to 4000 pixels tall, which is why nothing else here
    // can reach the height where the dialog card has to shrink: `Dialog`
    // adds the keyboard inset to its own padding, so the card gets 142
    // pixels and content laid out for more paints outside it.
    //
    // No exception marks that. `Align` centres an oversized child instead
    // of clipping it, so the overflow is silent and `takeException` reads
    // `null` either way — the assertions below are rects for that reason.
    const viewportWidth = 844.0;
    const viewportHeight = 390.0;
    const viewport = Size(viewportWidth, viewportHeight);
    const keyboardInset = 200.0;
    const keyboardLine = viewportHeight - keyboardInset;

    /// Fails unless [finder] can be brought into the space the keyboard
    /// leaves, and sits within the viewport's width once it is.
    ///
    /// `ensureVisible` first, because the fix is a scroll view: a control
    /// scrolled out of a shrunken card is still reachable, one laid out
    /// past the keyboard line is not, and only a rect read after scrolling
    /// separates the two. With no scrollable ancestor `ensureVisible` is a
    /// no-op, so an unscrollable dialog reports the rect it really painted
    /// at rather than throwing — which is what makes this reject the
    /// non-scrollable layout instead of merely asserting a `Scrollable`
    /// exists somewhere above the control.
    Future<void> expectReachable(WidgetTester tester, Finder finder) async {
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final rect = tester.getRect(finder);
      expect(
        rect.bottom,
        lessThanOrEqualTo(keyboardLine),
        reason: 'the control is painted past the keyboard line at $rect',
      );
      // The dialog's width comes from `AlertDialog`'s `IntrinsicWidth`, and
      // the scroll view now sits between the two. A card that collapsed to
      // its minimum width would push these controls out sideways — the same
      // silent overflow this group exists to reject, on the other axis.
      expect(rect.left, greaterThanOrEqualTo(0.0));
      expect(rect.right, lessThanOrEqualTo(viewportWidth));
    }

    /// Shrinks the open dialog to a landscape phone with the keyboard up.
    ///
    /// The dialog is opened on the roomy viewport first and the screen is
    /// resized under it, because the buttons that open these dialogs sit
    /// below a lazy list and are not built at all at 390 pixels tall. That
    /// is also the real order of events: the operator taps the action on a
    /// full-height screen, and the keyboard rises once the dialog's field
    /// takes focus.
    Future<void> raiseKeyboard(WidgetTester tester) async {
      tester.view.physicalSize = viewport;
      tester.view.viewInsets = const FakeViewPadding(bottom: keyboardInset);
      await tester.pumpAndSettle();
    }

    testWidgets('the ingredient picker can reach its unit control', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));
      await raiseKeyboard(tester);

      // The last control in the picker, and the one a new ingredient's
      // default unit comes from: unreachable, the operator can only create
      // ingredients measured in grams.
      await expectReachable(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButtonFormField<Unit>),
        ),
      );
    });

    testWidgets('a stocked library does not push the unit control away', (
      tester,
    ) async {
      // The matches used to sit in a bounded list that scrolled inside the
      // card; they are plain children of the dialog's own scroll view now,
      // so the list's length is what separates the field at the top from
      // the unit control at the bottom. Twenty is well past what the
      // development seed creates, and the editor is the only place
      // ingredients come from, so the library only grows from there.
      for (var i = 0; i < 20; i++) {
        await ingredients.upsert(
          buildIngredient(id: 'stock-$i', name: 'Stock ingredient $i'),
        );
      }

      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(OutlinedButton, 'Add ingredient'));
      await raiseKeyboard(tester);

      await expectReachable(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(DropdownButtonFormField<Unit>),
        ),
      );
    });

    testWidgets('the custom unit dialog can reach its kind control', (
      tester,
    ) async {
      await _openEditor(tester, recipes: recipes, ingredients: ingredients);
      await _tap(tester, find.widgetWithText(TextButton, 'Add a custom unit'));
      await raiseKeyboard(tester);

      // Count versus yield is not recoverable from the symbol afterwards,
      // so a segmented button the operator cannot reach silently fixes
      // every declared unit to the default.
      await expectReachable(
        tester,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(SegmentedButton<bool>),
        ),
      );
    });
  });
}
