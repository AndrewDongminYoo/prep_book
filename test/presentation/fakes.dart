import 'dart:async';

import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../application/fakes.dart';

/// A repository whose reads the test completes by hand.
///
/// The library screen's hard cases are all about *when* a read finishes:
/// the spinner before the first one returns, a failure, a slow read
/// overtaken by a newer one, and a read that lands after the cubit closed.
/// `FakeRecipeRepository` in `test/application/fakes.dart` answers
/// immediately and cannot express any of them, so this fake exists
/// alongside it rather than replacing it — the ordinary cases keep using
/// the fake that `test/application/fakes_test.dart` pins against the real
/// repository's behaviour.
///
/// Every other member throws: the two use cases the screen holds call
/// [listLatestRevisions] and nothing else, and a fake that quietly answered
/// the rest would invite a test to depend on an answer nobody checked.
final class DeferredRecipeRepository implements RecipeRepository {
  /// One entry per [listLatestRevisions] call that has not been answered,
  /// in call order. The test completes them itself, in any order it likes.
  final List<Completer<List<Recipe>>> pending = [];

  /// How many reads this fake has been asked for.
  int get readCount => pending.length;

  /// Answers the read at [index] with [recipes].
  void complete(int index, List<Recipe> recipes) =>
      pending[index].complete(recipes);

  /// Fails the read at [index].
  void fail(int index, [Object error = 'the database is unreadable']) =>
      pending[index].completeError(error);

  @override
  Future<List<Recipe>> listLatestRevisions() {
    final completer = Completer<List<Recipe>>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<Recipe?> findRevision(String id, int revision) =>
      throw UnsupportedError('the library screen never reads one revision');

  @override
  Future<Recipe?> findLatest(String id) =>
      throw UnsupportedError('the library screen never reads one recipe');

  @override
  Future<void> saveRevision(Recipe recipe) =>
      throw UnsupportedError('the library screen never writes');

  @override
  Future<void> setArchived(String id, {required bool isArchived}) =>
      throw UnsupportedError('the library screen never archives');

  @override
  Future<List<Recipe>> listLatestRevisionsUsingIngredient(
    String ingredientId,
  ) => throw UnsupportedError('the library screen never reads by ingredient');
}

/// An ingredient repository whose reads the test completes by hand.
///
/// The sibling of [DeferredRecipeRepository], added for the recipe editor:
/// the editor reads the ingredient library when it opens, so the spinner,
/// the failed read, and the read that lands after the cubit closed are all
/// timing cases on *this* repository rather than on the recipe one.
///
/// Every other member throws, for the same reason the sibling's do: the
/// editor's use cases call [listAll] and [upsert] and nothing else.
final class DeferredIngredientRepository implements IngredientRepository {
  /// One entry per [listAll] call that has not been answered, in call order.
  final List<Completer<List<Ingredient>>> pending = [];

  /// Every ingredient [upsert] was given, in call order.
  final List<Ingredient> written = [];

  /// One entry per deferred [upsert] call that has not been answered.
  final List<Completer<void>> pendingWrites = [];

  /// Whether a write should throw instead of storing.
  bool failWrites = false;

  /// Whether a write should stay open until the test answers it.
  ///
  /// Off by default, so the tests that only care about the result stay one
  /// line each. The editor's *timing* case needs the other setting: the form
  /// has to refuse input for as long as the write runs, and a write that has
  /// already finished by the time `createIngredient` returns leaves no
  /// window to look at.
  bool deferWrites = false;

  /// Answers the read at [index] with [ingredients].
  void complete(int index, List<Ingredient> ingredients) =>
      pending[index].complete(ingredients);

  /// Fails the read at [index].
  void fail(int index, [Object error = 'the database is unreadable']) =>
      pending[index].completeError(error);

  /// Answers the deferred write at [index].
  void completeWrite(int index) => pendingWrites[index].complete();

  @override
  Future<List<Ingredient>> listAll() {
    final completer = Completer<List<Ingredient>>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<void> upsert(Ingredient ingredient) async {
    if (failWrites) throw StateError('the database is unwritable');
    written.add(ingredient);
    if (!deferWrites) return;
    final completer = Completer<void>();
    pendingWrites.add(completer);
    await completer.future;
  }

  @override
  Future<Ingredient?> findById(String id) =>
      throw UnsupportedError('the editor never reads one ingredient');

  @override
  Future<void> delete(String id) =>
      throw UnsupportedError('the editor never deletes an ingredient');
}

/// A recipe repository that reads through [FakeRecipeRepository] and holds
/// its writes open until the test answers them.
///
/// The editor's timing cases are on the write, not the read: the operator
/// must not be able to press Save twice while the first one is in flight,
/// and a failed write has to leave the form up with a message. Neither is
/// expressible against a fake that answers immediately, and
/// [DeferredRecipeRepository] refuses to write at all because the library
/// screen it was built for never does.
final class DeferredWriteRecipeRepository implements RecipeRepository {
  /// Creates a repository reading through [reads].
  DeferredWriteRecipeRepository(this.reads);

  /// The in-memory library every read is answered from.
  final FakeRecipeRepository reads;

  /// One entry per [saveRevision] call that has not been answered.
  final List<Completer<void>> pendingWrites = [];

  /// Every revision [saveRevision] was given, in call order.
  final List<Recipe> written = [];

  /// Answers the write at [index].
  void completeWrite(int index) => pendingWrites[index].complete();

  /// Fails the write at [index].
  void failWrite(int index, [Object error = 'the database is unwritable']) =>
      pendingWrites[index].completeError(error);

  @override
  Future<void> saveRevision(Recipe recipe) {
    written.add(recipe);
    final completer = Completer<void>();
    pendingWrites.add(completer);
    return completer.future;
  }

  @override
  Future<List<Recipe>> listLatestRevisions() => reads.listLatestRevisions();

  @override
  Future<Recipe?> findRevision(String id, int revision) =>
      reads.findRevision(id, revision);

  @override
  Future<Recipe?> findLatest(String id) => reads.findLatest(id);

  @override
  Future<void> setArchived(String id, {required bool isArchived}) =>
      throw UnsupportedError('the editor never archives');

  @override
  Future<List<Recipe>> listLatestRevisionsUsingIngredient(
    String ingredientId,
  ) => throw UnsupportedError('the editor never reads by ingredient');
}

/// A clock that never moves, so a stored revision carries a timestamp the
/// test chose rather than the moment it happened to run.
final class FixedClock implements Clock {
  /// Creates the clock.
  const FixedClock();

  @override
  DateTime now() => DateTime.utc(2026, 9, 8, 12);
}

/// A run identifier source that answers with the same value every time.
///
/// Fixed rather than counted because nothing stores what the production
/// setup screen calculates, so no test needs two runs to differ — and the
/// entrypoints bind a constant source too, for the reason
/// `PreviewRunIdSource` states.
final class FixedRunIdSource implements RunIdSource {
  /// Creates the source.
  const FixedRunIdSource();

  @override
  String next() => 'run-1';
}

/// A recipe repository that reads through [FakeRecipeRepository] and holds
/// every single-recipe lookup open until the test answers it.
///
/// The production setup screen's timing cases are all on that lookup: the
/// spinner while a calculation runs, a slower calculation overtaken by a
/// newer target, a target cleared while one is in flight, and one that
/// lands after the cubit closed. [DeferredRecipeRepository] expresses none
/// of them — it defers the whole list and refuses to look one recipe up —
/// and [FakeRecipeRepository] answers before there is a window to look at.
///
/// Every lookup is deferred, sub-recipes included: a run over a recipe that
/// references another asks for each of them in turn, so a fake holding only
/// the first would let the rest resolve while the test thought nothing had.
final class DeferredLookupRecipeRepository implements RecipeRepository {
  /// Creates a repository answering out of [reads].
  DeferredLookupRecipeRepository(this.reads);

  /// The in-memory library [complete] answers from.
  final FakeRecipeRepository reads;

  /// One entry per [findLatest] call that has not been answered, in call
  /// order.
  final List<Completer<Recipe?>> pending = [];

  /// The identifiers [findLatest] was called with, in call order.
  final List<String> lookups = [];

  /// Answers the lookup at [index] out of [reads].
  Future<void> complete(int index) async =>
      pending[index].complete(await reads.findLatest(lookups[index]));

  /// Fails the lookup at [index].
  void fail(int index, [Object error = 'the database is unreadable']) =>
      pending[index].completeError(error);

  @override
  Future<Recipe?> findLatest(String id) {
    lookups.add(id);
    final completer = Completer<Recipe?>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<List<Recipe>> listLatestRevisions() => reads.listLatestRevisions();

  @override
  Future<Recipe?> findRevision(String id, int revision) =>
      throw UnsupportedError('production setup never reads one revision');

  @override
  Future<void> saveRevision(Recipe recipe) =>
      throw UnsupportedError('production setup never writes');

  @override
  Future<void> setArchived(String id, {required bool isArchived}) =>
      throw UnsupportedError('production setup never archives');

  @override
  Future<List<Recipe>> listLatestRevisionsUsingIngredient(
    String ingredientId,
  ) => throw UnsupportedError('production setup never reads by ingredient');
}

/// A launcher over in-memory storage, wired exactly as the entrypoints wire
/// the real one, so a screen test opens the editor the app actually opens.
RecipeEditorLauncher buildEditorLauncher(
  RecipeRepository recipes,
  IngredientRepository ingredients,
) => RecipeEditorLauncher(
  listLibrary: ListLibrary(recipes),
  listIngredients: ListIngredients(ingredients),
  saveRecipeRevision: SaveRecipeRevision(recipes, const FixedClock()),
  saveIngredient: SaveIngredient(ingredients),
);

/// A production setup launcher over in-memory storage, wired the way the
/// entrypoints wire the real one, so a screen test opens the screen the app
/// actually opens.
ProductionSetupLauncher buildProductionLauncher(RecipeRepository recipes) =>
    ProductionSetupLauncher(
      StartProductionRun(recipes, const FixedRunIdSource(), const FixedClock()),
    );

/// A sub-recipe produced one gram at a time.
///
/// Referenced from a parent that states no maximum of its own — a
/// `buildSubRecipeComponent` line consumes a tenth of the parent's yield —
/// it is how a target the parent absorbs in a single batch still expands
/// into a batch per gram underneath. Both the cubit suite and the widget
/// suite scale it against `ProductionSetupState.maxPlannedBatches`, so the
/// one-gram maximum and the parent's tenth are two halves of one number and
/// live here rather than once per suite.
Recipe buildGrainSubRecipe() => Recipe(
  id: 'grain',
  revision: 1,
  name: 'Grain',
  baseYield: Quantity.parse('1000', Unit.gram),
  maxBatchYield: Quantity.parse('1', Unit.gram),
  modifiedAt: DateTime.utc(2026, 9, 8),
  components: [
    RecipeComponent(
      id: 'grain-flour',
      target: const IngredientRef('flour'),
      baseQuantity: Quantity.parse('500', Unit.gram),
      behavior: ScalingBehavior.proportional,
      displayOrder: 0,
    ),
  ],
);
