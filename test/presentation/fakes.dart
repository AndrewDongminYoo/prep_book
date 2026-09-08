import 'dart:async';

import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

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
