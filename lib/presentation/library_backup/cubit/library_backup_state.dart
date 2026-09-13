part of 'library_backup_cubit.dart';

/// The operation selected for one dialog.
enum LibraryBackupAction { create, restore }

/// The observable phase of one backup or restore operation.
enum LibraryBackupStatus {
  idle,
  creating,
  awaitingConfirmation,
  restoring,
  succeeded,
  failed,
}

/// Immutable state for the library backup dialog.
@immutable
final class LibraryBackupState {
  /// Creates one state value.
  const LibraryBackupState({
    this.status = LibraryBackupStatus.idle,
    this.action,
    this.pendingRestoreBytes,
    this.failure,
  });

  final LibraryBackupStatus status;
  final LibraryBackupAction? action;
  final Uint8List? pendingRestoreBytes;
  final LibraryBackupFailureKind? failure;
}
