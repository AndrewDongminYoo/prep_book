import 'package:prep_book/application/dependency_closure.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Writes an edited recipe as the next revision of its id.
final class SaveRecipeRevision {
  /// Creates the use case over [_recipes].
  const SaveRecipeRevision(this._recipes);

  final RecipeRepository _recipes;

  /// Stores [edited] as revision N+1 and returns it as stored.
  ///
  /// The revision on [edited] is ignored. Letting a caller supply it would
  /// put a read-modify-write in every screen and let two parallel edits
  /// choose the same number, which `saveRevision` refuses rather than
  /// merges.
  ///
  /// Throws [RecipeCycleError] naming the path, or [MissingDependencyError],
  /// before anything is written.
  Future<Recipe> call(Recipe edited) async {
    final closure = await resolveDependencyClosure(_recipes, edited);
    RecipeDependencyGraph(closure).assertResolvable(edited.id);

    final latest = await _recipes.findLatest(edited.id);
    final next = _withRevision(edited, (latest?.revision ?? 0) + 1);
    await _recipes.saveRevision(next);
    return next;
  }

  /// [Recipe] has no `copyWith`, so every field is restated here.
  static Recipe _withRevision(Recipe recipe, int revision) => Recipe(
    id: recipe.id,
    revision: revision,
    name: recipe.name,
    baseYield: recipe.baseYield,
    components: recipe.components,
    modifiedAt: recipe.modifiedAt,
    category: recipe.category,
    maxBatchYield: recipe.maxBatchYield,
    preparationNotes: recipe.preparationNotes,
    isArchived: recipe.isArchived,
  );
}
