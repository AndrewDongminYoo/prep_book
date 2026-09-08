import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../fakes.dart';

final class _FixedClock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 8, 12);
}

final _piece = Unit.count('piece');
final _tray = Unit.namedYield('tray');

/// An editor over in-memory storage. The same four use cases the screen
/// builds, so nothing here is a shortcut past the boundary the editor keeps.
RecipeEditorCubit _editor({
  FakeRecipeRepository? recipes,
  FakeIngredientRepository? ingredients,
  Recipe? recipe,
}) {
  final storedRecipes = recipes ?? FakeRecipeRepository();
  final storedIngredients = ingredients ?? FakeIngredientRepository();
  return RecipeEditorCubit(
    ListLibrary(storedRecipes),
    ListIngredients(storedIngredients),
    SaveRecipeRevision(storedRecipes, _FixedClock()),
    SaveIngredient(storedIngredients),
    recipe: recipe,
  );
}

/// The least a form needs before [RecipeEditorCubit.save] will write.
void _fillRequiredFields(RecipeEditorCubit cubit, {String name = 'Ciabatta'}) =>
    cubit
      ..nameChanged(name)
      ..baseYieldAmountChanged('1000');

void main() {
  group('loading', () {
    test('reads both libraries into the pickers', () async {
      final recipes = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'dough', name: 'Dough'));
      final ingredients = FakeIngredientRepository();
      await ingredients.upsert(buildIngredient(id: 'flour'));

      final cubit = _editor(recipes: recipes, ingredients: ingredients);
      await cubit.load();

      expect(cubit.state.status, RecipeEditorStatus.ready);
      expect(cubit.state.ingredients.map((i) => i.id), ['flour']);
      expect(cubit.state.libraryRecipes.map((r) => r.id), ['dough']);
    });

    test('a failed read leaves the form unusable rather than empty', () async {
      final ingredients = DeferredIngredientRepository();
      final cubit = RecipeEditorCubit(
        ListLibrary(FakeRecipeRepository()),
        ListIngredients(ingredients),
        SaveRecipeRevision(FakeRecipeRepository(), _FixedClock()),
        SaveIngredient(ingredients),
      );

      final loading = cubit.load();
      expect(cubit.state.status, RecipeEditorStatus.loading);
      ingredients.fail(0);
      await loading;

      // Not `ready` with empty pickers: an empty ingredient list and a
      // failed read look identical on screen, and only one of them is
      // fixed by trying again.
      expect(cubit.state.status, RecipeEditorStatus.loadFailure);
    });

    test('a read landing after the cubit closed emits nothing', () async {
      final ingredients = DeferredIngredientRepository();
      final cubit = RecipeEditorCubit(
        ListLibrary(FakeRecipeRepository()),
        ListIngredients(ingredients),
        SaveRecipeRevision(FakeRecipeRepository(), _FixedClock()),
        SaveIngredient(ingredients),
      );

      final loading = cubit.load();
      await cubit.close();
      ingredients.complete(0, []);

      // Without the `isClosed` guard this throws a StateError out of the
      // await below, which is what a popped editor would do to a slow read.
      await expectLater(loading, completes);
    });
  });

  group('an empty form', () {
    test('starts new, blank, and invalid', () {
      final cubit = _editor();

      expect(cubit.state.isNewRecipe, isTrue);
      expect(cubit.state.recipeId, '');
      expect(cubit.state.components, isEmpty);
      expect(cubit.state.nameIsMissing, isTrue);
      expect(cubit.state.baseYieldIsInvalid, isTrue);
      expect(cubit.state.hasFieldErrors, isTrue);
      expect(cubit.state.submitted, isFalse);
    });

    test('records every metadata field the operator types', () {
      final cubit = _editor()
        ..nameChanged('Ciabatta')
        ..categoryChanged('Breads')
        ..baseYieldAmountChanged('1000')
        ..baseYieldUnitChanged(Unit.kilogram)
        ..maxBatchAmountChanged('500')
        ..maxBatchUnitChanged(Unit.gram)
        ..preparationNotesChanged('Rest overnight\nBake hot');

      expect(cubit.state.name, 'Ciabatta');
      expect(cubit.state.category, 'Breads');
      expect(cubit.state.baseYieldAmount, '1000');
      expect(cubit.state.baseYieldUnit, Unit.kilogram);
      expect(cubit.state.maxBatchAmount, '500');
      expect(cubit.state.maxBatchUnit, Unit.gram);
      expect(cubit.state.preparationNotes, 'Rest overnight\nBake hot');
      expect(cubit.state.hasFieldErrors, isFalse);
    });
  });

  group('field validation', () {
    test('rejects an amount that is not a positive number', () {
      final cubit = _editor()
        ..nameChanged('Ciabatta')
        ..baseYieldAmountChanged('nope');

      expect(cubit.state.baseYieldIsInvalid, isTrue);

      cubit.baseYieldAmountChanged('0');
      expect(cubit.state.baseYieldIsInvalid, isTrue);

      // `Quantity.fromRational` throws on a negative amount, which would
      // otherwise surface as a save failure the operator cannot read.
      cubit.baseYieldAmountChanged('-5');
      expect(cubit.state.baseYieldIsInvalid, isTrue);

      cubit.baseYieldAmountChanged('2.5');
      expect(cubit.state.baseYieldIsInvalid, isFalse);
      expect(cubit.state.hasFieldErrors, isFalse);
    });

    test('an absent maximum batch yield is not an error', () {
      final cubit = _editor();
      _fillRequiredFields(cubit);

      expect(cubit.state.maxBatchIsBlank, isTrue);
      expect(cubit.state.maxBatchIsInvalid, isFalse);
      expect(cubit.state.maxBatchUnitIsIncompatible, isFalse);
      expect(cubit.state.hasFieldErrors, isFalse);
    });

    test('a maximum batch yield must be positive and convertible', () {
      final cubit = _editor();
      _fillRequiredFields(cubit);

      cubit.maxBatchAmountChanged('0');
      expect(cubit.state.maxBatchIsInvalid, isTrue);
      expect(cubit.state.hasFieldErrors, isTrue);

      cubit
        ..maxBatchAmountChanged('500')
        ..maxBatchUnitChanged(_piece);
      expect(cubit.state.maxBatchIsInvalid, isFalse);
      expect(cubit.state.maxBatchUnitIsIncompatible, isTrue);
      expect(cubit.state.hasFieldErrors, isTrue);

      cubit.maxBatchUnitChanged(Unit.kilogram);
      expect(cubit.state.maxBatchUnitIsIncompatible, isFalse);
      expect(cubit.state.hasFieldErrors, isFalse);
    });

    test('a component needs an amount unless it is manual', () {
      final cubit = _editor()
        ..addIngredientComponent(buildIngredient(id: 'flour'));
      _fillRequiredFields(cubit);
      final draft = cubit.state.components.single;

      expect(cubit.state.amountIsInvalid(draft), isTrue);
      expect(cubit.state.hasFieldErrors, isTrue);

      cubit.componentBehaviorChanged(draft.id, ScalingBehavior.manual);
      expect(
        cubit.state.amountIsInvalid(cubit.state.components.single),
        isFalse,
      );
      expect(cubit.state.hasFieldErrors, isFalse);
    });

    test('a declared rounding increment must be positive', () {
      final cubit = _editor()
        ..addIngredientComponent(buildIngredient(id: 'flour'));
      _fillRequiredFields(cubit);
      final id = cubit.state.components.single.id;
      cubit.componentAmountChanged(id, '500');

      expect(
        cubit.state.roundingIsInvalid(cubit.state.components.single),
        isFalse,
      );

      cubit.componentRoundingChanged(id, '0');
      expect(
        cubit.state.roundingIsInvalid(cubit.state.components.single),
        isTrue,
      );
      expect(cubit.state.hasFieldErrors, isTrue);

      // A manual line produces no numeric result, so nothing rounds it and
      // an increment left behind on it cannot block the save.
      cubit.componentBehaviorChanged(id, ScalingBehavior.manual);
      expect(
        cubit.state.roundingIsInvalid(cubit.state.components.single),
        isFalse,
      );

      cubit
        ..componentBehaviorChanged(id, ScalingBehavior.proportional)
        ..componentRoundingChanged(id, '5');
      expect(
        cubit.state.roundingIsInvalid(cubit.state.components.single),
        isFalse,
      );
      expect(cubit.state.hasFieldErrors, isFalse);
    });
  });

  group('the unit picker', () {
    test('offers every unit the domain declares as a fixed instance', () {
      final source = File('lib/domain/units/unit.dart').readAsStringSync();
      final declared = RegExp(
        r'static final Unit \w+',
      ).allMatches(source).length;

      // Rejects dropping a unit from the picker's list, and fails the day
      // the domain gains one that the picker was not told about. Eight
      // named instances, and the picker starts with exactly those: a blank
      // form's base yield and maximum batch unit are both grams, which the
      // list already holds.
      expect(declared, greaterThan(0));
      expect(_editor().state.unitChoices, hasLength(declared));
    });

    test('offers units the data uses that no fixed list could name', () async {
      final recipes = FakeRecipeRepository()
        ..seed(
          buildRecipe(id: 'focaccia', baseYield: Quantity.parse('2', _tray)),
        );
      final ingredients = FakeIngredientRepository();
      await ingredients.upsert(
        Ingredient(id: 'eggs', name: 'Eggs', defaultUnit: _piece),
      );

      final cubit = _editor(recipes: recipes, ingredients: ingredients);
      await cubit.load();

      // `Unit.count` and `Unit.namedYield` build a unit from any string, so
      // a picker restricted to the fixed table could not express either of
      // these — and both are already in the development seed.
      expect(cubit.state.unitChoices, contains(_tray));
      expect(cubit.state.unitChoices, contains(_piece));
    });

    test('offers a unit the operator declares, once, in order', () {
      final cubit = _editor()..addCustomUnit(Unit.count('sheet'));

      expect(cubit.state.unitChoices.last, Unit.count('sheet'));
      expect(
        cubit.state.unitChoices.where((u) => u == Unit.gram),
        hasLength(1),
      );
    });
  });

  group('the sub-recipe picker', () {
    test('leaves archived recipes out and the edited one in', () async {
      final recipes = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'live', name: 'Live'))
        ..seed(buildRecipe(id: 'shelved', name: 'Shelved', isArchived: true));
      final cubit = _editor(
        recipes: recipes,
        recipe: buildRecipe(id: 'live', name: 'Live'),
      );
      await cubit.load();

      // An archived dependency blocks a production run, so offering one
      // here builds a recipe that cannot be run. The recipe being edited
      // stays: filtering it would be a partial cycle check in the screen,
      // and the domain rejects the whole class by path.
      expect(cubit.state.subRecipeChoices.map((r) => r.id), ['live']);
    });
  });

  group("a sub-recipe line's unit", () {
    test(
      "offers only what the referenced recipe's yield converts to",
      () async {
        final recipes = FakeRecipeRepository()
          ..seed(
            buildRecipe(
              id: 'dough',
              name: 'Dough',
              baseYield: Quantity.parse('4', _tray),
            ),
          );
        final cubit = _editor(recipes: recipes);
        await cubit.load();
        cubit.addSubRecipeComponent(cubit.state.libraryRecipes.single);

        // The line's quantity is the target yield the referenced recipe is run
        // against, and a yield-only unit converts to nothing but itself: every
        // other choice here would store a recipe whose every production run
        // throws.
        expect(cubit.state.unitChoicesFor(cubit.state.components.single), [
          _tray,
        ]);
        expect(cubit.state.unitChoices, contains(Unit.gram));
      },
    );

    test('narrows to the dimension, not to the one unit', () async {
      final recipes = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'dough', name: 'Dough'));
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      cubit.addSubRecipeComponent(cubit.state.libraryRecipes.single);

      // Dough yields grams, and a run may ask for it in any mass unit.
      final choices = cubit.state.unitChoicesFor(cubit.state.components.single);
      expect(choices, containsAll([Unit.milligram, Unit.gram, Unit.kilogram]));
      expect(choices, isNot(contains(Unit.liter)));
    });

    test('retargeting keeps a unit the new recipe converts to', () async {
      final recipes = FakeRecipeRepository()
        ..seed(
          buildRecipe(
            id: 'filling',
            name: 'Filling',
            baseYield: Quantity.parse('1000', Unit.gram),
          ),
        )
        ..seed(
          buildRecipe(
            id: 'sauce',
            name: 'Sauce',
            baseYield: Quantity.parse('2', Unit.kilogram),
          ),
        );
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      _fillRequiredFields(cubit);
      cubit.addSubRecipeComponent((await recipes.findLatest('filling'))!);
      final id = cubit.state.components.single.id;
      final sauce = (await recipes.findLatest('sauce'))!;

      cubit
        ..componentAmountChanged(id, '500')
        ..subRecipeTargetChanged(id, sauce);
      await cubit.save();

      // Asserted through the save rather than on the draft, because the
      // damage is in what `_recipeFrom` writes: checking the draft's unit
      // passes without the quantity ever being built. Rejects an
      // implementation that adopts the new target's yield unit
      // unconditionally, which stores 500 kg — a thousand times what was
      // typed, from an action that said nothing about the amount, and which
      // nothing downstream refuses because grams convert to kilograms.
      final stored = (await recipes.findLatest('ciabatta'))!;
      expect(stored.components.single.target, const SubRecipeRef('sauce'));
      expect(
        stored.components.single.baseQuantity,
        Quantity.parse('500', Unit.gram),
      );
    });

    test('retargeting replaces a unit the new recipe cannot reach', () async {
      final recipes = FakeRecipeRepository()
        ..seed(
          buildRecipe(
            id: 'dough',
            name: 'Dough',
            baseYield: Quantity.parse('24', _piece),
          ),
        )
        ..seed(
          buildRecipe(
            id: 'filling',
            name: 'Filling',
            baseYield: Quantity.parse('1000', Unit.gram),
          ),
        );
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      cubit.addSubRecipeComponent((await recipes.findLatest('dough'))!);
      final id = cubit.state.components.single.id;
      final filling = (await recipes.findLatest('filling'))!;

      cubit
        ..componentAmountChanged(id, '6')
        ..subRecipeTargetChanged(id, filling);

      // The other branch, and the one that discriminates: keeping the unit
      // here would leave a line measured in pieces under a recipe yielding
      // grams, which every production run of the saved recipe throws on.
      // Rejects an implementation that never substitutes. The rule is one
      // ternary, reported covered from either side alone, so the test above
      // does not pin this half and this one does not pin that half.
      final draft = cubit.state.components.single;
      expect(draft.unit, Unit.gram);
      expect(cubit.state.subRecipeUnitIsIncompatible(draft), isFalse);
    });

    test('an ingredient line is not narrowed at all', () {
      final cubit = _editor()
        ..addIngredientComponent(buildIngredient(id: 'flour'));
      final draft = cubit.state.components.single;

      expect(cubit.state.unitChoicesFor(draft), cubit.state.unitChoices);
      expect(cubit.state.subRecipeUnitIsIncompatible(draft), isFalse);
    });

    test(
      'refuses the save rather than storing a recipe no run can execute',
      () async {
        final recipes = FakeRecipeRepository()
          ..seed(
            buildRecipe(
              id: 'dough',
              name: 'Dough',
              baseYield: Quantity.parse('4', _tray),
            ),
          );
        final cubit = _editor(recipes: recipes);
        await cubit.load();
        _fillRequiredFields(cubit);
        cubit.addSubRecipeComponent(cubit.state.libraryRecipes.single);
        final id = cubit.state.components.single.id;
        cubit
          ..componentAmountChanged(id, '2')
          ..componentUnitChanged(id, Unit.gram);

        expect(
          cubit.state.subRecipeUnitIsIncompatible(
            cubit.state.components.single,
          ),
          isTrue,
        );
        expect(cubit.state.hasFieldErrors, isTrue);

        await cubit.save();

        // Nothing reached storage: `SaveRecipeRevision` checks the dependency
        // graph and never the units, so a save that got this far would be
        // written and would throw on every production run afterwards.
        expect(recipes.calls, isEmpty);
        expect(cubit.state.submitted, isTrue);
        expect(cubit.state.status, RecipeEditorStatus.ready);
      },
    );

    test(
      'a stored manual line switched to a scaling behavior is caught',
      () async {
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
        final recipes = FakeRecipeRepository()
          ..seed(
            buildRecipe(
              id: 'dough',
              name: 'Dough',
              baseYield: Quantity.parse('4', _tray),
            ),
          )
          ..seed(cake);
        final cubit = _editor(recipes: recipes, recipe: cake);
        await cubit.load();

        // A stored manual component carries no quantity and therefore no unit,
        // so the form starts it at the documented fallback — grams, under a
        // recipe that yields trays. Manual is fine: it never expands.
        expect(cubit.state.components.single.unit, Unit.gram);
        expect(cubit.state.hasFieldErrors, isFalse);

        cubit
          ..componentBehaviorChanged('sub-dough', ScalingBehavior.proportional)
          ..componentAmountChanged('sub-dough', '2');
        final draft = cubit.state.components.single;

        // Reached without touching the unit control, so narrowing the choices
        // cannot prevent it and the field check is what stops the save.
        expect(cubit.state.subRecipeUnitIsIncompatible(draft), isTrue);
        expect(cubit.state.hasFieldErrors, isTrue);
        // The wrong unit stays on offer: a dropdown whose value is absent from
        // its items throws, and the operator has to see what to replace.
        expect(cubit.state.unitChoicesFor(draft), [_tray, Unit.gram]);
      },
    );

    test('a reference the library does not hold is left to the save', () async {
      final cubit = _editor();
      await cubit.load();
      _fillRequiredFields(cubit);
      cubit.addSubRecipeComponent(
        buildRecipe(
          id: 'ghost',
          name: 'Ghost',
          baseYield: Quantity.parse('4', _tray),
        ),
      );
      final id = cubit.state.components.single.id;
      cubit
        ..componentAmountChanged(id, '2')
        ..componentUnitChanged(id, Unit.liter);
      final draft = cubit.state.components.single;

      // Nothing here knows what 'ghost' yields, and reporting a unit error
      // for it would name the wrong problem: it is a missing dependency, and
      // `SaveRecipeRevision` says so by name.
      expect(cubit.state.subRecipeUnitIsIncompatible(draft), isFalse);
      expect(cubit.state.unitChoicesFor(draft), cubit.state.unitChoices);
      expect(cubit.state.hasFieldErrors, isFalse);

      await cubit.save();

      expect(cubit.state.saveError, isA<MissingDependencyError>());
    });
  });

  group('the base yield unit of a recipe others consume', () {
    /// The shape the seed already stores: a filling yielding grams, and a
    /// pastry that consumes a fixed amount of it.
    ///
    /// [consumed] is what the pastry's line measures, or `null` for a manual
    /// line, and [consumes] is which recipe it points at.
    (FakeRecipeRepository, Recipe) buildLibrary({
      Quantity? consumed,
      String consumes = 'cream',
    }) {
      final cream = buildRecipe(
        id: 'cream',
        name: 'Pastry cream',
        baseYield: Quantity.parse('2000', Unit.gram),
      );
      final croissant = buildRecipe(
        id: 'croissant',
        name: 'Almond croissant',
        components: [
          RecipeComponent(
            id: 'sub-cream',
            target: SubRecipeRef(consumes),
            baseQuantity: consumed,
            behavior: consumed == null
                ? ScalingBehavior.manual
                : ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
      );
      final recipes = FakeRecipeRepository()
        ..seed(cream)
        ..seed(croissant);
      return (recipes, cream);
    }

    test('a unit no longer converting to theirs refuses the save', () async {
      final (recipes, cream) = buildLibrary(
        consumed: Quantity.parse('400', Unit.gram),
      );
      final cubit = _editor(recipes: recipes, recipe: cream);
      await cubit.load();

      cubit.baseYieldUnitChanged(Unit.liter);

      // A parent hands its line's total to this recipe as a target yield,
      // so `ProductionCalculator.calculate` throws
      // `IncompatibleYieldUnitError` on it — and nothing between the two
      // catches it: `SaveRecipeRevision` checks the dependency graph, not
      // the units, and every run reads its dependencies at the latest
      // revision, so the edit reaches Almond croissant the moment it lands.
      expect(cubit.state.dependentsBlockedByBaseYieldUnit.map((r) => r.id), [
        'croissant',
      ]);
      expect(cubit.state.hasFieldErrors, isTrue);

      await cubit.save();

      expect(recipes.calls, isEmpty);
      expect(cubit.state.submitted, isTrue);
      expect(cubit.state.status, RecipeEditorStatus.ready);
    });

    test('a unit that still converts to theirs is stored', () async {
      final (recipes, cream) = buildLibrary(
        consumed: Quantity.parse('400', Unit.gram),
      );
      final cubit = _editor(recipes: recipes, recipe: cream);
      await cubit.load();

      // The control the two cases above cannot supply: kilograms convert to
      // the grams Almond croissant measures its line in, so this edit breaks
      // nothing. Rejects a guard that refuses every recipe something
      // consumes rather than only the ones it breaks.
      cubit.baseYieldUnitChanged(Unit.kilogram);

      expect(cubit.state.dependentsBlockedByBaseYieldUnit, isEmpty);
      expect(cubit.state.hasFieldErrors, isFalse);

      await cubit.save();

      expect(recipes.calls, contains('saveRevision:cream:2'));
    });

    test("a parent's manual line is left alone", () async {
      final (recipes, cream) = buildLibrary();
      final cubit = _editor(recipes: recipes, recipe: cream);
      await cubit.load();

      // A manual line carries no quantity, so it is never expanded and
      // never throws. Rejects a guard that reads the reference alone.
      cubit.baseYieldUnitChanged(Unit.liter);

      expect(cubit.state.dependentsBlockedByBaseYieldUnit, isEmpty);
      expect(cubit.state.hasFieldErrors, isFalse);
    });

    test('a line consuming some other recipe is left alone', () async {
      final (recipes, cream) = buildLibrary(
        consumed: Quantity.parse('400', Unit.gram),
        consumes: 'ganache',
      );
      final cubit = _editor(recipes: recipes, recipe: cream);
      await cubit.load();

      // Rejects a guard that flags every sub-recipe line in the library
      // rather than the ones pointing at the recipe being edited.
      cubit.baseYieldUnitChanged(Unit.liter);

      expect(cubit.state.dependentsBlockedByBaseYieldUnit, isEmpty);
      expect(cubit.state.hasFieldErrors, isFalse);
    });
  });

  group('components', () {
    test("an ingredient line starts in that ingredient's unit", () {
      final cubit = _editor()
        ..addIngredientComponent(
          Ingredient(id: 'eggs', name: 'Eggs', defaultUnit: _piece),
        );

      final draft = cubit.state.components.single;
      expect(draft.target, const IngredientRef('eggs'));
      expect(draft.unit, _piece);
      expect(draft.behavior, ScalingBehavior.proportional);
    });

    test("a sub-recipe line starts in that recipe's yield unit", () {
      final cubit = _editor()
        ..addSubRecipeComponent(
          buildRecipe(id: 'dough', baseYield: Quantity.parse('24', _piece)),
        );

      final draft = cubit.state.components.single;
      expect(draft.target, const SubRecipeRef('dough'));
      // The parent quantity is the target yield handed to the sub-recipe,
      // so a line in grams under a recipe yielding pieces cannot run.
      expect(draft.unit, _piece);
    });

    test('records every per-component field', () {
      final cubit = _editor()
        ..addIngredientComponent(buildIngredient(id: 'flour'));
      final id = cubit.state.components.single.id;

      cubit
        ..componentAmountChanged(id, '500')
        ..componentUnitChanged(id, Unit.kilogram)
        ..componentBehaviorChanged(id, ScalingBehavior.perBatch)
        ..componentRoundingChanged(id, '5')
        ..componentNoteChanged(id, 'Sift first');

      final draft = cubit.state.components.single;
      expect(draft.amount, '500');
      expect(draft.unit, Unit.kilogram);
      expect(draft.behavior, ScalingBehavior.perBatch);
      expect(draft.roundingIncrement, '5');
      expect(draft.note, 'Sift first');
    });

    test('editing one line leaves the others alone', () {
      final cubit = _editor()
        ..addIngredientComponent(buildIngredient(id: 'flour'))
        ..addIngredientComponent(buildIngredient(id: 'water', name: 'Water'));
      final first = cubit.state.components.first.id;

      cubit.componentAmountChanged(first, '500');

      expect(cubit.state.components.first.amount, '500');
      expect(cubit.state.components.last.amount, '');
    });

    test('removing one line keeps the rest', () {
      final cubit = _editor()
        ..addIngredientComponent(buildIngredient(id: 'flour'))
        ..addIngredientComponent(buildIngredient(id: 'water', name: 'Water'));
      final first = cubit.state.components.first.id;

      cubit.removeComponent(first);

      expect(
        cubit.state.components.single.target,
        const IngredientRef('water'),
      );
    });

    test('reordering moves the line, not just its number', () {
      final cubit = _editor()
        ..addIngredientComponent(buildIngredient(id: 'flour'))
        ..addIngredientComponent(buildIngredient(id: 'water', name: 'Water'))
        ..reorderComponent(oldIndex: 1, newIndex: 0);

      expect(cubit.state.components.map((d) => d.target), [
        const IngredientRef('water'),
        const IngredientRef('flour'),
      ]);
    });
  });

  group('creating an ingredient', () {
    test('stores it, offers it, and uses it on the new line', () async {
      final ingredients = FakeIngredientRepository();
      final cubit = _editor(ingredients: ingredients);
      await cubit.load();

      await cubit.createIngredient(
        name: '  Almond flakes ',
        defaultUnit: _piece,
      );

      expect(ingredients.stored.values.single.name, 'Almond flakes');
      expect(ingredients.stored.values.single.defaultUnit, _piece);
      expect(cubit.state.ingredients.map((i) => i.name), ['Almond flakes']);
      expect(cubit.state.components.single.unit, _piece);
      expect(
        cubit.state.components.single.target,
        IngredientRef(ingredients.stored.keys.single),
      );
    });

    test('keeps the offered list in name order', () async {
      final ingredients = FakeIngredientRepository();
      await ingredients.upsert(buildIngredient(id: 'sugar', name: 'Sugar'));
      final cubit = _editor(ingredients: ingredients);
      await cubit.load();

      await cubit.createIngredient(name: 'Butter', defaultUnit: Unit.gram);

      // Appending would put Butter last, which is not where the picker's
      // own read would have put it.
      expect(cubit.state.ingredients.map((i) => i.name), ['Butter', 'Sugar']);
    });

    test('a second ingredient of the same name gets its own id', () async {
      final ingredients = FakeIngredientRepository();
      final cubit = _editor(ingredients: ingredients);
      await cubit.load();

      await cubit.createIngredient(name: 'Flour', defaultUnit: Unit.gram);
      await cubit.createIngredient(name: 'Flour', defaultUnit: Unit.gram);

      // A shared id would silently replace the first record, and every
      // component pointing at it with it.
      expect(ingredients.stored.keys, ['flour', 'flour-2']);
    });

    test('a failed write is reported and adds no line', () async {
      final ingredients = DeferredIngredientRepository()..failWrites = true;
      final cubit = RecipeEditorCubit(
        ListLibrary(FakeRecipeRepository()),
        ListIngredients(ingredients),
        SaveRecipeRevision(FakeRecipeRepository(), _FixedClock()),
        SaveIngredient(ingredients),
      );

      await cubit.createIngredient(name: 'Flour', defaultUnit: Unit.gram);

      expect(cubit.state.saveError, isA<StateError>());
      expect(cubit.state.components, isEmpty);
      expect(cubit.state.isWriting, isFalse);
      // Writing an ingredient does not decide what the screen is showing.
      // This cubit never loaded, and a write that reported the form ready
      // would put an empty one on screen with no library behind it.
      expect(cubit.state.status, RecipeEditorStatus.loading);
    });

    test('the form refuses input while the write runs', () async {
      final ingredients = DeferredIngredientRepository()..deferWrites = true;
      final cubit = RecipeEditorCubit(
        ListLibrary(FakeRecipeRepository()),
        ListIngredients(ingredients),
        SaveRecipeRevision(FakeRecipeRepository(), _FixedClock()),
        SaveIngredient(ingredients),
      );
      final loading = cubit.load();
      ingredients.complete(0, []);
      await loading;
      expect(cubit.state.isEditable, isTrue);

      final creating = cubit.createIngredient(
        name: 'Flour',
        defaultUnit: Unit.gram,
      );

      // The write ends by rewriting the state it read when it started, so an
      // edit made here would be dropped without a trace — and a save pressed
      // here would store a recipe without the line the write is adding.
      expect(cubit.state.isWriting, isTrue);
      expect(cubit.state.isEditable, isFalse);

      ingredients.completeWrite(0);
      await creating;

      expect(cubit.state.isEditable, isTrue);
      expect(cubit.state.components, hasLength(1));
    });

    test('a write landing after the cubit closed emits nothing', () async {
      final ingredients = DeferredIngredientRepository();
      final cubit = RecipeEditorCubit(
        ListLibrary(FakeRecipeRepository()),
        ListIngredients(ingredients),
        SaveRecipeRevision(FakeRecipeRepository(), _FixedClock()),
        SaveIngredient(ingredients),
      );

      final creating = cubit.createIngredient(
        name: 'Flour',
        defaultUnit: Unit.gram,
      );
      await cubit.close();

      await expectLater(creating, completes);
    });
  });

  group('saving', () {
    test(
      'a form with field errors writes nothing and starts reporting',
      () async {
        final recipes = FakeRecipeRepository();
        final cubit = _editor(recipes: recipes);
        await cubit.load();

        await cubit.save();

        expect(cubit.state.submitted, isTrue);
        expect(cubit.state.status, RecipeEditorStatus.ready);
        expect(
          recipes.calls.where((call) => call.startsWith('saveRevision:')),
          isEmpty,
        );
      },
    );

    test(
      'a new recipe is stored as revision 1 under a slug of its name',
      () async {
        final recipes = FakeRecipeRepository();
        final cubit = _editor(recipes: recipes);
        await cubit.load();
        _fillRequiredFields(cubit, name: 'Summer focaccia');
        cubit.categoryChanged('Breads');

        await cubit.save();

        final stored = await recipes.findLatest('summer-focaccia');
        expect(stored!.revision, 1);
        expect(stored.name, 'Summer focaccia');
        expect(stored.category, 'Breads');
        expect(stored.baseYield, Quantity.parse('1000', Unit.gram));
        expect(cubit.state.status, RecipeEditorStatus.saved);
        expect(cubit.state.savedRecipe!.id, 'summer-focaccia');
      },
    );

    test('a recipe named like an existing one does not replace it', () async {
      final recipes = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'ciabatta', name: 'Ciabatta'))
        ..seed(buildRecipe(id: 'ciabatta-2', name: 'Ciabatta'));
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      _fillRequiredFields(cubit);

      await cubit.save();

      // Reusing the slug would store this as revision 2 of the existing
      // recipe, replacing it in the library under its own name. The second
      // seeded recipe is what makes the suffix search run more than once.
      expect(cubit.state.savedRecipe!.id, 'ciabatta-3');
      expect((await recipes.findLatest('ciabatta'))!.revision, 1);
    });

    test('a recipe whose name slugs to nothing still gets an id', () async {
      final recipes = FakeRecipeRepository();
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      // A blank name is a field error, so the fallback is only reachable
      // through a name that is non-blank and yet slugs away to nothing.
      _fillRequiredFields(cubit, name: '!!!');

      await cubit.save();

      expect(cubit.state.savedRecipe!.id, 'recipe');
    });

    test('every component field reaches the stored revision', () async {
      final recipes = FakeRecipeRepository();
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      _fillRequiredFields(cubit);
      cubit
        ..preparationNotesChanged('Rest overnight\n\n  Bake hot  ')
        ..maxBatchAmountChanged('500')
        ..addIngredientComponent(buildIngredient(id: 'flour'))
        ..addIngredientComponent(buildIngredient(id: 'salt', name: 'Salt'));
      final flour = cubit.state.components.first.id;
      final salt = cubit.state.components.last.id;
      cubit
        ..componentAmountChanged(flour, '500')
        ..componentRoundingChanged(flour, '5')
        ..componentNoteChanged(flour, '  Sift first  ')
        ..componentBehaviorChanged(salt, ScalingBehavior.manual)
        ..componentNoteChanged(salt, 'To taste');

      await cubit.save();

      final stored = (await recipes.findLatest('ciabatta'))!;
      expect(stored.maxBatchYield, Quantity.parse('500', Unit.gram));
      expect(stored.preparationNotes, ['Rest overnight', 'Bake hot']);
      final first = stored.components.first;
      expect(first.baseQuantity, Quantity.parse('500', Unit.gram));
      expect(first.rounding!.increment, Decimal.parse('5'));
      expect(first.note, 'Sift first');
      expect(first.displayOrder, 0);
      final second = stored.components.last;
      // A free-form amount is a manual component, never a numeric zero.
      expect(second.baseQuantity, isNull);
      expect(second.behavior, ScalingBehavior.manual);
      expect(second.rounding, isNull);
      expect(second.displayOrder, 1);
    });

    test('an amount typed before manual was chosen is dropped', () async {
      final recipes = FakeRecipeRepository();
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      _fillRequiredFields(cubit);
      cubit.addIngredientComponent(buildIngredient(id: 'salt', name: 'Salt'));
      final id = cubit.state.components.single.id;
      cubit
        ..componentAmountChanged(id, '5')
        ..componentRoundingChanged(id, '2')
        ..componentBehaviorChanged(id, ScalingBehavior.manual);

      await cubit.save();

      // `RecipeComponent` rejects a manual line carrying a quantity, so
      // keeping the text on screen and dropping it here is the only way
      // both can be true.
      final stored = (await recipes.findLatest('ciabatta'))!;
      expect(stored.components.single.baseQuantity, isNull);
      expect(cubit.state.components.single.amount, '5');
    });

    test('an empty component list is stored as written', () async {
      final recipes = FakeRecipeRepository();
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      _fillRequiredFields(cubit);

      await cubit.save();

      // The domain accepts a recipe with no components, so the form does
      // not invent a rule against one.
      expect((await recipes.findLatest('ciabatta'))!.components, isEmpty);
    });

    test('the reordered position is what displayOrder records', () async {
      final recipes = FakeRecipeRepository();
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      _fillRequiredFields(cubit);
      cubit
        ..addIngredientComponent(buildIngredient(id: 'flour'))
        ..addIngredientComponent(buildIngredient(id: 'water', name: 'Water'));
      for (final draft in cubit.state.components) {
        cubit.componentAmountChanged(draft.id, '100');
      }

      cubit.reorderComponent(oldIndex: 1, newIndex: 0);
      await cubit.save();

      final stored = (await recipes.findLatest('ciabatta'))!;
      expect(stored.components.map((c) => (c.target, c.displayOrder)), [
        (const IngredientRef('water'), 0),
        (const IngredientRef('flour'), 1),
      ]);
    });

    test('a cycle is reported with the path the domain found', () async {
      final recipes = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'cake', name: 'Cake'))
        ..seed(
          buildRecipe(
            id: 'syrup',
            name: 'Syrup',
            components: [buildSubRecipeComponent('cake')],
          ),
        );
      final cubit = _editor(
        recipes: recipes,
        recipe: await recipes.findLatest('cake'),
      );
      await cubit.load();
      cubit.addSubRecipeComponent((await recipes.findLatest('syrup'))!);
      cubit.componentAmountChanged(cubit.state.components.last.id, '100');

      await cubit.save();

      expect(
        cubit.state.saveError,
        isA<RecipeCycleError>().having((e) => e.path, 'path', [
          'cake',
          'syrup',
          'cake',
        ]),
      );
      // The form stays up with what was typed; the screen renders the path.
      expect(cubit.state.status, RecipeEditorStatus.ready);
      expect(cubit.state.components, hasLength(2));
    });

    test('a missing sub-recipe is reported by name', () async {
      final recipes = FakeRecipeRepository();
      final cubit = _editor(recipes: recipes);
      await cubit.load();
      _fillRequiredFields(cubit);
      cubit.addSubRecipeComponent(buildRecipe(id: 'ghost', name: 'Ghost'));
      cubit.componentAmountChanged(cubit.state.components.single.id, '100');

      await cubit.save();

      expect(
        cubit.state.saveError,
        isA<MissingDependencyError>().having(
          (e) => e.missingId,
          'missingId',
          'ghost',
        ),
      );
    });

    test('a failed write leaves the form up with the error', () async {
      final reads = FakeRecipeRepository();
      final recipes = DeferredWriteRecipeRepository(reads);
      final ingredients = FakeIngredientRepository();
      final cubit = RecipeEditorCubit(
        ListLibrary(recipes),
        ListIngredients(ingredients),
        SaveRecipeRevision(recipes, _FixedClock()),
        SaveIngredient(ingredients),
      );
      await cubit.load();
      _fillRequiredFields(cubit);

      final saving = cubit.save();
      expect(cubit.state.status, RecipeEditorStatus.saving);
      // `SaveRecipeRevision` reads the dependency closure and the latest
      // revision before it writes, so the write does not exist yet on the
      // turn `save` was called.
      await pumpEventQueue();
      recipes.failWrite(0);
      await saving;

      expect(cubit.state.status, RecipeEditorStatus.ready);
      expect(cubit.state.saveError, isNotNull);
    });

    test('the form refuses input while the save runs, and after it', () async {
      final reads = FakeRecipeRepository();
      final recipes = DeferredWriteRecipeRepository(reads);
      final ingredients = FakeIngredientRepository();
      final cubit = RecipeEditorCubit(
        ListLibrary(recipes),
        ListIngredients(ingredients),
        SaveRecipeRevision(recipes, _FixedClock()),
        SaveIngredient(ingredients),
      );
      await cubit.load();
      _fillRequiredFields(cubit);

      final saving = cubit.save();
      expect(cubit.state.isWriting, isTrue);
      expect(cubit.state.isEditable, isFalse);

      await pumpEventQueue();
      recipes.completeWrite(0);
      await saving;

      // The write is over, but the screen is on its way out over what was
      // stored, so the form stays closed rather than taking an edit that
      // nothing left will read.
      expect(cubit.state.isWriting, isFalse);
      expect(cubit.state.isEditable, isFalse);
      expect(cubit.state.status, RecipeEditorStatus.saved);
    });

    test('a retry clears the previous error before it runs', () async {
      final reads = FakeRecipeRepository();
      final recipes = DeferredWriteRecipeRepository(reads);
      final ingredients = FakeIngredientRepository();
      final cubit = RecipeEditorCubit(
        ListLibrary(recipes),
        ListIngredients(ingredients),
        SaveRecipeRevision(recipes, _FixedClock()),
        SaveIngredient(ingredients),
      );
      await cubit.load();
      _fillRequiredFields(cubit);
      final first = cubit.save();
      await pumpEventQueue();
      recipes.failWrite(0);
      await first;

      final second = cubit.save();
      expect(cubit.state.saveError, isNull);
      await pumpEventQueue();
      recipes.completeWrite(1);
      await second;

      expect(cubit.state.status, RecipeEditorStatus.saved);
    });

    test('a write landing after the cubit closed emits nothing', () async {
      final reads = FakeRecipeRepository();
      final recipes = DeferredWriteRecipeRepository(reads);
      final ingredients = FakeIngredientRepository();
      final cubit = RecipeEditorCubit(
        ListLibrary(recipes),
        ListIngredients(ingredients),
        SaveRecipeRevision(recipes, _FixedClock()),
        SaveIngredient(ingredients),
      );
      await cubit.load();
      _fillRequiredFields(cubit);

      final saving = cubit.save();
      await pumpEventQueue();
      await cubit.close();
      recipes.completeWrite(0);

      await expectLater(saving, completes);
    });
  });

  group('editing a stored recipe', () {
    late FakeRecipeRepository recipes;
    late Recipe stored;

    setUp(() async {
      stored = Recipe(
        id: 'croissant-dough',
        revision: 3,
        name: 'Croissant dough',
        category: 'Doughs',
        baseYield: Quantity.parse('24', _piece),
        maxBatchYield: Quantity.parse('12', _piece),
        modifiedAt: DateTime.utc(2026, 9, 3, 6),
        preparationNotes: const ['Laminate cold', 'Three folds'],
        isArchived: true,
        components: [
          RecipeComponent(
            id: 'component-3',
            target: const IngredientRef('flour'),
            baseQuantity: Quantity.parse('1000', Unit.gram),
            behavior: ScalingBehavior.proportional,
            rounding: RoundingRule.upToIncrement(Decimal.parse('5')),
            note: 'Sift',
            displayOrder: 1,
          ),
          RecipeComponent(
            id: 'dusting',
            target: const IngredientRef('flour'),
            baseQuantity: null,
            behavior: ScalingBehavior.manual,
            displayOrder: 0,
          ),
        ],
      );
      recipes = FakeRecipeRepository()..seed(stored);
    });

    test('fills the form from the revision, in display order', () {
      final cubit = _editor(recipes: recipes, recipe: stored);

      expect(cubit.state.isNewRecipe, isFalse);
      expect(cubit.state.recipeId, 'croissant-dough');
      expect(cubit.state.name, 'Croissant dough');
      expect(cubit.state.category, 'Doughs');
      expect(cubit.state.baseYieldAmount, '24');
      expect(cubit.state.baseYieldUnit, _piece);
      expect(cubit.state.maxBatchAmount, '12');
      expect(cubit.state.maxBatchUnit, _piece);
      expect(cubit.state.preparationNotes, 'Laminate cold\nThree folds');
      // Stored order is not display order here: the manual line is second
      // in the list and first on screen.
      expect(cubit.state.components.map((d) => d.id), [
        'dusting',
        'component-3',
      ]);
      final manual = cubit.state.components.first;
      expect(manual.amount, '');
      expect(manual.unit, Unit.gram);
      final flour = cubit.state.components.last;
      expect(flour.amount, '1000');
      expect(flour.roundingIncrement, '5');
      expect(flour.note, 'Sift');
    });

    test('a recipe with no maximum batch yield fills neither field', () {
      final cubit = _editor(recipe: buildRecipe(id: 'plain'));

      expect(cubit.state.maxBatchAmount, '');
      // The unit still has to be something the picker can show, and the
      // base yield's is the only sensible starting point.
      expect(cubit.state.maxBatchUnit, Unit.gram);
    });

    test('saves as the next revision under the same id', () async {
      final cubit = _editor(recipes: recipes, recipe: stored);
      await cubit.load();
      cubit.nameChanged('Croissant dough v2');

      await cubit.save();

      final next = (await recipes.findLatest('croissant-dough'))!;
      expect(next.revision, 4);
      expect(next.name, 'Croissant dough v2');
      // Archiving is the library screen's job; a save must not undo it.
      expect(next.isArchived, isTrue);
      expect(next.components.map((c) => c.id), ['dusting', 'component-3']);
    });

    test('an amount nobody retyped keeps its exact value', () async {
      // A third of a gram has no finite decimal form, so the form can only
      // show it as `0.333333` — `Quantity.toDecimal` approximates rather
      // than refusing. A save that rebuilt every amount from what is on
      // screen would write that approximation over a value the operator
      // never touched, on all three of the amounts a recipe carries.
      final third = Rational.fromInt(1, 3);
      final exact = Recipe(
        id: 'starter',
        revision: 1,
        name: 'Starter',
        baseYield: Quantity.fromRational(third, Unit.gram),
        maxBatchYield: Quantity.fromRational(third, Unit.gram),
        modifiedAt: DateTime.utc(2026, 9, 3),
        components: [
          RecipeComponent(
            id: 'flour',
            target: const IngredientRef('flour'),
            baseQuantity: Quantity.fromRational(third, Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
      );
      final exactRecipes = FakeRecipeRepository()..seed(exact);
      final cubit = _editor(recipes: exactRecipes, recipe: exact);
      await cubit.load();

      // On the same line as the amount, and not the amount: a draft that
      // kept the stored value only until some neighbouring field changed
      // would still pass a test that touched nothing at all.
      cubit.componentNoteChanged('flour', 'Sift');
      await cubit.save();

      final next = (await exactRecipes.findLatest('starter'))!;
      expect(next.components.single.baseQuantity!.amount, third);
      expect(next.baseYield.amount, third);
      expect(next.maxBatchYield!.amount, third);
    });

    test('a retyped amount is what gets stored', () async {
      final cubit = _editor(recipes: recipes, recipe: stored);
      await cubit.load();

      cubit.componentAmountChanged('component-3', '1200');
      await cubit.save();

      // The other half of the rule above: keeping the stored quantity is
      // only right for as long as the form is still showing it.
      final next = (await recipes.findLatest('croissant-dough'))!;
      expect(
        next.components.last.baseQuantity,
        Quantity.parse('1200', Unit.gram),
      );
    });

    test('changing only the unit restates the amount in that unit', () async {
      final cubit = _editor(recipes: recipes, recipe: stored);
      await cubit.load();

      cubit.componentUnitChanged('component-3', Unit.kilogram);
      await cubit.save();

      // The typed amount reads the same as the stored one and means
      // something else. Keeping a thousand grams here would store a
      // thousandth of what the operator asked for.
      final next = (await recipes.findLatest('croissant-dough'))!;
      expect(
        next.components.last.baseQuantity,
        Quantity.parse('1000', Unit.kilogram),
      );
    });

    test('a new line cannot collide with a stored component id', () {
      final cubit = _editor(recipes: recipes, recipe: stored)
        ..addIngredientComponent(buildIngredient(id: 'water', name: 'Water'));

      // Numbering from zero would produce `component-1`, then eventually
      // `component-3`, which `Recipe` rejects as a repeated component id at
      // save time with nothing on screen to explain it.
      expect(cubit.state.components.last.id, 'component-4');
    });
  });
}
