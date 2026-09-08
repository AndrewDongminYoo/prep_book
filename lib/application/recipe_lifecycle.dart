import 'package:prep_book/application/save_recipe_revision.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Archives or restores every revision of a recipe.
final class ArchiveRecipe {
  /// Creates the use case over [_recipes].
  const ArchiveRecipe(this._recipes);

  final RecipeRepository _recipes;

  /// Sets the archived flag on every revision of [recipeId].
  ///
  /// Archiving is not deletion: the design document keeps an archived
  /// recipe readable, and a stored production run computed from it is
  /// unaffected either way.
  Future<void> call(String recipeId, {required bool isArchived}) =>
      _recipes.setArchived(recipeId, isArchived: isArchived);
}

/// Copies a recipe's latest revision under a new id.
final class DuplicateRecipe {
  /// Creates the use case over [_recipes].
  const DuplicateRecipe(this._recipes);

  final RecipeRepository _recipes;

  /// Writes the latest revision of [sourceId] as revision 1 of [newId].
  ///
  /// [name] is the caller's, not derived: what a copy is called is a
  /// product decision, and a screen can prefill a field with whatever it
  /// likes.
  ///
  /// The copy goes through [SaveRecipeRevision], so it is validated exactly
  /// as an edit is — a source whose dependencies have since been deleted
  /// fails here rather than producing an unusable copy.
  ///
  /// Throws [MissingDependencyError] when [sourceId] has no stored revision.
  Future<Recipe> call({
    required String sourceId,
    required String newId,
    required String name,
  }) async {
    final source = await _recipes.findLatest(sourceId);
    // Both arguments are `sourceId` on purpose. `MissingDependencyError`
    // renders "recipe X is not in the index" when they match and
    // "recipe X references missing recipe Y" when they differ, and nothing
    // references the source here — the operator asked for it directly.
    if (source == null) throw MissingDependencyError(sourceId, sourceId);

    return await SaveRecipeRevision(_recipes).call(
      Recipe(
        id: newId,
        // Ignored by SaveRecipeRevision, which assigns the real number.
        revision: 1,
        name: name,
        baseYield: source.baseYield,
        components: source.components,
        modifiedAt: source.modifiedAt,
        category: source.category,
        maxBatchYield: source.maxBatchYield,
        preparationNotes: source.preparationNotes,
        // A copy is a live recipe even when its source was archived;
        // otherwise duplicating to revive a recipe produces another
        // archived one.
      ),
    );
  }
}
