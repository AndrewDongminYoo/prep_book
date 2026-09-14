import 'dart:async';
import 'dart:typed_data';

import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/archive_codec.dart';
import 'package:prep_book/persistence/persistence.dart';

/// Produces validated bytes from the currently active database.
typedef CreateDatabaseSnapshot = Future<Uint8List> Function();

/// Encodes database bytes into the portable backup envelope.
typedef EncodeBackupArchive =
    Uint8List Function({
      required Uint8List databaseBytes,
      required int databaseSchemaVersion,
      required DateTime createdAtUtc,
    });

/// Decodes and validates the portable backup envelope.
typedef DecodeBackupArchive = DecodedLibraryBackup Function(Uint8List bytes);

/// Replaces the active database with validated decoded bytes.
typedef RestoreDatabaseSnapshot =
    Future<void> Function(
      Uint8List databaseBytes, {
      required int manifestSchemaVersion,
    });

/// Composes archive and database operations behind the application gateway.
final class DatabaseLibraryBackupGateway implements LibraryBackupGateway {
  /// Creates one serialized backup gateway.
  DatabaseLibraryBackupGateway({
    required CreateDatabaseSnapshot createSnapshot,
    required EncodeBackupArchive encodeArchive,
    required DecodeBackupArchive decodeArchive,
    required RestoreDatabaseSnapshot restoreDatabase,
    required DateTime Function() now,
    int maxArchiveBytes = maxLibraryBackupBytes,
  }) : this._(
         createSnapshot,
         encodeArchive,
         decodeArchive,
         restoreDatabase,
         now,
         maxArchiveBytes,
       );

  DatabaseLibraryBackupGateway._(
    this._createSnapshot,
    this._encodeArchive,
    this._decodeArchive,
    this._restoreDatabase,
    this._now,
    this._maxArchiveBytes,
  ) : assert(_maxArchiveBytes > 0, 'maxArchiveBytes must be positive.');

  final CreateDatabaseSnapshot _createSnapshot;
  final EncodeBackupArchive _encodeArchive;
  final DecodeBackupArchive _decodeArchive;
  final RestoreDatabaseSnapshot _restoreDatabase;
  final DateTime Function() _now;
  final int _maxArchiveBytes;
  Future<Object?>? _inFlight;

  @override
  Future<LibraryBackupFile> create() => _runSerialized(
    busyKind: LibraryBackupFailureKind.saveFailed,
    operation: () async {
      try {
        final databaseBytes = await _createSnapshot();
        final createdAt = _now();
        final archiveBytes = _encodeArchive(
          databaseBytes: databaseBytes,
          databaseSchemaVersion: currentSchemaVersion,
          createdAtUtc: createdAt.toUtc(),
        );
        return LibraryBackupFile.takeOwnership(
          bytes: archiveBytes,
          suggestedName: buildLibraryBackupFilename(createdAt.toLocal()),
        );
      } on LibraryBackupException {
        rethrow;
      } on Object catch (error, stackTrace) {
        throw LibraryBackupException(
          LibraryBackupFailureKind.saveFailed,
          cause: error,
          stackTrace: stackTrace,
        );
      }
    },
  );

  @override
  Future<void> restore(Uint8List archiveBytes) => _runSerialized(
    busyKind: LibraryBackupFailureKind.restoreFailed,
    operation: () async {
      try {
        if (archiveBytes.length > _maxArchiveBytes) {
          throw LibraryBackupException(
            LibraryBackupFailureKind.backupTooLarge,
            cause: const FormatException(
              'The backup exceeds the supported size.',
            ),
            stackTrace: StackTrace.current,
          );
        }
        final decoded = _decodeArchive(archiveBytes);
        await _restoreDatabase(
          decoded.databaseBytes,
          manifestSchemaVersion: decoded.databaseSchemaVersion,
        );
      } on LibraryBackupException {
        rethrow;
      } on Object catch (error, stackTrace) {
        throw LibraryBackupException(
          LibraryBackupFailureKind.restoreFailed,
          cause: error,
          stackTrace: stackTrace,
        );
      }
    },
  );

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
