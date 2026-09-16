import 'package:flutter/material.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/production_history/view/production_history_page.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_launcher.dart';

/// Opens the read-only production history screen.
@immutable
final class ProductionHistoryLauncher {
  /// Creates the route over its history reads and sheet destination.
  const ProductionHistoryLauncher({
    required this.listHistory,
    required this.openProductionRun,
    required this.productionSheet,
  });

  final ListProductionHistory listHistory;
  final OpenProductionRun openProductionRun;
  final ProductionSheetLauncher productionSheet;

  /// Pushes the production history screen.
  Future<void> open(BuildContext context) => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => ProductionHistoryPage(
        listHistory: listHistory,
        openProductionRun: openProductionRun,
        productionSheet: productionSheet,
      ),
    ),
  );
}
