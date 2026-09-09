import 'package:flutter/material.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/production_setup/view/production_setup_page.dart';

/// Opens the production setup screen.
///
/// One value threaded through the library screen rather than a use case,
/// and the one place this route is built — the same shape, and for the same
/// reason, as the editor's launcher: two callers must not be able to drift
/// into opening two differently-configured screens.
@immutable
final class ProductionSetupLauncher {
  /// Creates a launcher over the use case the screen calculates through.
  const ProductionSetupLauncher(this.startProductionRun);

  /// Calculates a run for a target yield without storing it.
  final StartProductionRun startProductionRun;

  /// Pushes the production setup screen over [recipe].
  ///
  /// Returns nothing, unlike the editor's launcher: this screen stores
  /// nothing, so a caller has nothing to read again when it comes back.
  Future<void> open(BuildContext context, {required Recipe recipe}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ProductionSetupPage(
            startProductionRun: startProductionRun,
            recipe: recipe,
          ),
        ),
      );
}
