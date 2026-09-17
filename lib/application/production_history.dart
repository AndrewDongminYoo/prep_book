import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// The storage-neutral fields a production history row renders.
final class ProductionHistoryEntry {
  /// Creates one history entry from stored snapshot metadata.
  const new({
    required this.id,
    required this.recipeId,
    required this.recipeName,
    required this.recipeRevision,
    required this.targetYield,
    required this.createdAt,
    required this.isDraft,
  });

  final String id;
  final String recipeId;
  final String recipeName;
  final int recipeRevision;
  final Quantity targetYield;
  final DateTime createdAt;
  final bool isDraft;
}

/// Every stored run, newest first.
final class ListProductionHistory {
  /// Creates the use case over [_runs].
  const new(this._runs);

  final ProductionRunRepository _runs;

  /// Reads the history. The repository already orders it.
  Future<List<ProductionHistoryEntry>> call() async => [
    for (final summary in await _runs.listSummaries())
      ProductionHistoryEntry(
        id: summary.id,
        recipeId: summary.recipeId,
        recipeName: summary.recipeName,
        recipeRevision: summary.recipeRevision,
        targetYield: summary.targetYield,
        createdAt: summary.createdAt,
        isDraft: summary.isDraft,
      ),
  ];
}

/// Reopens one stored run.
final class OpenProductionRun {
  /// Creates the use case over [_runs].
  const new(this._runs);

  final ProductionRunRepository _runs;

  /// The run stored under [runId], or null when it is gone.
  ///
  /// Never recalculated against the current recipe: the snapshot is what
  /// was stored, and editing or archiving the source recipe afterwards does
  /// not reach it.
  Future<ProductionRun?> call(String runId) => _runs.findById(runId);
}
