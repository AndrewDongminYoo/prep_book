part of 'production_sheet_cubit.dart';

enum ProductionSheetStatus { generating, ready, failure }

enum ProductionSheetActionStatus { idle, sharing, printing }

/// Generation and platform-action state for one production sheet.
@immutable
final class ProductionSheetState {
  const ProductionSheetState({
    this.organization = ProductionSheetOrganization.batch,
    this.status = ProductionSheetStatus.generating,
    this.bytes,
    this.filename,
    this.generationError,
    this.actionStatus = ProductionSheetActionStatus.idle,
    this.actionError,
    this.failedAction,
  });

  final ProductionSheetOrganization organization;
  final ProductionSheetStatus status;
  final Uint8List? bytes;
  final String? filename;
  final Object? generationError;
  final ProductionSheetActionStatus actionStatus;
  final Object? actionError;
  final ProductionSheetActionStatus? failedAction;

  bool get canUsePdfActions =>
      status == ProductionSheetStatus.ready &&
      bytes != null &&
      filename != null &&
      actionStatus == ProductionSheetActionStatus.idle;
}
