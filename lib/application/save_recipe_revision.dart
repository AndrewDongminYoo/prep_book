import 'package:prep_book/application/dependency_closure.dart';
import 'package:prep_book/application/start_production_run.dart' show Clock;
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Writes an edited recipe as the next revision of its id.
final class SaveRecipeRevision {
  /// Creates the use case over [_recipes], stamping the saved revision's
  /// `modifiedAt` from [_clock].
  const new(this._recipes, this._clock);

  final RecipeRepository _recipes;
  final Clock _clock;

  /// Stores [edited] as revision N+1 and returns it as stored.
  ///
  /// The revision on [edited] is ignored. Letting a caller supply it would
  /// put a read-modify-write in every screen and let two parallel edits
  /// choose the same number, which `saveRevision` refuses rather than
  /// merges.
  ///
  /// `modifiedAt` on [edited] is ignored the same way: the stored revision
  /// is stamped with [_clock]'s instant, because `Recipe.modifiedAt`
  /// documents "when this revision was saved" and only this call knows that
  /// moment — a caller-supplied value would let a duplicated or re-submitted
  /// recipe claim it was last modified whenever its source was.
  ///
  /// This is the write for an id that may already hold a recipe, which is
  /// what makes it the wrong one for a recipe that must not: it answers an
  /// occupied id with that recipe's next revision. [CreateRecipe] is the
  /// write for a new one.
  ///
  /// Throws [RecipeCycleError] naming the path, or [MissingDependencyError],
  /// before anything is written.
  Future<Recipe> call(Recipe edited) async {
    await _assertResolvable(_recipes, edited);
    final latest = await _recipes.findLatest(edited.id);
    return await _store(
      _recipes,
      edited,
      revision: (latest?.revision ?? 0) + 1,
      modifiedAt: _clock.now(),
    );
  }
}

/// Writes a recipe as revision 1 of an id nothing is stored under yet.
final class CreateRecipe {
  /// Creates the use case over [_recipes], stamping the stored revision's
  /// `modifiedAt` from [_clock].
  const new(this._recipes, this._clock);

  final RecipeRepository _recipes;
  final Clock _clock;

  /// Stores [created] as revision 1 and returns it as stored, ignoring its
  /// `revision` and `modifiedAt` for the reasons [SaveRecipeRevision.call]
  /// gives.
  ///
  /// Throws [RecipeIdOccupiedError] when [created]'s id already names a
  /// stored recipe, and [RecipeCycleError] or [MissingDependencyError] as
  /// [SaveRecipeRevision.call] does, all before anything is written.
  ///
  /// The number is 1, never the stored count plus one, and that is the
  /// guarantee rather than the check in front of it. A caller mints the id
  /// from what it last read, and a write landing after that read can take
  /// the id first: counting from storage turned such a create into the
  /// occupant's next revision, replacing its name and content in the
  /// library under its own id. The check makes the common case a typed
  /// refusal before anything is written. A write landing between the check
  /// and the insert has already stored revision 1, and `saveRevision` never
  /// updates a stored revision, so the insert is refused and the occupant is
  /// kept either way.
  ///
  /// That refusal is the repository's own error, which this layer cannot
  /// name — SQLite's is a primary-key violation — so a failed insert is
  /// followed by one more read of the id. A recipe stored there now makes it
  /// the same [RecipeIdOccupiedError] the check gives, which a screen can
  /// answer by minting another id; an id still free leaves the failure as
  /// the repository raised it, because nothing about the id caused it.
  Future<Recipe> call(Recipe created) async {
    if (await _recipes.findLatest(created.id) != null) {
      throw RecipeIdOccupiedError(created.id);
    }
    await _assertResolvable(_recipes, created);
    try {
      return await _store(
        _recipes,
        created,
        revision: 1,
        modifiedAt: _clock.now(),
      );
    } on Object {
      if (await _recipes.findLatest(created.id) != null) {
        throw RecipeIdOccupiedError(created.id);
      }
      rethrow;
    }
  }
}

/// A recipe was to be created under an id that already names a stored one.
///
/// An [ArgumentError] rather than a `DomainError`: every domain error names
/// a missing or invalid reference, and nothing in the domain knows what is
/// stored. It is an argument error because the id is the caller's, which is
/// also what `DuplicateRecipe` has always documented this refusal as.
final class RecipeIdOccupiedError extends ArgumentError {
  /// Creates the error for the occupied [recipeId].
  new(this.recipeId)
    : super.value(
        recipeId,
        'id',
        'already names a stored recipe; create under an unused id',
      );

  /// The id a stored recipe already has.
  final String recipeId;
}

/// Throws [RecipeCycleError] or [MissingDependencyError] when [recipe]'s
/// dependencies, as stored now, cannot resolve.
Future<void> _assertResolvable(RecipeRepository recipes, Recipe recipe) async {
  final closure = await resolveDependencyClosure(recipes, recipe);
  RecipeDependencyGraph(closure).assertResolvable(recipe.id);
}

/// Writes [recipe] as [revision], stamped [modifiedAt], and returns it as
/// stored.
Future<Recipe> _store(
  RecipeRepository recipes,
  Recipe recipe, {
  required int revision,
  required DateTime modifiedAt,
}) async {
  final stored = _withRevision(
    recipe,
    revision: revision,
    modifiedAt: modifiedAt,
  );
  await recipes.saveRevision(stored);
  return stored;
}

/// [Recipe] has no `copyWith`, so every field is restated here.
Recipe _withRevision(
  Recipe recipe, {
  required int revision,
  required DateTime modifiedAt,
}) => Recipe(
  id: recipe.id,
  revision: revision,
  name: recipe.name,
  baseYield: recipe.baseYield,
  components: recipe.components,
  modifiedAt: modifiedAt,
  category: recipe.category,
  maxBatchYield: recipe.maxBatchYield,
  preparationNotes: recipe.preparationNotes,
  isArchived: recipe.isArchived,
);
