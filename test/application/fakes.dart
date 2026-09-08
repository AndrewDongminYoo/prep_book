import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// A one-component recipe, enough for most use-case tests.
Recipe buildRecipe({
  required String id,
  int revision = 1,
  String name = 'Test recipe',
  List<RecipeComponent>? components,
  bool isArchived = false,
}) => Recipe(
  id: id,
  revision: revision,
  name: name,
  baseYield: Quantity.parse('1000', Unit.gram),
  modifiedAt: DateTime.utc(2026, 9, 8),
  isArchived: isArchived,
  components:
      components ??
      [
        RecipeComponent(
          id: 'flour',
          target: const IngredientRef('flour'),
          baseQuantity: Quantity.parse('500', Unit.gram),
          behavior: ScalingBehavior.proportional,
          displayOrder: 0,
        ),
      ],
);

/// A recipe with one manual line, so its calculated result carries a
/// blocking `ManualComponentWarning` for Task 8 to acknowledge.
Recipe buildRecipeWithManualComponent({required String id}) => buildRecipe(
  id: id,
  components: [
    RecipeComponent(
      id: 'flour',
      target: const IngredientRef('flour'),
      baseQuantity: Quantity.parse('500', Unit.gram),
      behavior: ScalingBehavior.proportional,
      displayOrder: 0,
    ),
    RecipeComponent(
      id: 'salt',
      target: const IngredientRef('salt'),
      baseQuantity: null,
      behavior: ScalingBehavior.manual,
      displayOrder: 1,
    ),
  ],
);

/// A component referencing the sub-recipe [recipeId].
RecipeComponent buildSubRecipeComponent(String recipeId) => RecipeComponent(
  id: 'sub-$recipeId',
  target: SubRecipeRef(recipeId),
  baseQuantity: Quantity.parse('100', Unit.gram),
  behavior: ScalingBehavior.proportional,
  displayOrder: 1,
);

Ingredient buildIngredient({required String id, String name = 'Flour'}) =>
    Ingredient(id: id, name: name, defaultUnit: Unit.gram);

/// In-memory [RecipeRepository]. Stores every revision, keyed by id.
final class FakeRecipeRepository implements RecipeRepository {
  final Map<String, List<Recipe>> revisions = {};

  /// Every call this fake received, in order, for asserting that a rejected
  /// operation wrote nothing.
  final List<String> calls = [];

  void seed(Recipe recipe) =>
      revisions.putIfAbsent(recipe.id, () => []).add(recipe);

  @override
  Future<List<Recipe>> listLatestRevisions() async =>
      [for (final list in revisions.values) _highest(list)]
        ..sort((a, b) => a.id.compareTo(b.id));

  @override
  Future<Recipe?> findRevision(String id, int revision) async {
    for (final recipe in revisions[id] ?? const <Recipe>[]) {
      if (recipe.revision == revision) return recipe;
    }
    return null;
  }

  @override
  Future<Recipe?> findLatest(String id) async {
    final list = revisions[id];
    if (list == null || list.isEmpty) return null;
    return _highest(list);
  }

  @override
  Future<void> saveRevision(Recipe recipe) async {
    calls.add('saveRevision:${recipe.id}:${recipe.revision}');
    final list = revisions.putIfAbsent(recipe.id, () => []);
    if (list.any((stored) => stored.revision == recipe.revision)) {
      throw StateError('revision ${recipe.revision} of ${recipe.id} exists');
    }
    list.add(recipe);
  }

  @override
  Future<void> setArchived(String id, {required bool isArchived}) async {
    calls.add('setArchived:$id:$isArchived');
    final list = revisions[id];
    if (list == null) return;
    for (var i = 0; i < list.length; i++) {
      list[i] = _withArchived(list[i], isArchived: isArchived);
    }
  }

  @override
  Future<List<Recipe>> listLatestRevisionsUsingIngredient(
    String ingredientId,
  ) async => [
    for (final list in revisions.values)
      if (_usesIngredient(_highest(list), ingredientId)) _highest(list),
  ]..sort((a, b) => a.id.compareTo(b.id));

  static bool _usesIngredient(Recipe recipe, String ingredientId) =>
      recipe.components.any(
        (component) => switch (component.target) {
          IngredientRef(ingredientId: final referenced) =>
            referenced == ingredientId,
          SubRecipeRef() => false,
        },
      );

  static Recipe _highest(List<Recipe> list) =>
      list.reduce((a, b) => a.revision >= b.revision ? a : b);

  static Recipe _withArchived(Recipe recipe, {required bool isArchived}) =>
      Recipe(
        id: recipe.id,
        revision: recipe.revision,
        name: recipe.name,
        baseYield: recipe.baseYield,
        components: recipe.components,
        modifiedAt: recipe.modifiedAt,
        category: recipe.category,
        maxBatchYield: recipe.maxBatchYield,
        preparationNotes: recipe.preparationNotes,
        isArchived: isArchived,
      );
}

/// In-memory [IngredientRepository].
final class FakeIngredientRepository implements IngredientRepository {
  final Map<String, Ingredient> stored = {};

  @override
  Future<List<Ingredient>> listAll() async =>
      stored.values.toList()..sort((a, b) => a.name.compareTo(b.name));

  @override
  Future<Ingredient?> findById(String id) async => stored[id];

  @override
  Future<void> upsert(Ingredient ingredient) async =>
      stored[ingredient.id] = ingredient;

  @override
  Future<void> delete(String id) async => stored.remove(id);
}

/// In-memory [ProductionRunRepository].
final class FakeProductionRunRepository implements ProductionRunRepository {
  final Map<String, ProductionRun> stored = {};

  @override
  Future<List<ProductionRunSummary>> listSummaries() async {
    final runs = stored.values.toList()
      ..sort((a, b) {
        final byCreatedAt = b.createdAt.compareTo(a.createdAt);
        return byCreatedAt != 0 ? byCreatedAt : a.id.compareTo(b.id);
      });
    return [
      for (final run in runs)
        ProductionRunSummary(
          id: run.id,
          recipeId: run.recipeId,
          recipeRevision: run.recipeRevision,
          targetYield: run.targetYield,
          createdAt: run.createdAt,
        ),
    ];
  }

  @override
  Future<ProductionRun?> findById(String id) async => stored[id];

  @override
  Future<void> save(ProductionRun run) async => stored[run.id] = run;

  @override
  Future<void> recordAcknowledgement(
    String runId,
    ProductionWarning warning,
  ) async {
    final run = stored[runId];
    if (run != null) stored[runId] = run.acknowledge(warning);
  }

  @override
  Future<void> recordOverride(
    String runId,
    OverrideKey key,
    Quantity value,
  ) async {
    final run = stored[runId];
    if (run == null) return;
    stored[runId] = run.override(
      recipeId: key.$1,
      componentId: key.$2,
      value: value,
    );
  }
}
