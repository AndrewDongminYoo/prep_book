import 'package:flutter/material.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/production_result/view/production_result_page.dart';

/// Opens the production result screen.
///
/// The three use cases threaded through the production setup screen, and
/// the one place this route is built — the same shape, and for the same
/// reason, as the two launchers before it: two callers must not be able to
/// drift into opening two differently-configured screens.
@immutable
final class ProductionResultLauncher {
  /// Creates a launcher over the use cases the screen reviews through.
  const ProductionResultLauncher({
    required this.acknowledgeWarning,
    required this.applyOverride,
    required this.saveProductionRun,
  });

  /// Marks one warning as seen.
  final AcknowledgeWarning acknowledgeWarning;

  /// Records an operator-entered quantity for one component.
  final ApplyOverride applyOverride;

  /// Commits a calculated run as an immutable snapshot.
  final SaveProductionRun saveProductionRun;

  /// Pushes the production result screen over the calculated [run].
  ///
  /// Returns nothing. The screen stores the run under an identifier the
  /// caller already holds, and reopening a stored run is the history
  /// screen's job, so there is nothing here for a caller to read back.
  Future<void> open(BuildContext context, {required ProductionRun run}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ProductionResultPage(
            acknowledgeWarning: acknowledgeWarning,
            applyOverride: applyOverride,
            saveProductionRun: saveProductionRun,
            run: run,
          ),
        ),
      );
}
