import 'dart:typed_data';

/// Maximum encoded backup size accepted by the application.
const int maxLibraryBackupBytes = 256 * 1024 * 1024;

/// Stable failure categories that presentation code can localize.
enum LibraryBackupFailureKind {
  cancelled,
  unsupportedFormat,
  invalidArchive,
  backupTooLarge,
  invalidDatabase,
  incompatibleSchema,
  saveFailed,
  restoreFailed,
  recoveryFailed,
}

/// A localized-message-safe backup or restore failure.
final class LibraryBackupException implements Exception {
  const LibraryBackupException(this.kind, {this.cause, this.stackTrace});

  /// The category presentation code maps to operator-facing copy.
  final LibraryBackupFailureKind kind;

  /// The underlying diagnostic error, which must not be rendered directly.
  final Object? cause;

  /// The underlying diagnostic stack trace.
  final StackTrace? stackTrace;
}

/// A complete portable library backup and its suggested filename.
final class LibraryBackupFile {
  /// Creates a backup value that cannot be changed through [bytes].
  LibraryBackupFile({required Uint8List bytes, required this.suggestedName})
    : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;

  /// A defensive copy of the encoded archive.
  Uint8List get bytes => Uint8List.fromList(_bytes);

  /// The filename offered to the native save interface.
  final String suggestedName;
}

/// Infrastructure operations used by the backup application use cases.
abstract interface class LibraryBackupGateway {
  /// Creates a complete, validated backup archive.
  Future<LibraryBackupFile> create();

  /// Validates, restores, and activates [archiveBytes].
  Future<void> restore(Uint8List archiveBytes);
}

/// Creates a complete portable library backup.
final class CreateLibraryBackup {
  const CreateLibraryBackup(this._gateway);

  final LibraryBackupGateway _gateway;

  /// Creates the archive and its suggested filename.
  Future<LibraryBackupFile> call() => _gateway.create();
}

/// Replaces the active library from a validated portable backup.
final class RestoreLibraryBackup {
  const RestoreLibraryBackup(this._gateway);

  final LibraryBackupGateway _gateway;

  /// Completes only after [archiveBytes] is active or recovery has settled.
  Future<void> call(Uint8List archiveBytes) => _gateway.restore(archiveBytes);
}
