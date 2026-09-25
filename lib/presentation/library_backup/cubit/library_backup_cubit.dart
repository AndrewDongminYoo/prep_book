import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/library_backup/view/library_backup_platform.dart';

part 'library_backup_state.dart';

/// Drives one backup or restore dialog.
///
/// Every archive this cubit receives is its to discard: a created backup
/// once the save settles, a picked one once it is restored or cancelled, and
/// whichever is still held when the dialog closes. Each is staged in a file
/// rather than memory, so a forgotten one costs disk space until the
/// platform reclaims its temporary directory.
final class LibraryBackupCubit extends Cubit<LibraryBackupState> {
  /// Creates the state machine over application and platform operations.
  new({
    required CreateLibraryBackup createBackup,
    required RestoreLibraryBackup restoreBackup,
    required LibraryBackupPlatform platform,
  }) : this._(createBackup, restoreBackup, platform);

  new _(this._createBackup, this._restoreBackup, this._platform) : super(const LibraryBackupState());

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
      final bool saved;
      try {
        if (isClosed) return;
        saved = await _platform.saveBackup(backup);
      } finally {
        await backup.archive.discard();
      }
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
      final archive = await _platform.pickBackup();
      if (archive == null) {
        if (!isClosed) emit(const LibraryBackupState());
        return;
      }
      if (isClosed) {
        await archive.discard();
        return;
      }
      emit(
        LibraryBackupState(
          status: LibraryBackupStatus.awaitingConfirmation,
          action: LibraryBackupAction.restore,
          pendingRestore: archive,
        ),
      );
    } on Object catch (error, stackTrace) {
      _fail(error, stackTrace, LibraryBackupFailureKind.restoreFailed);
    }
  }

  /// Discards a picked backup without changing the library.
  Future<void> cancelRestore() async {
    if (state.status != LibraryBackupStatus.awaitingConfirmation) return;
    final archive = state.pendingRestore!;
    emit(const LibraryBackupState());
    await archive.discard();
  }

  /// Restores the picked backup after explicit confirmation.
  Future<void> confirmRestore() async {
    if (_operationActive || state.status != LibraryBackupStatus.awaitingConfirmation) {
      return;
    }
    final archive = state.pendingRestore!;
    _operationActive = true;
    emit(
      const LibraryBackupState(
        status: LibraryBackupStatus.restoring,
        action: LibraryBackupAction.restore,
      ),
    );
    try {
      try {
        await _restoreBackup(archive);
      } finally {
        await archive.discard();
      }
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

  /// Discards a picked backup still awaiting confirmation.
  @override
  Future<void> close() async {
    final pending = state.status == LibraryBackupStatus.awaitingConfirmation ? state.pendingRestore : null;
    await super.close();
    await pending?.discard();
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
