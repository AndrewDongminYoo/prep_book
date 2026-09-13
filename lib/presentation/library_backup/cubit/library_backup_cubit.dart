import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/library_backup/view/library_backup_platform.dart';

part 'library_backup_state.dart';

/// Drives one backup or restore dialog.
final class LibraryBackupCubit extends Cubit<LibraryBackupState> {
  /// Creates the state machine over application and platform operations.
  LibraryBackupCubit({
    required CreateLibraryBackup createBackup,
    required RestoreLibraryBackup restoreBackup,
    required LibraryBackupPlatform platform,
  }) : this._(createBackup, restoreBackup, platform);

  LibraryBackupCubit._(this._createBackup, this._restoreBackup, this._platform)
    : super(const LibraryBackupState());

  final CreateLibraryBackup _createBackup;
  final RestoreLibraryBackup _restoreBackup;
  final LibraryBackupPlatform _platform;
  var _operationActive = false;

  /// Starts the selected [action] unless another action owns the dialog.
  Future<void> start(LibraryBackupAction action) async {
    if (_operationActive || state.action != null) return;
    _operationActive = true;
    try {
      switch (action) {
        case LibraryBackupAction.create:
          await _create();
        case LibraryBackupAction.restore:
          await _pickRestore();
      }
    } finally {
      _operationActive = false;
    }
  }

  Future<void> _create() async {
    emit(
      const LibraryBackupState(
        status: LibraryBackupStatus.creating,
        action: LibraryBackupAction.create,
      ),
    );
    try {
      final backup = await _createBackup();
      if (isClosed) return;
      final saved = await _platform.saveBackup(backup);
      if (isClosed) return;
      if (!saved) {
        emit(const LibraryBackupState());
        return;
      }
      emit(
        const LibraryBackupState(
          status: LibraryBackupStatus.succeeded,
          action: LibraryBackupAction.create,
        ),
      );
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace, LibraryBackupFailureKind.saveFailed);
    }
  }

  Future<void> _pickRestore() async {
    try {
      final bytes = await _platform.pickBackup();
      if (isClosed) return;
      if (bytes == null) {
        emit(const LibraryBackupState());
        return;
      }
      emit(
        LibraryBackupState(
          status: LibraryBackupStatus.awaitingConfirmation,
          action: LibraryBackupAction.restore,
          pendingRestoreBytes: bytes,
        ),
      );
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace, LibraryBackupFailureKind.restoreFailed);
    }
  }

  /// Discards a picked backup without changing the library.
  void cancelRestore() {
    if (state.status != LibraryBackupStatus.awaitingConfirmation) return;
    emit(const LibraryBackupState());
  }

  /// Restores the picked backup after explicit confirmation.
  Future<void> confirmRestore() async {
    if (_operationActive ||
        state.status != LibraryBackupStatus.awaitingConfirmation) {
      return;
    }
    final bytes = state.pendingRestoreBytes!;
    _operationActive = true;
    emit(
      const LibraryBackupState(
        status: LibraryBackupStatus.restoring,
        action: LibraryBackupAction.restore,
      ),
    );
    try {
      await _restoreBackup(bytes);
      if (isClosed) return;
      emit(
        const LibraryBackupState(
          status: LibraryBackupStatus.succeeded,
          action: LibraryBackupAction.restore,
        ),
      );
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace, LibraryBackupFailureKind.restoreFailed);
    } finally {
      _operationActive = false;
    }
  }

  void _fail(
    Object error,
    StackTrace stackTrace,
    LibraryBackupFailureKind fallback,
  ) {
    if (isClosed) return;
    final failure = error is LibraryBackupException
        ? error
        : LibraryBackupException(
            fallback,
            cause: error,
            stackTrace: stackTrace,
          );
    addError(failure.cause ?? failure, failure.stackTrace ?? stackTrace);
    emit(
      LibraryBackupState(
        status: LibraryBackupStatus.failed,
        action: state.action,
        failure: failure.kind,
      ),
    );
  }
}
