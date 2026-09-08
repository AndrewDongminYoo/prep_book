import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Every stored run, newest first.
final class ListProductionHistory {
  /// Creates the use case over [_runs].
  const ListProductionHistory(this._runs);

  final ProductionRunRepository _runs;

  /// Reads the history. The repository already orders it.
  Future<List<ProductionRunSummary>> call() => _runs.listSummaries();
}

/// Reopens one stored run.
final class OpenProductionRun {
  /// Creates the use case over [_runs].
  const OpenProductionRun(this._runs);

  final ProductionRunRepository _runs;

  /// The run stored under [runId], or null when it is gone.
  ///
  /// Never recalculated against the current recipe: the snapshot is what
  /// was stored, and editing or archiving the source recipe afterwards does
  /// not reach it.
  Future<ProductionRun?> call(String runId) => _runs.findById(runId);
}
