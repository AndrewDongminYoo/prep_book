import 'package:flutter/material.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_page.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_platform.dart';

/// Opens the production-sheet preview for one stored run.
@immutable
final class ProductionSheetLauncher {
  const ProductionSheetLauncher({required this.platform});

  final ProductionSheetPlatform platform;

  Future<void> open(BuildContext context, {required ProductionRun run}) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ProductionSheetPage(run: run, platform: platform),
        ),
      );
}
