import 'dart:async';

import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/archive_codec.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/backup/database_session.dart';
import 'package:prep_book/persistence/persistence.dart';

/// Copies one validated live-database state to [destinationPath].
typedef CreateDatabaseSnapshot = Future<void> Function(String destinationPath);

/// Encodes the database file at [databasePath] into the portable backup
/// envelope at [archivePath].
typedef EncodeBackupArchive = Future<void> Function({
  required String databasePath,
  required String archivePath,
  required int databaseSchemaVersion,
  required DateTime createdAtUtc,
});

/// Decodes and validates the portable backup envelope at [archivePath],
/// writing its database to [databasePath].
typedef DecodeBackupArchive = Future<DecodedLibraryBackup> Function({
  required String archivePath,
  required String databasePath,
});

/// Replaces the active database with the one [stageCandidate] writes.
typedef RestoreDatabaseSnapshot = Future<void> Function(
  StageRestoreCandidate stageCandidate,
);

/// Composes archive and database operations behind the application gateway.
///
/// Every full-size artifact — the snapshot, the archive, the staged restore
/// input — lives in a file inside a temporary directory, never in memory. A
/// created archive's directory is released by the archive's own `discard`;
/// a restore's directory is removed before [restore] completes.
final class DatabaseLibraryBackupGateway implements LibraryBackupGateway {
  /// Creates one serialized backup gateway.
  new({
    required CreateDatabaseSnapshot createSnapshot,
    required EncodeBackupArchive encodeArchive,
    required DecodeBackupArchive decodeArchive,
    required RestoreDatabaseSnapshot restoreDatabase,
    required BackupFiles files,
    required DateTime Function() now,
    int maxArchiveBytes = maxLibraryBackupBytes,
  }) : this._(
         createSnapshot,
         encodeArchive,
         decodeArchive,
         restoreDatabase,
         files,
         now,
         maxArchiveBytes,
       );

  new _(
    this._createSnapshot,
    this._encodeArchive,
    this._decodeArchive,
    this._restoreDatabase,
    this._files,
    this._now,
    this._maxArchiveBytes,
  ) : assert(_maxArchiveBytes > 0, 'maxArchiveBytes must be positive.');

  final CreateDatabaseSnapshot _createSnapshot;
  final EncodeBackupArchive _encodeArchive;
  final DecodeBackupArchive _decodeArchive;
  final RestoreDatabaseSnapshot _restoreDatabase;
  final BackupFiles _files;
  final DateTime Function() _now;
  final int _maxArchiveBytes;
  Future<Object?>? _inFlight;

  @override
  Future<LibraryBackupFile> create() => _runSerialized(
    busyKind: LibraryBackupFailureKind.saveFailed,
    operation: () async {
      String? directory;
      try {
        directory = await _files.createTemporaryDirectory('prep-book-backup-');
        final snapshotPath = '$directory/library.db';
        final archivePath = '$directory/backup.prepbook';
        await _createSnapshot(snapshotPath);
        final createdAt = _now();
        await _encodeArchive(
          databasePath: snapshotPath,
          archivePath: archivePath,
          databaseSchemaVersion: currentSchemaVersion,
          createdAtUtc: createdAt.toUtc(),
        );
        // Released as soon as the archive holds it, so a near-limit backup
        // does not keep two full-size files until the save finishes.
        await _files.deleteIfExists(snapshotPath);
        return LibraryBackupFile(
          archive: StagedBackupArchive(
            path: archivePath,
            length: await _files.length(archivePath),
            directory: directory,
            files: _files,
          ),
          suggestedName: buildLibraryBackupFilename(createdAt.toLocal()),
        );
      } on Object catch (error, stackTrace) {
        if (directory != null) await _deleteQuietly(directory);
        if (error is LibraryBackupException) rethrow;
        throw LibraryBackupException(
          LibraryBackupFailureKind.saveFailed,
          cause: error,
          stackTrace: stackTrace,
        );
      }
    },
  );

  @override
  Future<void> restore(LibraryBackupArchive archive) => _runSerialized(
    busyKind: LibraryBackupFailureKind.restoreFailed,
    operation: () async {
      String? directory;
      try {
        if (archive.length > _maxArchiveBytes) _throwTooLarge();
        directory = await _files.createTemporaryDirectory('prep-book-restore-');
        final archivePath = '$directory/restore.prepbook';
        final staged = await _files.writeStream(
          archivePath,
          _bounded(archive.openRead(), maxBytes: _maxArchiveBytes),
          flush: false,
        );
        if (staged != archive.length) {
          throw StateError('The backup size changed while it was read.');
        }
        await _restoreDatabase((candidatePath) async {
          final decoded = await _decodeArchive(
            archivePath: archivePath,
            databasePath: candidatePath,
          );
          return decoded.databaseSchemaVersion;
        });
      } on LibraryBackupException {
        rethrow;
      } on Object catch (error, stackTrace) {
        throw LibraryBackupException(
          LibraryBackupFailureKind.restoreFailed,
          cause: error,
          stackTrace: stackTrace,
        );
      } finally {
        if (directory != null) await _deleteQuietly(directory);
      }
    },
  );

  /// [content], failing with `backupTooLarge` once it passes [maxBytes], so
  /// an archive that grows while it is read stops before it fills the disk.
  Stream<List<int>> _bounded(
    Stream<List<int>> content, {
    required int maxBytes,
  }) {
    var length = 0;
    return content.map((chunk) {
      if (chunk.length > maxBytes - length) _throwTooLarge();
      length += chunk.length;
      return chunk;
    });
  }

  /// Removes a temporary [directory] without letting a cleanup failure hide
  /// the outcome the operation already reached.
  Future<void> _deleteQuietly(String directory) async {
    try {
      await _files.deleteDirectory(directory);
    } on Object {
      // A leftover temporary directory is the platform's to reclaim.
    }
  }

  Future<T> _runSerialized<T>({
    required LibraryBackupFailureKind busyKind,
    required Future<T> Function() operation,
  }) {
    if (_inFlight != null) {
      return Future<T>.error(
        LibraryBackupException(
          busyKind,
          cause: StateError('A library backup operation is already running.'),
          stackTrace: StackTrace.current,
        ),
      );
    }

    final future = Future<T>.sync(operation);
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }
}

Never _throwTooLarge() {
  throw LibraryBackupException(
    LibraryBackupFailureKind.backupTooLarge,
    cause: const FormatException('The backup exceeds the supported size.'),
    stackTrace: StackTrace.current,
  );
}
