import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/bootstrap.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/persistence.dart';

Future<void> main() async {
  await bootstrap((recipes) async {
    await _seedIfEmpty(recipes);
    return App(
      listLibrary: ListLibrary(recipes),
      searchLibrary: SearchLibrary(recipes),
    );
  });
}

/// Writes [_developmentLibrary] into an empty database, so a development
/// build has something to list without duplicating itself on every run.
///
/// Development only, and deliberately so: a temporary fixture written into
/// a production database is not removable afterwards. Nothing here is
/// migrated data — these recipes were written for this file.
Future<void> _seedIfEmpty(RecipeRepository recipes) async {
  if ((await recipes.listLatestRevisions()).isNotEmpty) return;
  for (final recipe in _developmentLibrary()) {
    await recipes.saveRevision(recipe);
  }
}

final _piece = Unit.count('piece');
final _tray = Unit.namedYield('tray');

/// Four recipes covering what the library screen and the production screens
/// after it have to handle: a plain recipe, one with a manual component, one
/// that references two sub-recipes, and one that is archived.
List<Recipe> _developmentLibrary() => [
  Recipe(
    id: 'seed-pastry-cream',
    revision: 1,
    name: 'Pastry cream',
    category: 'Fillings',
    baseYield: Quantity.parse('2000', Unit.gram),
    modifiedAt: DateTime.utc(2026, 9, 1, 8, 30),
    components: [
      RecipeComponent(
        id: 'milk',
        target: const IngredientRef('milk'),
        baseQuantity: Quantity.parse('1600', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'sugar',
        target: const IngredientRef('sugar'),
        baseQuantity: Quantity.parse('300', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 1,
      ),
      RecipeComponent(
        id: 'egg-yolk',
        target: const IngredientRef('egg-yolk'),
        baseQuantity: Quantity.parse('240', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 2,
      ),
      RecipeComponent(
        id: 'cornstarch',
        target: const IngredientRef('cornstarch'),
        baseQuantity: Quantity.parse('120', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 3,
      ),
    ],
  ),
  Recipe(
    id: 'seed-croissant-dough',
    revision: 1,
    name: 'Croissant dough',
    category: 'Doughs',
    baseYield: Quantity.parse('24', _piece),
    // The sheeter takes one twelve-piece block at a time.
    maxBatchYield: Quantity.parse('12', _piece),
    modifiedAt: DateTime.utc(2026, 9, 3, 6),
    preparationNotes: const [
      'Laminate cold, three single folds, 20 minutes rest between folds.',
    ],
    components: [
      RecipeComponent(
        id: 'flour',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1000', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'butter',
        target: const IngredientRef('butter'),
        baseQuantity: Quantity.parse('500', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 1,
      ),
      RecipeComponent(
        id: 'water',
        target: const IngredientRef('water'),
        baseQuantity: Quantity.parse('480', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 2,
      ),
      // Free-form: the baker dusts as needed, so this line carries no
      // amount and produces a review warning rather than a numeric zero.
      RecipeComponent(
        id: 'dusting-flour',
        target: const IngredientRef('flour'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 3,
        note: 'For dusting the bench, as needed.',
      ),
    ],
  ),
  Recipe(
    id: 'seed-almond-croissant',
    revision: 1,
    name: 'Almond croissant',
    category: 'Viennoiserie',
    baseYield: Quantity.parse('12', _piece),
    modifiedAt: DateTime.utc(2026, 9, 5, 5, 15),
    components: [
      RecipeComponent(
        id: 'dough',
        target: const SubRecipeRef('seed-croissant-dough'),
        baseQuantity: Quantity.parse('12', _piece),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'cream',
        target: const SubRecipeRef('seed-pastry-cream'),
        baseQuantity: Quantity.parse('400', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 1,
      ),
      RecipeComponent(
        id: 'almond-flakes',
        target: const IngredientRef('almond-flakes'),
        baseQuantity: Quantity.parse('120', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 2,
      ),
    ],
  ),
  Recipe(
    id: 'seed-summer-focaccia',
    revision: 1,
    name: 'Summer focaccia',
    category: 'Breads',
    baseYield: Quantity.parse('2', _tray),
    modifiedAt: DateTime.utc(2026, 9, 2, 7),
    // Off the menu until next summer, so the library screen's archived
    // toggle has something to show.
    isArchived: true,
    components: [
      RecipeComponent(
        id: 'flour',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1200', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'olive-oil',
        target: const IngredientRef('olive-oil'),
        baseQuantity: Quantity.parse('180', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 1,
      ),
      // One tray of tomatoes per tray of focaccia, whatever the run size.
      RecipeComponent(
        id: 'tomatoes',
        target: const IngredientRef('tomatoes'),
        baseQuantity: Quantity.parse('400', Unit.gram),
        behavior: ScalingBehavior.perBatch,
        displayOrder: 2,
      ),
    ],
  ),
];
