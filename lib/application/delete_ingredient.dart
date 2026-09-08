import 'package:meta/meta.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// What [DeleteIngredient] did, and what stood in the way.
@immutable
final class IngredientDeletion {
  /// Creates an outcome.
  const IngredientDeletion({required this.deleted, required this.blockedBy});

  /// Whether the ingredient was removed.
  final bool deleted;

  /// The recipes whose latest revision names the ingredient directly.
  ///
  /// Populated whether or not the deletion went ahead, so a forced call can
  /// still tell the operator which recipes now carry a dangling reference.
  final List<Recipe> blockedBy;
}

/// Removes an ingredient, refusing while recipes still name it.
///
/// The repository deliberately refuses nothing — its own documentation says
/// so — which is why the rule lives here.
final class DeleteIngredient {
  /// Creates the use case over [_ingredients] and [_recipes].
  const DeleteIngredient(this._ingredients, this._recipes);

  final IngredientRepository _ingredients;
  final RecipeRepository _recipes;

  /// Deletes [ingredientId] when nothing uses it.
  ///
  /// When recipes do, nothing is removed and they are returned instead. A
  /// caller that wants to delete anyway calls again with [force], so the
  /// operator's confirmation is a second decision rather than a flag the
  /// first call already carried and the screen forgot to unset.
  Future<IngredientDeletion> call(
    String ingredientId, {
    bool force = false,
  }) async {
    final users = await _recipes.listLatestRevisionsUsingIngredient(
      ingredientId,
    );
    if (users.isNotEmpty && !force) {
      return IngredientDeletion(deleted: false, blockedBy: users);
    }
    await _ingredients.delete(ingredientId);
    return IngredientDeletion(deleted: true, blockedBy: users);
  }
}
