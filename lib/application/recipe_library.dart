import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// The latest revision of every recipe, archived ones included.
final class ListLibrary {
  /// Creates the use case over [_recipes].
  const ListLibrary(this._recipes);

  final RecipeRepository _recipes;

  /// Reads the library.
  Future<List<Recipe>> call() => _recipes.listLatestRevisions();
}

/// The library, filtered by name.
///
/// An in-memory filter rather than a query, because the library is one
/// restaurant's recipes and the persistence layer's query surface stays
/// smaller for it. Moving this into SQL later does not change the
/// signature.
final class SearchLibrary {
  /// Creates the use case over [_recipes].
  const SearchLibrary(this._recipes);

  final RecipeRepository _recipes;

  /// Every latest revision whose name contains [query], ignoring case. An
  /// empty [query] matches everything, which is what a cleared search box
  /// should show.
  Future<List<Recipe>> call(String query) async {
    final needle = query.toLowerCase();
    final all = await _recipes.listLatestRevisions();
    return [
      for (final recipe in all)
        if (recipe.name.toLowerCase().contains(needle)) recipe,
    ];
  }
}
