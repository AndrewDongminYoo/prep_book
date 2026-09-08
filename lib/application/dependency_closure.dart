import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Every recipe reachable from [root] through `subRecipeIds`, keyed by id,
/// with [root] itself included under its own id.
///
/// [root] is the caller's own object, not a re-read of storage, so an edit
/// that has not been saved yet is what the walk follows. That is what lets
/// a cycle introduced *by* the edit be found: the stored revision of the
/// same id does not carry the new reference.
///
/// Dependencies are read at their latest revision, matching what
/// [RecipeRepository.listLatestRevisionsUsingIngredient] already assumes is
/// current. An id no revision is stored for is left out rather than
/// reported: the caller passes this map to `RecipeDependencyGraph` or to
/// `ProductionCalculator`, and both already raise `MissingDependencyError`
/// naming the reference and its parent. Reporting it here would duplicate
/// an error the domain owns, in a worse form, because this walk does not
/// track which parent asked.
///
/// A recipe already in the map is not visited again, so a diamond loads
/// once and a cycle terminates. The cycle is not diagnosed here either;
/// `RecipeDependencyGraph.assertResolvable` names its path.
Future<Map<String, Recipe>> resolveDependencyClosure(
  RecipeRepository recipes,
  Recipe root,
) async {
  final closure = <String, Recipe>{root.id: root};
  final pending = <String>[...root.subRecipeIds];

  while (pending.isNotEmpty) {
    final id = pending.removeLast();
    if (closure.containsKey(id)) continue;
    final recipe = await recipes.findLatest(id);
    if (recipe == null) continue;
    closure[id] = recipe;
    pending.addAll(recipe.subRecipeIds);
  }

  return closure;
}
