import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/bootstrap.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:prep_book/presentation/presentation.dart';

Future<void> main() async {
  await bootstrap((recipes, ingredients) async {
    await _seedDevelopmentData(recipes, ingredients);
    return App(
      listLibrary: ListLibrary(recipes),
      searchLibrary: SearchLibrary(recipes),
      editor: RecipeEditorLauncher(
        listLibrary: ListLibrary(recipes),
        listIngredients: ListIngredients(ingredients),
        saveRecipeRevision: SaveRecipeRevision(recipes, const SystemClock()),
        saveIngredient: SaveIngredient(ingredients),
      ),
    );
  });
}

/// Writes [_developmentLibrary] and [_developmentIngredients] into a
/// development database, so a development build has something to list
/// without duplicating itself on every run.
///
/// Development only, and deliberately so: a temporary fixture written into
/// a production database is not removable afterwards. Nothing here is
/// migrated data — these recipes were written for this file.
///
/// Only the recipes are guarded on an empty library, and the asymmetry is
/// the point. `saveRevision` only ever inserts a revision, so re-running
/// that loop over fixtures pinned at revision 1 would throw rather than
/// heal. `upsert` replaces a row carrying the same id, so the ingredients
/// are written unconditionally: a launch that stored some of them and then
/// failed is repaired by the next one, where a guard on a nonempty table
/// would leave the rest missing for good and the editor would name their
/// components by identifier. That reserves these ids: renaming one of these
/// ingredients in the editor does not survive the next development launch,
/// while an ingredient the editor creates under its own id is untouched.
Future<void> _seedDevelopmentData(
  RecipeRepository recipes,
  IngredientRepository ingredients,
) async {
  for (final ingredient in _developmentIngredients()) {
    await ingredients.upsert(ingredient);
  }
  if ((await recipes.listLatestRevisions()).isNotEmpty) return;
  for (final recipe in _developmentLibrary()) {
    await recipes.saveRevision(recipe);
  }
}

/// A record for every ingredient identifier [_developmentLibrary] references.
///
/// The components have always named these; nothing stored what they are
/// called, so the editor had no name to show for any of them. Every one is
/// written in grams because that is the unit each component already uses.
List<Ingredient> _developmentIngredients() => [
  Ingredient(
    id: 'almond-flakes',
    name: 'Almond flakes',
    defaultUnit: Unit.gram,
  ),
  Ingredient(id: 'butter', name: 'Butter', defaultUnit: Unit.gram),
  Ingredient(id: 'cornstarch', name: 'Cornstarch', defaultUnit: Unit.gram),
  Ingredient(id: 'egg-yolk', name: 'Egg yolk', defaultUnit: Unit.gram),
  Ingredient(id: 'flour', name: 'Flour', defaultUnit: Unit.gram),
  Ingredient(id: 'milk', name: 'Milk', defaultUnit: Unit.gram),
  Ingredient(id: 'olive-oil', name: 'Olive oil', defaultUnit: Unit.gram),
  Ingredient(id: 'sugar', name: 'Sugar', defaultUnit: Unit.gram),
  Ingredient(id: 'tomatoes', name: 'Tomatoes', defaultUnit: Unit.gram),
  Ingredient(id: 'water', name: 'Water', defaultUnit: Unit.gram),
];

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
