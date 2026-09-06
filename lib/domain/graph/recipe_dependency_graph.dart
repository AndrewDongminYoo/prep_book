import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/recipe/recipe.dart';

/// Validates that a recipe's sub-recipe references form a resolvable tree.
final class RecipeDependencyGraph {
  /// Creates a graph over [recipesById].
  RecipeDependencyGraph(Map<String, Recipe> recipesById)
    : _recipes = Map.unmodifiable(recipesById);

  final Map<String, Recipe> _recipes;

  /// The dependency path proving a cycle reachable from [recipeId], or null.
  ///
  /// The returned path ends at the identifier that repeats, so the caller can
  /// show the operator exactly which reference to remove.
  List<String>? findCycleFrom(String recipeId) {
    final path = <String>[];
    final onPath = <String>{};
    final settled = <String>{};

    List<String>? visit(String id) {
      if (onPath.contains(id)) return [...path, id];
      if (settled.contains(id)) return null;

      final recipe = _recipes[id];
      if (recipe == null) return null;

      path.add(id);
      onPath.add(id);
      for (final childId in recipe.subRecipeIds) {
        final cycle = visit(childId);
        if (cycle != null) return cycle;
      }
      onPath.remove(id);
      path.removeLast();
      settled.add(id);
      return null;
    }

    return visit(recipeId);
  }

  /// Throws when [recipeId] cannot be resolved into a finite tree.
  ///
  /// Cycles are reported before missing dependencies, because a cycle makes
  /// the traversal that finds missing references non-terminating.
  void assertResolvable(String recipeId) {
    final cycle = findCycleFrom(recipeId);
    if (cycle != null) throw RecipeCycleError(cycle);

    final seen = <String>{};
    void visit(String id, String parentId) {
      final recipe = _recipes[id];
      if (recipe == null) throw MissingDependencyError(parentId, id);
      if (!seen.add(id)) return;
      for (final childId in recipe.subRecipeIds) {
        visit(childId, id);
      }
    }

    visit(recipeId, recipeId);
  }
}
