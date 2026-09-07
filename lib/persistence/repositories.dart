import 'package:prep_book/domain/domain.dart';

/// Storage for the ingredient library.
abstract interface class IngredientRepository {
  /// Every stored ingredient, ordered by name.
  Future<List<Ingredient>> listAll();

  /// The ingredient stored under [id], or `null` when none exists.
  Future<Ingredient?> findById(String id);

  /// Inserts [ingredient], or replaces the row already stored under its id.
  Future<void> upsert(Ingredient ingredient);

  /// Removes the ingredient stored under [id], if any.
  Future<void> delete(String id);
}

/// Storage for recipes and their revisions.
abstract interface class RecipeRepository {
  /// The highest revision of every recipe, archived ones included.
  Future<List<Recipe>> listLatestRevisions();

  /// The revision [revision] of the recipe [id], or `null` when no such
  /// revision is stored.
  Future<Recipe?> findRevision(String id, int revision);

  /// The highest stored revision of the recipe [id], or `null` when the
  /// recipe does not exist.
  Future<Recipe?> findLatest(String id);

  /// Inserts [recipe] as a new revision. Never updates an existing one, so a
  /// stored production run keeps the revision it was computed against.
  Future<void> saveRevision(Recipe recipe);

  /// Sets the archived flag on every revision of the recipe [id].
  Future<void> setArchived(String id, {required bool isArchived});

  /// The highest revision of every recipe that references the ingredient
  /// [ingredientId], archived ones included.
  ///
  /// Answers "is this ingredient in use?" and nothing else. It is a read
  /// rather than a result of [IngredientRepository.delete] because the
  /// answer is needed *before* the row is gone: the application layer warns
  /// with the recipes named here and then deletes if the operator confirms.
  /// Nothing in this unit refuses the deletion.
  ///
  /// Only the latest revision of each recipe is examined. A recipe whose
  /// earlier revision used the ingredient and whose current one does not is
  /// not a use, and one recipe with three revisions is one answer, not
  /// three.
  ///
  /// An archived recipe counts, for the same reason
  /// [listLatestRevisions] returns one: it can be restored, and an
  /// ingredient deleted out from under it would leave a reference that only
  /// surfaces once the operator has forgotten about it. Each returned
  /// [Recipe] carries its own `isArchived`, so a caller that wants to say so
  /// can.
  Future<List<Recipe>> listLatestRevisionsUsingIngredient(String ingredientId);
}

/// Enough of a run to list it without deserializing its result.
final class ProductionRunSummary {
  /// Creates a summary.
  const ProductionRunSummary({
    required this.id,
    required this.recipeId,
    required this.recipeRevision,
    required this.targetYield,
    required this.createdAt,
  });

  /// Stable identifier of the run.
  final String id;

  /// The recipe the run was computed from.
  final String recipeId;

  /// The revision of that recipe.
  final int recipeRevision;

  /// The yield the operator asked for.
  final Quantity targetYield;

  /// When the run was calculated.
  final DateTime createdAt;
}

/// Storage for production runs and the acknowledgement and override state
/// each one carries.
abstract interface class ProductionRunRepository {
  /// Every stored run, newest first.
  Future<List<ProductionRunSummary>> listSummaries();

  /// The run stored under [id], or `null` when none exists.
  Future<ProductionRun?> findById(String id);

  /// Writes the run and the acknowledgement and override state it carries in
  /// one transaction.
  Future<void> save(ProductionRun run);

  /// Records that [warning] has been acknowledged on the run [runId].
  Future<void> recordAcknowledgement(String runId, ProductionWarning warning);

  /// Records an operator-entered replacement [value] for [key] on the run
  /// [runId].
  Future<void> recordOverride(String runId, OverrideKey key, Quantity value);
}
