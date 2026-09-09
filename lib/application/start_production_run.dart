import 'package:prep_book/application/dependency_closure.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Supplies the identifier a new production run is stored under.
///
/// Injected rather than generated inline so a test can assert an exact
/// snapshot; the app binds it to a UUID source.
abstract interface class RunIdSource {
  /// A new, unused run identifier.
  String next();
}

/// Supplies the current instant, for the same reason as [RunIdSource].
abstract interface class Clock {
  /// The current instant.
  DateTime now();
}

/// Calculates a production run without storing it.
///
/// The design document requires the snapshot to be computed before
/// persistence; returning an unsaved value is how that is satisfied. The
/// caller reviews it, records acknowledgements and overrides, and then
/// passes it to `SaveProductionRun`.
final class StartProductionRun {
  /// Creates the use case.
  const StartProductionRun(this._recipes, this._ids, this._clock);

  final RecipeRepository _recipes;
  final RunIdSource _ids;
  final Clock _clock;

  /// Scales [recipeId] to [targetYield].
  ///
  /// Throws [MissingDependencyError] when the recipe or one of its
  /// sub-recipes is not stored, [RecipeCycleError] when the stored graph has
  /// a cycle, and the domain's own yield errors for a target the recipe
  /// cannot take. None is rewrapped: each already names what the operator
  /// has to be told.
  ///
  /// [maxPlannedBatches] bounds how many batches any one recipe in the run
  /// — the root, and every sub-recipe expanded under it — may be split
  /// into, and a target that crosses it raises [BatchLimitExceededError].
  /// A call argument rather than a constructor one, and unbounded by
  /// default, because the bound belongs to the caller's situation rather
  /// than to the run: a screen that blocks on the calculation has to cap
  /// it, and a caller that can wait has no reason to.
  Future<ProductionRun> call({
    required String recipeId,
    required Quantity targetYield,
    int? maxPlannedBatches,
  }) async {
    final root = await _recipes.findLatest(recipeId);
    // Both arguments match on purpose: `MissingDependencyError` renders
    // "recipe X is not in the index" in that case, which is the wording the
    // domain chose for an absent root rather than a dangling reference. Its
    // own "reports a missing root as absent, not self-referencing" test
    // pins that message.
    if (root == null) throw MissingDependencyError(recipeId, recipeId);

    final closure = await resolveDependencyClosure(_recipes, root);
    final result = ProductionCalculator(
      maxPlannedBatches: maxPlannedBatches,
    ).calculate(recipe: root, targetYield: targetYield, recipeIndex: closure);

    // `dependencySnapshot` documents every recipe the calculation depended
    // on, and `ProductionRun.recipe` already holds the root — so the root
    // is dropped here rather than persisted twice for no reader. `closure`
    // itself keeps the root, because `recipeIndex` above needs it to
    // validate the graph and resolve self-references during expansion.
    final dependencies = {...closure}..remove(root.id);

    return ProductionRun(
      id: _ids.next(),
      createdAt: _clock.now(),
      recipe: root,
      dependencySnapshot: dependencies,
      targetYield: targetYield,
      result: result,
    );
  }
}
