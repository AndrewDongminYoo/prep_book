import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Records that the operator has seen a warning.
///
/// One domain call, kept as a use case so the presentation unit never
/// reaches past this layer into the domain to mutate a run, and so a later
/// rule about which warnings may be acknowledged has one place to live.
final class AcknowledgeWarning {
  /// Creates the use case.
  const AcknowledgeWarning();

  /// [run] with [warning] marked as seen.
  ProductionRun call(ProductionRun run, ProductionWarning warning) =>
      run.acknowledge(warning);
}

/// Records an operator-entered quantity for one component.
final class ApplyOverride {
  /// Creates the use case.
  const ApplyOverride();

  /// [run] with [value] recorded for [componentId] of [recipeId].
  ///
  /// The calculated result is never rewritten, so the original stays
  /// available for comparison.
  ProductionRun call(
    ProductionRun run, {
    required String recipeId,
    required String componentId,
    required Quantity value,
  }) =>
      run.override(recipeId: recipeId, componentId: componentId, value: value);
}

/// Commits a calculated run and the state it carries.
final class SaveProductionRun {
  /// Creates the use case over [_runs].
  const SaveProductionRun(this._runs);

  final ProductionRunRepository _runs;

  /// Writes [run], its acknowledgements, and its overrides in one
  /// transaction, which [ProductionRunRepository.save] already provides.
  ///
  /// `recordAcknowledgement` and `recordOverride` are not called here. Those
  /// exist for state recorded against a run that is already stored; calling
  /// them for a first save would write the same rows twice.
  ///
  /// A run that is not `isFinalizable` is saved all the same. Acknowledgement
  /// is a precondition of finalizing a run, not of storing one, and a screen
  /// that saves a draft is not finalizing it.
  Future<void> call(ProductionRun run) => _runs.save(run);
}
