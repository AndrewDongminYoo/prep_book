import 'package:meta/meta.dart';

/// The available ways to organize production quantities.
enum ProductionSheetOrganization { batch, total }

/// A complete production-sheet document model.
@immutable
final class ProductionSheet {
  ProductionSheet({
    required this.organization,
    required this.labels,
    required this.recipeName,
    required this.recipeRevision,
    required this.targetYield,
    required this.createdAt,
    required this.rootBatchCount,
    required this.isDraft,
    required List<ProductionSheetWarning> outstandingWarnings,
    required List<ProductionSheetWarning> acknowledgedWarnings,
    required List<ProductionSheetSection> sections,
  }) : outstandingWarnings = List.unmodifiable(outstandingWarnings),
       acknowledgedWarnings = List.unmodifiable(acknowledgedWarnings),
       sections = List.unmodifiable(sections);

  final ProductionSheetOrganization organization;
  final ProductionSheetLabels labels;
  final String recipeName;
  final int recipeRevision;
  final String targetYield;
  final String createdAt;
  final int rootBatchCount;
  final bool isDraft;
  final List<ProductionSheetWarning> outstandingWarnings;
  final List<ProductionSheetWarning> acknowledgedWarnings;
  final List<ProductionSheetSection> sections;
}

/// One recipe occurrence in depth-first display order.
@immutable
final class ProductionSheetSection {
  ProductionSheetSection({
    required this.path,
    required this.depth,
    required this.recipeName,
    required this.targetYield,
    required this.batchCount,
    required List<String> preparationNotes,
    required List<ProductionSheetTable> tables,
  }) : preparationNotes = List.unmodifiable(preparationNotes),
       tables = List.unmodifiable(tables);

  final String path;
  final int depth;
  final String recipeName;
  final String targetYield;
  final int batchCount;
  final List<String> preparationNotes;
  final List<ProductionSheetTable> tables;
}

/// One total or batch-oriented component table.
@immutable
final class ProductionSheetTable {
  ProductionSheetTable({
    required this.heading,
    required this.batchYield,
    required List<ProductionSheetRow> rows,
  }) : rows = List.unmodifiable(rows);

  final String heading;
  final String? batchYield;
  final List<ProductionSheetRow> rows;
}

/// One component row with stored calculated and operator values.
@immutable
final class ProductionSheetRow {
  const ProductionSheetRow({
    required this.label,
    required this.note,
    required this.calculated,
    required this.exact,
    required this.actualWholeRun,
  });

  final String label;
  final String? note;
  final String calculated;
  final String? exact;
  final String? actualWholeRun;
}

/// Static copy used by the pure Dart renderer.
@immutable
final class ProductionSheetLabels {
  const ProductionSheetLabels({
    required this.documentTitle,
    required this.recipeRevision,
    required this.targetYield,
    required this.createdAt,
    required this.rootBatchCount,
    required this.organization,
    required this.batchOrganization,
    required this.totalOrganization,
    required this.outstandingWarnings,
    required this.acknowledgedWarnings,
    required this.sectionTarget,
    required this.sectionBatchCount,
    required this.preparationNotes,
    required this.totals,
    required this.component,
    required this.calculatedAmount,
    required this.batchYield,
    required this.exactAmount,
    required this.wholeRunActual,
    required this.manualAmount,
    required this.draft,
    required this.pagePattern,
  });

  final String documentTitle;
  final String recipeRevision;
  final String targetYield;
  final String createdAt;
  final String rootBatchCount;
  final String organization;
  final String batchOrganization;
  final String totalOrganization;
  final String outstandingWarnings;
  final String acknowledgedWarnings;
  final String sectionTarget;
  final String sectionBatchCount;
  final String preparationNotes;
  final String totals;
  final String component;
  final String calculatedAmount;
  final String batchYield;
  final String exactAmount;
  final String wholeRunActual;
  final String manualAmount;
  final String draft;
  final String pagePattern;
}

/// One warning whose stored identifiers have been resolved for display.
@immutable
final class ProductionSheetWarning {
  const ProductionSheetWarning({required this.message});

  final String message;
}
