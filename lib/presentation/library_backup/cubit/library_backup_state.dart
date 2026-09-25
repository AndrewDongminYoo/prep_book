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
  const new({
    this.status = LibraryBackupStatus.idle,
    this.action,
    this.pendingRestore,
    this.failure,
  });

  final LibraryBackupStatus status;
  final LibraryBackupAction? action;

  /// The picked backup awaiting confirmation, owned by the cubit until it
  /// is restored, cancelled, or the dialog closes.
  final LibraryBackupArchive? pendingRestore;
  final LibraryBackupFailureKind? failure;
}
