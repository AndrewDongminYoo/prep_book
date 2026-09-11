import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/export/export.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/units/readable_quantity.dart';

/// Adapts generated application copy to the presentation-independent export.
final class AppProductionSheetLocalizations
    implements ProductionSheetLocalizations {
  const AppProductionSheetLocalizations({
    required this.localizations,
    required this.locale,
  });

  final AppLocalizations localizations;
  final Locale locale;

  @override
  ProductionSheetLabels get labels => ProductionSheetLabels(
    documentTitle: localizations.productionSheetDocumentTitle,
    recipeRevision: localizations.productionSheetRecipeRevision,
    targetYield: localizations.productionSheetTargetYield,
    createdAt: localizations.productionSheetCreatedAt,
    rootBatchCount: localizations.productionSheetRootBatchCount,
    organization: localizations.productionSheetOrganization,
    batchOrganization: localizations.productionSheetBatchOrganization,
    totalOrganization: localizations.productionSheetTotalOrganization,
    outstandingWarnings: localizations.productionSheetOutstandingWarnings,
    acknowledgedWarnings: localizations.productionSheetAcknowledgedWarnings,
    sectionTarget: localizations.productionSheetSectionTarget,
    sectionBatchCount: localizations.productionSheetSectionBatchCount,
    preparationNotes: localizations.productionSheetPreparationNotes,
    totals: localizations.productionSheetTotals,
    component: localizations.productionSheetComponent,
    calculatedAmount: localizations.productionSheetCalculatedAmount,
    batchYield: localizations.productionSheetBatchYield,
    exactAmount: localizations.productionSheetExactAmount,
    wholeRunActual: localizations.productionSheetWholeRunActual,
    manualAmount: localizations.productionSheetManualAmount,
    draft: localizations.productionSheetDraft,
    pagePattern: localizations.productionSheetPage('{current}', '{total}'),
  );

  @override
  String batch(int number) => localizations.productionSheetBatch(number);

  @override
  String batchRange(int first, int last) =>
      localizations.productionSheetBatchRange(first, last);

  @override
  String formatCreatedAt(DateTime createdAtUtc) {
    final value = DateFormat.yMMMd(
      locale.toLanguageTag(),
    ).add_Hm().format(createdAtUtc.toUtc());
    return '$value ${localizations.productionSheetUtc}';
  }

  @override
  String formatQuantity(Quantity quantity) => readableQuantity(quantity);

  @override
  String warningMessage({
    required ProductionWarning warning,
    required String recipeName,
    String? componentName,
  }) => switch (warning) {
    ManualComponentWarning(:final componentId) =>
      localizations.productionResultManualWarning(
        componentName ?? componentId,
        recipeName,
      ),
    RoundingAdjustedWarning(:final componentId) =>
      localizations.productionResultRoundingWarning(
        componentName ?? componentId,
        recipeName,
      ),
    ArchivedDependencyWarning() =>
      localizations.productionResultArchivedWarning(recipeName),
  };
}
