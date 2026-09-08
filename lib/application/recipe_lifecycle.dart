import 'package:prep_book/application/save_recipe_revision.dart';
import 'package:prep_book/application/start_production_run.dart' show Clock;
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
  ///
  /// Throws [MissingDependencyError] when [recipeId] has no stored revision,
  /// matching `StartProductionRun` and `DuplicateRecipe` for the same
  /// condition. `setArchived`'s own SQL discards its affected-row count, so
  /// without this read first, zero rows matched would be indistinguishable
  /// from success.
  Future<void> call(String recipeId, {required bool isArchived}) async {
    final latest = await _recipes.findLatest(recipeId);
    if (latest == null) throw MissingDependencyError(recipeId, recipeId);
    await _recipes.setArchived(recipeId, isArchived: isArchived);
  }
}

/// Copies a recipe's latest revision under a new id.
final class DuplicateRecipe {
  /// Creates the use case over [_recipes], passing [_clock] on to
  /// [SaveRecipeRevision] so the copy's `modifiedAt` is stamped from it.
  const DuplicateRecipe(this._recipes, this._clock);

  final RecipeRepository _recipes;
  final Clock _clock;

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
  /// Throws [MissingDependencyError] when [sourceId] has no stored revision,
  /// and [ArgumentError] when [newId] already names a stored recipe. The
  /// spec requires the copy to land "under a new id at revision 1"; without
  /// this guard, an occupied [newId] would fall through to
  /// [SaveRecipeRevision] and silently become the *next* revision of
  /// whatever already lives there, overwriting the occupant's identity
  /// under its own name rather than creating a copy.
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

    final occupant = await _recipes.findLatest(newId);
    if (occupant != null) {
      // No `DomainError` fits "this id is already taken" — every existing
      // one names a missing or invalid reference, not an occupied one — so
      // this is a plain `ArgumentError`, the idiomatic Dart choice for a
      // caller-supplied value that is invalid on its own terms.
      throw ArgumentError.value(
        newId,
        'newId',
        'already names a stored recipe; duplicate under an unused id',
      );
    }

    return await SaveRecipeRevision(_recipes, _clock).call(
      Recipe(
        id: newId,
        // Ignored by SaveRecipeRevision, which assigns the real number. The
        // guard above is what makes that number 1: with `newId` proven to
        // have no stored revision, `(latest?.revision ?? 0) + 1` can only be
        // 1, which is what makes this method's "at revision 1" contract
        // true rather than merely stated.
        revision: 1,
        name: name,
        baseYield: source.baseYield,
        components: source.components,
        // Ignored by SaveRecipeRevision, which stamps `_clock`'s instant
        // instead: a copy is saved now, not whenever its source last was.
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
