import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

import 'fakes.dart';

final class _Ids implements RunIdSource {
  _Ids(this._values);
  final List<String> _values;
  var _index = 0;

  @override
  String next() => _values[_index++];
}

final class _Clock implements Clock {
  _Clock(this._values);
  final List<DateTime> _values;
  var _index = 0;

  @override
  DateTime now() => _values[_index++];
}

/// A [ProductionRunRepository] whose [listSummaries] returns a fixed order
/// that matches none of the sorts an over-helpful `ListProductionHistory`
/// might apply on its own (id ascending, id descending, `createdAt`
/// ascending, `createdAt` descending). Only a use case that returns exactly
/// what this repository handed it, unsorted, produces the sequence the test
/// asserts.
final class _FixedOrderRunRepository implements ProductionRunRepository {
  _FixedOrderRunRepository(this._summaries);
  final List<ProductionRunSummary> _summaries;

  @override
  Future<List<ProductionRunSummary>> listSummaries() async => _summaries;

  @override
  Future<ProductionRun?> findById(String id) => throw UnimplementedError();

  @override
  Future<void> save(ProductionRun run) => throw UnimplementedError();

  @override
  Future<void> recordAcknowledgement(String runId, ProductionWarning warning) =>
      throw UnimplementedError();

  @override
  Future<void> recordOverride(String runId, OverrideKey key, Quantity value) =>
      throw UnimplementedError();
}

ProductionRunSummary _summary(String id, DateTime createdAt) =>
    ProductionRunSummary(
      id: id,
      recipeId: 'a',
      recipeRevision: 1,
      targetYield: Quantity.parse('1000', Unit.gram),
      createdAt: createdAt,
    );

void main() {
  test('history comes back newest first', () async {
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));
    final runs = FakeProductionRunRepository();
    final start = StartProductionRun(
      recipes,
      _Ids(['older', 'newer']),
      _Clock([DateTime.utc(2026, 9, 8, 10), DateTime.utc(2026, 9, 8, 11)]),
    );
    final target = Quantity.parse('1000', Unit.gram);
    await SaveProductionRun(
      runs,
    ).call(await start.call(recipeId: 'a', targetYield: target));
    await SaveProductionRun(
      runs,
    ).call(await start.call(recipeId: 'a', targetYield: target));

    final summaries = await ListProductionHistory(runs).call();

    expect(summaries.map((s) => s.id), ['newer', 'older']);
  });

  test(
    'history is exactly the repository order, not a use-case re-sort',
    () async {
      // None of id-ascending (a, b, c), id-descending (c, b, a),
      // createdAt-ascending (a, c, b), or createdAt-descending (b, c, a)
      // matches this sequence, so a `ListProductionHistory` that trusted its
      // own sort instead of the repository's would fail here even though it
      // passes the "newest first" test above with flying colors.
      final runs = _FixedOrderRunRepository([
        _summary('c', DateTime.utc(2026, 3)),
        _summary('a', DateTime.utc(2026)),
        _summary('b', DateTime.utc(2026, 6)),
      ]);

      final summaries = await ListProductionHistory(runs).call();

      expect(summaries.map((s) => s.id), ['c', 'a', 'b']);
    },
  );

  test('opening a stored run returns what was stored', () async {
    final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));
    final runs = FakeProductionRunRepository();
    final run = await StartProductionRun(
      recipes,
      _Ids(['run-1']),
      _Clock([DateTime.utc(2026, 9, 8, 10)]),
    ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));
    await SaveProductionRun(runs).call(run);

    final opened = await OpenProductionRun(runs).call('run-1');

    // `id` alone would also pass for an implementation that fabricated a new
    // `ProductionRun` carrying the requested id instead of reading storage.
    // `same` proves the exact stored object came back, the way
    // `production_run_edits_test.dart` already does for `save`/`findById`.
    expect(opened, same(run));
    expect(opened!.id, 'run-1');
  });

  test(
    'opening one of several stored runs returns that run, not another',
    () async {
      final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'a'));
      final runs = FakeProductionRunRepository();
      final start = StartProductionRun(
        recipes,
        _Ids(['first', 'second']),
        _Clock([DateTime.utc(2026, 9, 8, 10), DateTime.utc(2026, 9, 8, 11)]),
      );
      final target = Quantity.parse('1000', Unit.gram);
      final first = await start.call(recipeId: 'a', targetYield: target);
      final second = await start.call(recipeId: 'a', targetYield: target);
      await SaveProductionRun(runs).call(first);
      await SaveProductionRun(runs).call(second);

      // With only one run stored, an implementation that ignores its
      // argument and always asks the repository for a hardcoded id would
      // still pass. Two distinct stored runs close that gap.
      expect(await OpenProductionRun(runs).call('first'), same(first));
      expect(await OpenProductionRun(runs).call('second'), same(second));
    },
  );

  test('opening a run that is gone returns null', () async {
    expect(
      await OpenProductionRun(FakeProductionRunRepository()).call('nope'),
      isNull,
    );
  });

  // This is an integration check across StartProductionRun, SaveProductionRun,
  // SaveRecipeRevision, and OpenProductionRun together, not new coverage of
  // logic this task added — the same invariant is pinned where it is
  // actually at risk, at the domain layer
  // (test/domain/production_run_test.dart) and the persistence layer
  // (test/persistence/production_run_repository_test.dart).
  test('a stored run keeps the revision it was computed from', () async {
    final recipes = FakeRecipeRepository()
      ..seed(buildRecipe(id: 'a', name: 'Original'));
    final runs = FakeProductionRunRepository();
    final run = await StartProductionRun(
      recipes,
      _Ids(['run-1']),
      _Clock([DateTime.utc(2026, 9, 8, 10)]),
    ).call(recipeId: 'a', targetYield: Quantity.parse('1000', Unit.gram));
    await SaveProductionRun(runs).call(run);

    await SaveRecipeRevision(
      recipes,
      _Clock([DateTime.utc(2026, 9, 8, 11)]),
    ).call(buildRecipe(id: 'a', name: 'Edited'));

    final reopened = await OpenProductionRun(runs).call('run-1');

    expect(reopened!.recipe.revision, 1);
    expect(reopened.recipe.name, 'Original');
    expect((await recipes.findLatest('a'))!.name, 'Edited');
  });
}
