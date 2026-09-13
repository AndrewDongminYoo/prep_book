import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/persistence/database.dart';

const _manifestEntryName = 'manifest.json';
const _databaseEntryName = 'library.db';
const _backupFormat = 'prep_book_backup';
const _backupFormatVersion = 1;

/// The validated contents of one portable library backup.
final class DecodedLibraryBackup {
  /// Creates decoded backup data with owned database bytes.
  DecodedLibraryBackup({
    required Uint8List databaseBytes,
    required this.databaseSchemaVersion,
    required this.createdAtUtc,
  }) : _databaseBytes = Uint8List.fromList(databaseBytes);

  final Uint8List _databaseBytes;

  /// An unmodifiable view of the owned SQLite database bytes.
  Uint8List get databaseBytes => _databaseBytes.asUnmodifiableView();

  /// The schema version declared by the manifest.
  final int databaseSchemaVersion;

  /// The instant at which the backup was created.
  final DateTime createdAtUtc;
}

/// Encodes and decodes version 1 PrepBook backup archives.
final class BackupArchiveCodec {
  /// Creates the codec.
  const BackupArchiveCodec({
    int maxArchiveBytes = maxLibraryBackupBytes,
    int maxDatabaseBytes = maxLibraryBackupBytes,
  }) : assert(maxArchiveBytes > 0, 'maxArchiveBytes must be positive.'),
       assert(maxDatabaseBytes > 0, 'maxDatabaseBytes must be positive.'),
       _maxArchiveBytes = maxArchiveBytes,
       _maxDatabaseBytes = maxDatabaseBytes;

  final int _maxArchiveBytes;
  final int _maxDatabaseBytes;

  /// Encodes one manifest and one SQLite database into a ZIP archive.
  Uint8List encode({
    required Uint8List databaseBytes,
    required int databaseSchemaVersion,
    required DateTime createdAtUtc,
  }) {
    if (databaseBytes.length > _maxDatabaseBytes) {
      _throwBackupTooLarge();
    }
    final manifest = <String, Object>{
      'format': _backupFormat,
      'formatVersion': _backupFormatVersion,
      'databaseSchemaVersion': databaseSchemaVersion,
      'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      'databaseEntry': _databaseEntryName,
    };
    final archive = Archive()
      ..add(ArchiveFile.string(_manifestEntryName, jsonEncode(manifest)))
      ..add(ArchiveFile.bytes(_databaseEntryName, databaseBytes));
    final encoded = ZipEncoder().encodeBytes(
      archive,
      modified: createdAtUtc.toUtc(),
    );
    if (encoded.length > _maxArchiveBytes) {
      _throwBackupTooLarge();
    }
    return encoded;
  }

  /// Decodes one version 1 backup archive.
  DecodedLibraryBackup decode(Uint8List archiveBytes) {
    if (archiveBytes.length > _maxArchiveBytes) {
      _throwBackupTooLarge();
    }
    final List<ZipFileHeader> headers;
    try {
      final directory = ZipDirectory()..read(InputMemoryStream(archiveBytes));
      headers = directory.fileHeaders;
    } on Object catch (error, stackTrace) {
      throw LibraryBackupException(
        LibraryBackupFailureKind.invalidArchive,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    for (final header in headers) {
      final maxEntryBytes = header.filename == _databaseEntryName
          ? _maxDatabaseBytes
          : _maxArchiveBytes;
      if (header.uncompressedSize > maxEntryBytes) {
        _throwBackupTooLarge();
      }
    }
    _validateArchiveStructure(headers);
    final ArchiveFile manifestEntry;
    final ArchiveFile databaseEntry;
    try {
      final archive = ZipDecoder().decodeBytes(archiveBytes);
      manifestEntry =
          archive.find(_manifestEntryName) ??
          (throw const FormatException(
            'The manifest entry could not be decoded.',
          ));
      databaseEntry =
          archive.find(_databaseEntryName) ??
          (throw const FormatException(
            'The database entry could not be decoded.',
          ));
    } on Object catch (error, stackTrace) {
      _throwBackupFailure(
        LibraryBackupFailureKind.invalidArchive,
        error,
        stackTrace,
      );
    }
    final manifestBytes = _readAndVerify(
      manifestEntry,
      maxBytes: _maxArchiveBytes,
    );
    final databaseBytes = _readAndVerify(
      databaseEntry,
      maxBytes: _maxDatabaseBytes,
    );
    final manifest = _decodeManifest(manifestBytes);
    return DecodedLibraryBackup(
      databaseBytes: databaseBytes,
      databaseSchemaVersion: manifest.databaseSchemaVersion,
      createdAtUtc: manifest.createdAtUtc,
    );
  }
}

Uint8List _readAndVerify(ArchiveFile entry, {required int maxBytes}) {
  final Uint8List bytes;
  try {
    final output = _BoundedOutputMemoryStream(maxBytes);
    entry.decompress(output);
    bytes = output.getBytes();
  } on _ArchiveEntryTooLarge {
    _throwBackupTooLarge();
  } on Object catch (error, stackTrace) {
    _throwBackupFailure(
      LibraryBackupFailureKind.invalidArchive,
      error,
      stackTrace,
    );
  }
  if (bytes.length != entry.size ||
      entry.crc32 == null ||
      getCrc32(bytes) != entry.crc32) {
    _throwInvalidArchive('The archive entry checksum or size is invalid.');
  }
  return bytes;
}

final class _ArchiveEntryTooLarge implements Exception {
  const _ArchiveEntryTooLarge();
}

final class _BoundedOutputMemoryStream extends OutputMemoryStream {
  _BoundedOutputMemoryStream(this._maxBytes);

  final int _maxBytes;

  @override
  void writeByte(int value) {
    _checkAdditionalBytes(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final writeLength = length ?? bytes.length;
    _checkAdditionalBytes(writeLength);
    super.writeBytes(bytes, length: writeLength);
  }

  @override
  void writeStream(InputStream stream) {
    _checkAdditionalBytes(stream.length);
    super.writeStream(stream);
  }

  void _checkAdditionalBytes(int count) {
    if (count > _maxBytes - length) {
      throw const _ArchiveEntryTooLarge();
    }
  }
}

({int databaseSchemaVersion, DateTime createdAtUtc}) _decodeManifest(
  Uint8List bytes,
) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes));
  } on Object catch (error, stackTrace) {
    _throwBackupFailure(
      LibraryBackupFailureKind.invalidArchive,
      error,
      stackTrace,
    );
  }
  if (decoded is! Map<String, Object?>) {
    _throwInvalidArchive('The backup manifest is not an object.');
  }
  final format = decoded['format'];
  final formatVersion = decoded['formatVersion'];
  final databaseSchemaVersion = decoded['databaseSchemaVersion'];
  final createdAtText = decoded['createdAtUtc'];
  final databaseEntry = decoded['databaseEntry'];
  if (format is! String ||
      formatVersion is! int ||
      databaseSchemaVersion is! int ||
      createdAtText is! String ||
      databaseEntry is! String) {
    _throwInvalidArchive('The backup manifest fields are invalid.');
  }
  if (format != _backupFormat || formatVersion != _backupFormatVersion) {
    _throwBackupFailure(
      LibraryBackupFailureKind.unsupportedFormat,
      const FormatException('The backup format is unsupported.'),
      StackTrace.current,
    );
  }
  if (databaseSchemaVersion <= 0) {
    _throwInvalidArchive('The database schema version is invalid.');
  }
  if (databaseSchemaVersion > currentSchemaVersion) {
    _throwBackupFailure(
      LibraryBackupFailureKind.incompatibleSchema,
      const FormatException('The database schema is newer than this build.'),
      StackTrace.current,
    );
  }
  if (databaseEntry != _databaseEntryName) {
    _throwInvalidArchive('The database entry name is invalid.');
  }
  final DateTime createdAtUtc;
  try {
    final fields = _utcTimestampPattern.firstMatch(createdAtText);
    if (fields == null) {
      throw const FormatException('The backup timestamp is not UTC.');
    }
    createdAtUtc = DateTime.parse(createdAtText);
    final parsedFields = [
      createdAtUtc.year,
      createdAtUtc.month,
      createdAtUtc.day,
      createdAtUtc.hour,
      createdAtUtc.minute,
      createdAtUtc.second,
    ];
    final declaredFields = [
      for (var index = 1; index <= 6; index++) int.parse(fields.group(index)!),
    ];
    if (!createdAtUtc.isUtc ||
        !parsedFields.indexed.every(
          (field) => field.$2 == declaredFields[field.$1],
        )) {
      throw const FormatException('The backup timestamp is not UTC.');
    }
  } on Object catch (error, stackTrace) {
    _throwBackupFailure(
      LibraryBackupFailureKind.invalidArchive,
      error,
      stackTrace,
    );
  }
  return (
    databaseSchemaVersion: databaseSchemaVersion,
    createdAtUtc: createdAtUtc,
  );
}

final _utcTimestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?Z$',
);

void _validateArchiveStructure(List<ZipFileHeader> headers) {
  const requiredNames = {_manifestEntryName, _databaseEntryName};
  final names = <String>{};
  for (final header in headers) {
    final fileType = header.externalFileAttributes >> 16 & 0xf000;
    final isRegularFile =
        header.filename.isNotEmpty &&
        !header.filename.endsWith('/') &&
        !header.filename.endsWith(r'\') &&
        (header.versionMadeBy >> 8 != 3 || fileType == 0 || fileType == 0x8000);
    if (!isRegularFile ||
        header.filename.contains('/') ||
        header.filename.contains(r'\') ||
        !names.add(header.filename)) {
      _throwInvalidArchive('The archive entry structure is invalid.');
    }
  }
  if (headers.length != requiredNames.length ||
      names.length != requiredNames.length ||
      !names.containsAll(requiredNames)) {
    _throwInvalidArchive('The archive entries are incomplete or unexpected.');
  }
}

Never _throwInvalidArchive(String message) {
  _throwBackupFailure(
    LibraryBackupFailureKind.invalidArchive,
    FormatException(message),
    StackTrace.current,
  );
}

Never _throwBackupTooLarge() {
  _throwBackupFailure(
    LibraryBackupFailureKind.backupTooLarge,
    const FormatException('The backup exceeds the supported size.'),
    StackTrace.current,
  );
}

Never _throwBackupFailure(
  LibraryBackupFailureKind kind,
  Object cause,
  StackTrace stackTrace,
) {
  throw LibraryBackupException(kind, cause: cause, stackTrace: stackTrace);
}

/// Builds the local-calendar filename offered to the native save picker.
String buildLibraryBackupFilename(DateTime localCreatedAt) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  final date =
      '${localCreatedAt.year.toString().padLeft(4, '0')}'
      '${twoDigits(localCreatedAt.month)}'
      '${twoDigits(localCreatedAt.day)}';
  final time =
      '${twoDigits(localCreatedAt.hour)}'
      '${twoDigits(localCreatedAt.minute)}'
      '${twoDigits(localCreatedAt.second)}';
  return 'prepbook-backup-$date-$time.prepbook';
}
