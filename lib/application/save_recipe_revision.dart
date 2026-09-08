import 'package:prep_book/application/dependency_closure.dart';
import 'package:prep_book/application/start_production_run.dart' show Clock;
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Writes an edited recipe as the next revision of its id.
final class SaveRecipeRevision {
  /// Creates the use case over [_recipes], stamping the saved revision's
  /// `modifiedAt` from [_clock].
  const SaveRecipeRevision(this._recipes, this._clock);

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
  /// Throws [RecipeCycleError] naming the path, or [MissingDependencyError],
  /// before anything is written.
  Future<Recipe> call(Recipe edited) async {
    final closure = await resolveDependencyClosure(_recipes, edited);
    RecipeDependencyGraph(closure).assertResolvable(edited.id);

    final latest = await _recipes.findLatest(edited.id);
    final next = _withRevision(
      edited,
      revision: (latest?.revision ?? 0) + 1,
      modifiedAt: _clock.now(),
    );
    await _recipes.saveRevision(next);
    return next;
  }

  /// [Recipe] has no `copyWith`, so every field is restated here.
  static Recipe _withRevision(
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
}
