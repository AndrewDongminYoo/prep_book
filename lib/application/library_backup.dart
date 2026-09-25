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
  const new(this.kind, {this.cause, this.stackTrace});

  /// The category presentation code maps to operator-facing copy.
  final LibraryBackupFailureKind kind;

  /// The underlying diagnostic error, which must not be rendered directly.
  final Object? cause;

  /// The underlying diagnostic stack trace.
  final StackTrace? stackTrace;
}

/// A portable backup archive, read as a stream rather than handed over as
/// one buffer.
///
/// Passing a readable archive instead of its bytes means nothing between
/// creating a backup and saving or restoring it has to hold the whole
/// archive in memory; a near-limit library otherwise kept several full-size
/// copies alive at once. [length] is known without reading the archive, so
/// a size check can run before any content is read.
///
/// Whoever receives an archive owns it: it calls [discard] once it no longer
/// needs the content, and nothing else releases it.
abstract interface class LibraryBackupArchive {
  /// The archive size in bytes.
  int get length;

  /// Opens a fresh read of the whole archive.
  ///
  /// Each call starts from the first byte, and a read that yields a total
  /// other than [length] means the content changed underneath it.
  Stream<List<int>> openRead();

  /// Releases whatever holds the archive. Calling it again does nothing.
  Future<void> discard();
}

/// A newly created backup and the filename offered for it.
final class LibraryBackupFile {
  /// Creates a backup over [archive].
  const new({required this.archive, required this.suggestedName});

  /// The encoded archive, owned by whoever received this backup.
  final LibraryBackupArchive archive;

  /// The filename offered to the native save interface.
  final String suggestedName;
}

/// Infrastructure operations used by the backup application use cases.
abstract interface class LibraryBackupGateway {
  /// Creates a complete, validated backup archive.
  ///
  /// The caller owns the returned archive and discards it once it has been
  /// saved or abandoned.
  Future<LibraryBackupFile> create();

  /// Validates, restores, and activates [archive].
  ///
  /// Reads [archive] and never discards it; the caller still owns it.
  Future<void> restore(LibraryBackupArchive archive);
}

/// Creates a complete portable library backup.
final class CreateLibraryBackup {
  const new(this._gateway);

  final LibraryBackupGateway _gateway;

  /// Creates the archive and its suggested filename.
  Future<LibraryBackupFile> call() => _gateway.create();
}

/// Replaces the active library from a validated portable backup.
final class RestoreLibraryBackup {
  const new(this._gateway);

  final LibraryBackupGateway _gateway;

  /// Completes only after [archive] is active or recovery has settled.
  Future<void> call(LibraryBackupArchive archive) => _gateway.restore(archive);
}
