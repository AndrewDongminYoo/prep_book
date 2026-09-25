import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' hide ZLibDecoder, ZLibEncoder;
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/bounded_output.dart';
import 'package:prep_book/persistence/database.dart';

const _manifestEntryName = 'manifest.json';
const _databaseEntryName = 'library.db';
const _backupFormat = 'prep_book_backup';
const _backupFormatVersion = 1;

/// The manifest facts of one decoded portable library backup.
///
/// The database itself is not here: [BackupArchiveCodec.decodeFile] writes
/// it to the path its caller names, so no full-size copy is held in memory.
final class DecodedLibraryBackup {
  /// Creates the decoded manifest facts.
  const new({required this.databaseSchemaVersion, required this.createdAtUtc});

  /// The schema version declared by the manifest.
  final int databaseSchemaVersion;

  /// The instant at which the backup was created.
  final DateTime createdAtUtc;
}

/// Opens the file [BackupArchiveCodec.decodeFile] writes a database entry
/// into.
typedef OpenDatabaseSink = Future<RandomAccessFile> Function(String path);

/// Encodes and decodes version 1 PrepBook backup archives.
///
/// Both directions work file to file in chunks. The archive and its database
/// entry can each be as large as the backup limit, and an in-memory codec
/// held the whole database, its compressed form, and the growing output
/// buffers at once — several full-size copies per operation.
final class BackupArchiveCodec {
  /// Creates the codec.
  ///
  /// `openDatabaseSink` opens the decoded database for writing; a test
  /// replaces it to fail a write the way a full disk does, which no
  /// portable file can be made to do.
  const new({
    int maxArchiveBytes = maxLibraryBackupBytes,
    int maxDatabaseBytes = maxLibraryBackupBytes,
    int maxManifestBytes = 64 * 1024,
    this._openDatabaseSink = _openDatabaseFile,
  }) : assert(maxArchiveBytes > 0, 'maxArchiveBytes must be positive.'),
       assert(maxDatabaseBytes > 0, 'maxDatabaseBytes must be positive.'),
       assert(maxManifestBytes > 0, 'maxManifestBytes must be positive.'),
       _maxArchiveBytes = maxArchiveBytes,
       _maxDatabaseBytes = maxDatabaseBytes,
       _maxManifestBytes = maxManifestBytes;

  final int _maxArchiveBytes;
  final int _maxDatabaseBytes;
  final int _maxManifestBytes;
  final OpenDatabaseSink _openDatabaseSink;

  /// Encodes one manifest and the SQLite database at [databasePath] into a
  /// ZIP archive written to [archivePath].
  ///
  /// The database is read and deflated in chunks, never held whole. Throws
  /// `backupTooLarge` when the database or the finished archive exceeds its
  /// limit; a partly written [archivePath] is left for the caller to remove.
  Future<void> encodeFile({
    required String databasePath,
    required String archivePath,
    required int databaseSchemaVersion,
    required DateTime createdAtUtc,
  }) async {
    if (await File(databasePath).length() > _maxDatabaseBytes) {
      _throwBackupTooLarge();
    }
    final manifest = <String, Object>{
      'format': _backupFormat,
      'formatVersion': _backupFormatVersion,
      'databaseSchemaVersion': databaseSchemaVersion,
      'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      'databaseEntry': _databaseEntryName,
    };
    final output = await File(archivePath).open(mode: FileMode.write);
    try {
      final writer = _ZipWriter(output, modified: createdAtUtc.toUtc());
      await writer.add(
        _manifestEntryName,
        Stream.value(utf8.encode(jsonEncode(manifest))),
        maxBytes: _maxManifestBytes,
      );
      await writer.add(
        _databaseEntryName,
        File(databasePath).openRead(),
        maxBytes: _maxDatabaseBytes,
      );
      await writer.finish();
      await output.flush();
    } on ArchiveEntryTooLarge {
      _throwBackupTooLarge();
    } finally {
      await output.close();
    }
    if (await File(archivePath).length() > _maxArchiveBytes) {
      _throwBackupTooLarge();
    }
  }

  /// Decodes the version 1 backup archive at [archivePath], writing its
  /// database entry to [databasePath].
  ///
  /// Only the ZIP directory, the local entry headers, and the manifest are
  /// read into memory; the database entry is inflated in chunks straight
  /// into [databasePath]. Every check the in-memory decoder made still runs,
  /// in the same order: the archive limit, each declared entry size, the
  /// entry structure, and then each entry's actual size and CRC, bounded
  /// while it is written. A partly written [databasePath] is left for the
  /// caller to remove.
  ///
  /// Only a fault in the archive's content is reported as an invalid
  /// archive. A failure to open, write, or flush [databasePath], such as a
  /// full disk, propagates as it was thrown, because the backup itself is
  /// sound and the caller reports it as a failed restore.
  Future<DecodedLibraryBackup> decodeFile({
    required String archivePath,
    required String databasePath,
  }) async {
    final archiveLength = await File(archivePath).length();
    if (archiveLength > _maxArchiveBytes) {
      _throwBackupTooLarge();
    }
    final headers = await _readHeaders(archivePath);
    for (final header in headers) {
      final maxEntryBytes = switch (header.filename) {
        _manifestEntryName => _maxManifestBytes,
        _databaseEntryName => _maxDatabaseBytes,
        _ => _maxArchiveBytes,
      };
      if (header.uncompressedSize > maxEntryBytes) {
        _throwBackupTooLarge();
      }
    }
    _validateArchiveStructure(headers);
    ZipFileHeader entryNamed(String name) => headers.singleWhere((header) => header.filename == name);

    final archive = await File(archivePath).open();
    try {
      final manifestBytes = BytesBuilder(copy: false);
      await _extractEntry(
        archive,
        archivePath: archivePath,
        archiveLength: archiveLength,
        header: entryNamed(_manifestEntryName),
        maxBytes: _maxManifestBytes,
        write: (chunk) async => manifestBytes.add(chunk),
      );
      final manifest = _decodeManifest(manifestBytes.takeBytes());

      final database = await _openDatabaseSink(databasePath);
      try {
        await _extractEntry(
          archive,
          archivePath: archivePath,
          archiveLength: archiveLength,
          header: entryNamed(_databaseEntryName),
          maxBytes: _maxDatabaseBytes,
          write: database.writeFrom,
        );
        await database.flush();
      } finally {
        await database.close();
      }
      return DecodedLibraryBackup(
        databaseSchemaVersion: manifest.databaseSchemaVersion,
        createdAtUtc: manifest.createdAtUtc,
      );
    } finally {
      await archive.close();
    }
  }
}

/// The central directory of the archive at [path], read through a file
/// stream so only the directory and the local headers it points at are
/// loaded.
///
/// `archive` 4.3.0 reads a malformed directory without throwing: it returns
/// whatever headers it could parse, possibly none, and the structure,
/// local-header, size, and CRC checks that follow reject what it could not
/// read as an invalid archive. Anything a later release does throw reaches
/// the gateway, which reports it as a failed restore.
Future<List<ZipFileHeader>> _readHeaders(String path) async {
  final input = InputFileStream(path);
  try {
    return (ZipDirectory()..read(input)).fileHeaders;
  } finally {
    await input.close();
  }
}

const _localHeaderSignature = 0x04034b50;
const _localHeaderLength = 30;
const _compressionStored = 0;
const _compressionDeflate = 8;
const _compressionBzip2 = 12;

/// Streams the entry [header] describes out of [archive] into [write],
/// failing when it inflates past [maxBytes] or when its size or CRC differs
/// from what the central directory declares.
Future<void> _extractEntry(
  RandomAccessFile archive, {
  required String archivePath,
  required int archiveLength,
  required ZipFileHeader header,
  required int maxBytes,
  required Future<void> Function(List<int> chunk) write,
}) async {
  try {
    final dataStart = await _entryDataStart(archive, archiveLength, header);
    final dataEnd = dataStart + header.compressedSize;
    if (dataEnd > archiveLength || (header.generalPurposeBitFlag & 0x1) != 0) {
      throw const FormatException('The archive entry cannot be read.');
    }
    final content = switch (header.compressionMethod) {
      _compressionStored => File(archivePath).openRead(dataStart, dataEnd),
      _compressionDeflate => File(
        archivePath,
      ).openRead(dataStart, dataEnd).transform(ZLibDecoder(raw: true)),
      _compressionBzip2 => Stream.value(
        await _decodeBzip2(archive, dataStart, header.compressedSize, maxBytes),
      ),
      _ => throw const FormatException('The archive compression is unsupported.'),
    };
    var length = 0;
    var crc = 0;
    await for (final chunk in content) {
      if (chunk.length > maxBytes - length) throw const ArchiveEntryTooLarge();
      length += chunk.length;
      crc = getCrc32(chunk, crc);
      try {
        await write(chunk);
      } on Object catch (error, stackTrace) {
        throw _EntryWriteFailure(error, stackTrace);
      }
    }
    if (length != header.uncompressedSize || crc != header.crc32) {
      throw const FormatException('The archive entry checksum or size is invalid.');
    }
  } on ArchiveEntryTooLarge {
    _throwBackupTooLarge();
  } on _EntryWriteFailure catch (failure) {
    Error.throwWithStackTrace(failure.error, failure.stackTrace);
  } on LibraryBackupException {
    rethrow;
  } on Object catch (error, stackTrace) {
    _throwBackupFailure(
      LibraryBackupFailureKind.invalidArchive,
      error,
      stackTrace,
    );
  }
}

Future<RandomAccessFile> _openDatabaseFile(String path) => File(path).open(mode: FileMode.write);

/// A failure of the sink an entry was written to, carried past the handler
/// that reports content faults so it reaches the caller unchanged.
final class _EntryWriteFailure implements Exception {
  const new(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

/// Where the content of [header]'s entry begins, after checking that its
/// local header is one and names the same entry the directory does.
Future<int> _entryDataStart(
  RandomAccessFile archive,
  int archiveLength,
  ZipFileHeader header,
) async {
  final offset = header.localHeaderOffset;
  if (offset < 0 || offset + _localHeaderLength > archiveLength) {
    throw const FormatException('The local entry header is out of range.');
  }
  await archive.setPosition(offset);
  final fixed = ByteData.sublistView(await archive.read(_localHeaderLength));
  if (fixed.lengthInBytes != _localHeaderLength || fixed.getUint32(0, Endian.little) != _localHeaderSignature) {
    throw const FormatException('The local entry header is invalid.');
  }
  final nameLength = fixed.getUint16(26, Endian.little);
  final extraLength = fixed.getUint16(28, Endian.little);
  final name = await archive.read(nameLength);
  if (utf8.decode(name, allowMalformed: true) != header.filename) {
    throw const FormatException('The local entry header names another entry.');
  }
  return offset + _localHeaderLength + nameLength + extraLength;
}

/// The bzip2 entry at [dataStart], decoded in memory and bounded by
/// [maxBytes].
///
/// The one path that is not streamed: `dart:io` has no bzip2 codec, and
/// this app never writes one. It is kept because the decoder has always
/// accepted a compatible writer's bzip2 entry.
Future<Uint8List> _decodeBzip2(
  RandomAccessFile archive,
  int dataStart,
  int compressedSize,
  int maxBytes,
) async {
  await archive.setPosition(dataStart);
  final compressed = await archive.read(compressedSize);
  final output = BoundedOutputMemoryStream(maxBytes);
  BZip2Decoder().decodeStream(InputMemoryStream(compressed), output);
  return output.getBytes();
}

/// Writes a two-entry ZIP archive to [_output] entry by entry, deflating
/// each one as it streams through and patching its local header with the
/// CRC and sizes once they are known.
final class _ZipWriter {
  new(this._output, {required DateTime modified})
    : _time = modified.hour << 11 | modified.minute << 5 | modified.second ~/ 2,
      _date = (modified.year < 1980 ? 0 : modified.year - 1980) << 9 | modified.month << 5 | modified.day;

  final RandomAccessFile _output;
  final int _time;
  final int _date;
  final _entries = <_ZipEntry>[];

  Future<void> add(
    String name,
    Stream<List<int>> content, {
    required int maxBytes,
  }) async {
    final nameBytes = utf8.encode(name);
    final headerOffset = await _output.position();
    await _output.writeFrom(_localHeader(nameBytes, crc: 0, compressed: 0, uncompressed: 0));
    var crc = 0;
    var uncompressed = 0;
    var compressed = 0;
    final deflated = content
        .map((chunk) {
          if (chunk.length > maxBytes - uncompressed) throw const ArchiveEntryTooLarge();
          uncompressed += chunk.length;
          crc = getCrc32(chunk, crc);
          return chunk;
        })
        .transform(ZLibEncoder(raw: true));
    await for (final chunk in deflated) {
      await _output.writeFrom(chunk);
      compressed += chunk.length;
    }
    final end = await _output.position();
    await _output.setPosition(headerOffset);
    await _output.writeFrom(
      _localHeader(nameBytes, crc: crc, compressed: compressed, uncompressed: uncompressed),
    );
    await _output.setPosition(end);
    _entries.add(
      _ZipEntry(
        nameBytes: nameBytes,
        headerOffset: headerOffset,
        crc: crc,
        compressed: compressed,
        uncompressed: uncompressed,
      ),
    );
  }

  Future<void> finish() async {
    final directoryOffset = await _output.position();
    var directoryLength = 0;
    for (final entry in _entries) {
      final record = _centralHeader(entry);
      await _output.writeFrom(record);
      directoryLength += record.length;
    }
    await _output.writeFrom(
      (ByteData(22)
            ..setUint32(0, 0x06054b50, Endian.little)
            ..setUint16(8, _entries.length, Endian.little)
            ..setUint16(10, _entries.length, Endian.little)
            ..setUint32(12, directoryLength, Endian.little)
            ..setUint32(16, directoryOffset, Endian.little))
          .buffer
          .asUint8List(),
    );
  }

  Uint8List _localHeader(
    Uint8List nameBytes, {
    required int crc,
    required int compressed,
    required int uncompressed,
  }) {
    final header = ByteData(_localHeaderLength)
      ..setUint32(0, _localHeaderSignature, Endian.little)
      ..setUint16(4, _zipVersion, Endian.little)
      ..setUint16(8, _compressionDeflate, Endian.little)
      ..setUint16(10, _time, Endian.little)
      ..setUint16(12, _date, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, compressed, Endian.little)
      ..setUint32(22, uncompressed, Endian.little)
      ..setUint16(26, nameBytes.length, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(nameBytes))
        .takeBytes();
  }

  Uint8List _centralHeader(_ZipEntry entry) {
    final header = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, _zipVersion, Endian.little)
      ..setUint16(6, _zipVersion, Endian.little)
      ..setUint16(10, _compressionDeflate, Endian.little)
      ..setUint16(12, _time, Endian.little)
      ..setUint16(14, _date, Endian.little)
      ..setUint32(16, entry.crc, Endian.little)
      ..setUint32(20, entry.compressed, Endian.little)
      ..setUint32(24, entry.uncompressed, Endian.little)
      ..setUint16(28, entry.nameBytes.length, Endian.little)
      ..setUint32(42, entry.headerOffset, Endian.little);
    return (BytesBuilder(copy: false)
          ..add(header.buffer.asUint8List())
          ..add(entry.nameBytes))
        .takeBytes();
  }
}

/// ZIP 2.0, the version that introduced deflate, written as both the
/// version made by (MS-DOS, so no Unix file mode is claimed) and the version
/// needed to extract.
const _zipVersion = 20;

final class _ZipEntry {
  const new({
    required this.nameBytes,
    required this.headerOffset,
    required this.crc,
    required this.compressed,
    required this.uncompressed,
  });

  final Uint8List nameBytes;
  final int headerOffset;
  final int crc;
  final int compressed;
  final int uncompressed;
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
