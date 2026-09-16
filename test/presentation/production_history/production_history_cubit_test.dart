import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/production_history/production_history.dart';

final class _HistoryRepository implements ProductionRunRepository {
  final List<Completer<List<ProductionRunSummary>>> pending = [];

  @override
  Future<List<ProductionRunSummary>> listSummaries() {
    final completer = Completer<List<ProductionRunSummary>>();
    pending.add(completer);
    return completer.future;
  }

  @override
  Future<ProductionRun?> findById(String id) => throw UnimplementedError();

  @override
  Future<void> recordAcknowledgement(String runId, ProductionWarning warning) =>
      throw UnimplementedError();

  @override
  Future<void> recordOverride(String runId, OverrideKey key, Quantity value) =>
      throw UnimplementedError();

  @override
  Future<void> save(ProductionRun run) => throw UnimplementedError();
}

ProductionRunSummary _summary(String id) => ProductionRunSummary(
  id: id,
  recipeId: 'recipe-$id',
  recipeName: 'Recipe $id',
  recipeRevision: 1,
  targetYield: Quantity.parse('12', Unit.count('roll')),
  createdAt: DateTime.utc(2026, 9, 15, 23),
  isDraft: false,
);

void main() {
  test('load keeps the repository order and marks the read loaded', () async {
    final repository = _HistoryRepository();
    final cubit = ProductionHistoryCubit(ListProductionHistory(repository));
    addTearDown(cubit.close);

    final load = cubit.load();
    expect(cubit.state.status, ProductionHistoryStatus.loading);
    repository.pending.single.complete([_summary('second'), _summary('first')]);
    await load;

    expect(cubit.state.status, ProductionHistoryStatus.loaded);
    expect(cubit.state.runs.map((run) => run.id), ['second', 'first']);
  });

  test('a failed read can be retried', () async {
    final repository = _HistoryRepository();
    final cubit = ProductionHistoryCubit(ListProductionHistory(repository));
    addTearDown(cubit.close);

    final failedLoad = cubit.load();
    repository.pending.single.completeError(StateError('unreadable'));
    await failedLoad;
    expect(cubit.state.status, ProductionHistoryStatus.failure);

    final retry = cubit.retry();
    expect(cubit.state.status, ProductionHistoryStatus.loading);
    repository.pending.last.complete([_summary('recovered')]);
    await retry;

    expect(cubit.state.status, ProductionHistoryStatus.loaded);
    expect(cubit.state.runs.single.id, 'recovered');
  });
}
