import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Every stored ingredient, ordered by name.
///
/// A thin delegation, and deliberately so: the recipe editor needs the
/// ingredient library to name a component's target, and this is what lets
/// it read one without holding a repository. The ordering is the
/// repository's contract, not this class's — sorting again here would
/// duplicate a guarantee that already holds.
final class ListIngredients {
  /// Creates the use case over [_ingredients].
  const ListIngredients(this._ingredients);

  final IngredientRepository _ingredients;

  /// Reads the ingredient library.
  Future<List<Ingredient>> call() => _ingredients.listAll();
}

/// Stores an ingredient, replacing the row already under its id.
///
/// Insert and update are one call because the repository's `upsert` is one
/// call: the editor creates ingredients and never edits them, so nothing
/// here needs to tell the two apart.
final class SaveIngredient {
  /// Creates the use case over [_ingredients].
  const SaveIngredient(this._ingredients);

  final IngredientRepository _ingredients;

  /// Writes [ingredient].
  Future<void> call(Ingredient ingredient) => _ingredients.upsert(ingredient);
}
