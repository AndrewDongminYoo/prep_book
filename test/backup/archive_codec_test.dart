import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/persistence/persistence.dart';

void main() {
  setUp(() async {
    _directory = await Directory.systemTemp.createTemp('prep-book-codec-');
  });

  tearDown(() => _directory.delete(recursive: true));

  group('BackupArchiveCodec', () {
    test('round-trips the exact version 1 envelope', () async {
      final databaseBytes = Uint8List.fromList([0, 1, 2, 255]);
      final createdAtUtc = DateTime.utc(2026, 9, 13, 1, 2, 3);

      final encoded = await _encode(
        databaseBytes,
        createdAtUtc: createdAtUtc,
      );
      final archive = ZipDecoder().decodeBytes(encoded);
      final result = await _decode(encoded);

      expect(archive.map((entry) => entry.name), [
        'manifest.json',
        'library.db',
      ]);
      expect(archive.every((entry) => entry.isFile), isTrue);
      expect(
        jsonDecode(utf8.decode(archive.first.readBytes()!)),
        <String, Object>{
          'format': 'prep_book_backup',
          'formatVersion': 1,
          'databaseSchemaVersion': 1,
          'createdAtUtc': '2026-09-13T01:02:03.000Z',
          'databaseEntry': 'library.db',
        },
      );
      expect(archive.last.readBytes(), databaseBytes);
      expect(result.databaseBytes, databaseBytes);
      expect(result.decoded.databaseSchemaVersion, 1);
      expect(result.decoded.createdAtUtc, createdAtUtc);
    });

    test('round-trips a database spanning many read and deflate chunks', () async {
      // Past several 64 KiB file-read chunks, half incompressible and half
      // runs, so both the CRC and the deflate stream cross chunk boundaries.
      final random = Random(31);
      final databaseBytes = Uint8List.fromList([
        for (var index = 0; index < 400 * 1024; index++) random.nextInt(256),
        ...List<int>.filled(400 * 1024, 7),
      ]);

      final encoded = await _encode(databaseBytes);
      final result = await _decode(encoded);

      expect(result.databaseBytes, databaseBytes);
      expect(ZipDecoder().decodeBytes(encoded).last.readBytes(), databaseBytes);
      expect(encoded.length, lessThan(databaseBytes.length));
    });

    test('decodes an archive another ZIP writer produced', () async {
      final result = await _decode(_archiveWithManifest(_validManifestMap));

      expect(result.databaseBytes, [1, 2, 3]);
      expect(result.decoded.databaseSchemaVersion, 1);
    });

    test('a failed database write propagates unchanged, not as a damaged archive', () async {
      const codec = BackupArchiveCodec(openDatabaseSink: _fullDiskSink);

      await expectLater(
        _decode(_archiveWithManifest(_validManifestMap), codec: codec),
        throwsA(same(_diskFull)),
      );
    });

    test('builds the suggested name from zero-padded local fields', () {
      final localCreatedAt = DateTime(2026, 3, 4, 5, 6, 7);

      final name = buildLibraryBackupFilename(localCreatedAt);

      expect(name, 'prepbook-backup-20260304-050607.prepbook');
    });

    group('archive structure', () {
      test('maps a malformed ZIP stream to invalid archive', () async {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchEocdUint32(bytes, offset: 16, value: 0x7fffffff);

        await _expectInvalidArchive(bytes);
      });

      test('maps a database decompression failure to invalid archive', () async {
        final bytes = _zipEntries([
          _manifestEntry(),
          ArchiveFile.bytes('library.db', List<int>.filled(1024, 0)),
        ]);
        _overwriteLocalContent(bytes, 'library.db', value: 0xff);

        await _expectInvalidArchive(bytes);
      });

      test('maps a corrupt local entry header to invalid archive', () async {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchLocalUint32(bytes, 'library.db', offset: 0, value: 0);

        await _expectInvalidArchive(bytes);
      });

      test('rejects a local header that names another entry', () async {
        final bytes = _archiveWithManifest(_validManifestMap);
        _renameLocalEntry(bytes, 'library.db', 'library.ab');

        await _expectInvalidArchive(bytes);
      });

      test('rejects a local header offset outside the archive', () async {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchCentralUint32(bytes, 'library.db', offset: 42, value: bytes.length);

        await _expectInvalidArchive(bytes);
      });

      test('rejects entry content that runs past the archive', () async {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchCentralUint32(bytes, 'library.db', offset: 20, value: bytes.length);

        await _expectInvalidArchive(bytes);
      });

      test('rejects an encrypted entry', () async {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchCentralUint16(bytes, 'library.db', offset: 8, value: 0x1);

        await _expectInvalidArchive(bytes);
      });

      test('rejects an unsupported compression method', () async {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchCentralUint16(bytes, 'library.db', offset: 10, value: 99);

        await _expectInvalidArchive(bytes);
      });

      test('rejects every missing required entry', () async {
        await _expectInvalidArchive(_zipEntries([_databaseEntry()]));
        await _expectInvalidArchive(_zipEntries([_manifestEntry()]));
      });

      test('rejects duplicate entry names', () async {
        await _expectInvalidArchive(
          _zipEntries([_manifestEntry(), _manifestEntry(), _databaseEntry()]),
        );
      });

      test('rejects directories, symbolic links, and nested paths', () async {
        await _expectInvalidArchive(
          _zipEntries([
            ArchiveFile.directory('manifest.json'),
            _databaseEntry(),
          ]),
        );
        await _expectInvalidArchive(_zipWithManifestSymlink());
        await _expectInvalidArchive(
          _zipEntries([
            _manifestEntry(name: 'folder/manifest.json'),
            _databaseEntry(),
          ]),
        );
      });

      test('rejects additional entries', () async {
        await _expectInvalidArchive(
          _zipEntries([
            _manifestEntry(),
            _databaseEntry(),
            ArchiveFile.string('notes.txt', 'not allowed'),
          ]),
        );
      });
    });

    group('manifest', () {
      test('rejects every missing required field', () async {
        for (final field in _validManifestMap.keys) {
          final manifest = Map<String, Object?>.of(_validManifestMap)..remove(field);

          await _expectFailure(
            _archiveWithManifest(manifest),
            LibraryBackupFailureKind.invalidArchive,
          );
        }
      });

      test('rejects malformed JSON and a non-object root', () async {
        await _expectFailure(
          _archiveWithManifestText('{'),
          LibraryBackupFailureKind.invalidArchive,
        );
        await _expectFailure(
          _archiveWithManifestText('[]'),
          LibraryBackupFailureKind.invalidArchive,
        );
      });

      test('rejects required fields with the wrong type', () async {
        final wrongValues = <String, Object?>{
          'format': 1,
          'formatVersion': '1',
          'databaseSchemaVersion': '1',
          'createdAtUtc': 1,
          'databaseEntry': 1,
        };
        for (final entry in wrongValues.entries) {
          final manifest = Map<String, Object?>.of(_validManifestMap)..[entry.key] = entry.value;

          await _expectFailure(
            _archiveWithManifest(manifest),
            LibraryBackupFailureKind.invalidArchive,
          );
        }
      });

      test('rejects another format and unsupported format version', () async {
        await _expectFailure(
          _archiveWithManifest({..._validManifestMap, 'format': 'another_app'}),
          LibraryBackupFailureKind.unsupportedFormat,
        );
        await _expectFailure(
          _archiveWithManifest({..._validManifestMap, 'formatVersion': 2}),
          LibraryBackupFailureKind.unsupportedFormat,
        );
      });

      test('rejects zero and future database schema versions', () async {
        await _expectFailure(
          _archiveWithManifest({
            ..._validManifestMap,
            'databaseSchemaVersion': 0,
          }),
          LibraryBackupFailureKind.invalidArchive,
        );
        await _expectFailure(
          _archiveWithManifest({
            ..._validManifestMap,
            'databaseSchemaVersion': currentSchemaVersion + 1,
          }),
          LibraryBackupFailureKind.incompatibleSchema,
        );
      });

      test('rejects a different database entry name', () async {
        await _expectFailure(
          _archiveWithManifest({
            ..._validManifestMap,
            'databaseEntry': 'other.db',
          }),
          LibraryBackupFailureKind.invalidArchive,
        );
      });

      test('requires a valid timestamp written with the UTC designator', () async {
        for (final value in [
          'not-a-timestamp',
          '2026-09-13T01:02:03.000',
          '2026-09-13T01:02:03.000+00:00',
          '2026-02-31T00:00:00.000Z',
        ]) {
          await _expectFailure(
            _archiveWithManifest({..._validManifestMap, 'createdAtUtc': value}),
            LibraryBackupFailureKind.invalidArchive,
          );
        }
      });

      test('ignores unknown fields for a compatible writer', () async {
        final result = await _decode(
          _archiveWithManifest({..._validManifestMap, 'writerVersion': '2.0'}),
        );

        expect(result.databaseBytes, [1, 2, 3]);
      });
    });

    group('integrity and size limits', () {
      test('checks the encoded archive limit before ZIP decoding', () async {
        const codec = BackupArchiveCodec(maxArchiveBytes: 3);

        await _expectFailure(
          Uint8List.fromList([0, 1, 2, 3]),
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('rejects oversized database bytes before encoding', () async {
        const codec = BackupArchiveCodec(maxDatabaseBytes: 2);

        await expectLater(
          _encode([1, 2, 3], codec: codec),
          throwsA(_failureKind(LibraryBackupFailureKind.backupTooLarge)),
        );
      });

      test('bounds each entry while it is encoded', () async {
        // The manifest has no length check ahead of the writer, so this is
        // the streaming bound itself refusing the entry.
        const codec = BackupArchiveCodec(maxManifestBytes: 16);

        await expectLater(
          _encode([1], codec: codec),
          throwsA(_failureKind(LibraryBackupFailureKind.backupTooLarge)),
        );
      });

      test('rejects an encoded archive that exceeds its limit', () async {
        const codec = BackupArchiveCodec(maxArchiveBytes: 64);

        await expectLater(
          _encode([1], codec: codec),
          throwsA(_failureKind(LibraryBackupFailureKind.backupTooLarge)),
        );
      });

      test('checks declared database size before reading entry content', () async {
        final oversized = ArchiveFile.noData('library.db')
          ..size = 3
          ..compression = CompressionType.none;
        final bytes = _zipEntries([_manifestEntry(), oversized]);
        _patchCentralUint32(bytes, 'library.db', offset: 16, value: 1);
        const codec = BackupArchiveCodec(maxDatabaseBytes: 2);

        await _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('bounds decompressed database bytes when the header lies', () async {
        final bytes = _zipEntries([
          _manifestEntry(),
          ArchiveFile.bytes('library.db', List<int>.filled(32, 0)),
        ]);
        _patchCentralUint32(bytes, 'library.db', offset: 24, value: 1);
        const codec = BackupArchiveCodec(maxDatabaseBytes: 8);

        await _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      for (final compression in [CompressionType.none, CompressionType.bzip2]) {
        test('decodes a ${compression.name} database entry within bounds', () async {
          final database = ArchiveFile.bytes('library.db', [1, 2, 3])..compression = compression;
          final bytes = _zipEntries([_manifestEntry(), database]);

          final result = await _decode(bytes);

          expect(result.databaseBytes, [1, 2, 3]);
        });
      }

      test('bounds a bzip2 entry whose declared size lies', () async {
        final database = ArchiveFile.bytes('library.db', List<int>.filled(32, 0))..compression = CompressionType.bzip2;
        final bytes = _zipEntries([_manifestEntry(), database]);
        _patchCentralUint32(bytes, 'library.db', offset: 24, value: 1);
        const codec = BackupArchiveCodec(maxDatabaseBytes: 8);

        await _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('checks declared database size before decoding a symlink', () async {
        final symlink = ArchiveFile.bytes(
          'library.db',
          utf8.encode('target.db'),
        )..mode = 0xa1ff;
        final bytes = _zipEntries([_manifestEntry(), symlink]);
        _markCentralEntryAsUnix(bytes, 'library.db');
        const codec = BackupArchiveCodec(maxDatabaseBytes: 2);

        await _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('checks declared manifest size against its dedicated limit', () async {
        final bytes = _zipEntries([
          ArchiveFile.string(
            'manifest.json',
            '${' ' * 1024}${jsonEncode(_validManifestMap)}',
          ),
          _databaseEntry(),
        ]);
        const codec = BackupArchiveCodec(maxManifestBytes: 128);

        await _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('bounds manifest expansion when its declared size lies', () async {
        final bytes = _zipEntries([
          ArchiveFile.string(
            'manifest.json',
            '${' ' * 1024}${jsonEncode(_validManifestMap)}',
          ),
          _databaseEntry(),
        ]);
        _patchCentralUint32(bytes, 'manifest.json', offset: 24, value: 1);
        const codec = BackupArchiveCodec(maxManifestBytes: 128);

        await _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('rejects an entry whose content does not match its CRC', () async {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchCentralUint32(bytes, 'library.db', offset: 16, value: 1);
        _patchLocalUint32(bytes, 'library.db', offset: 14, value: 1);

        await _expectFailure(bytes, LibraryBackupFailureKind.invalidArchive);
      });

      test('rejects an entry shorter than its declared size', () async {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchCentralUint32(bytes, 'library.db', offset: 24, value: 4);

        await _expectFailure(bytes, LibraryBackupFailureKind.invalidArchive);
      });
    });
  });
}

const _validManifestMap = <String, Object?>{
  'format': 'prep_book_backup',
  'formatVersion': 1,
  'databaseSchemaVersion': 1,
  'createdAtUtc': '2026-09-13T01:02:03.000Z',
  'databaseEntry': 'library.db',
};

ArchiveFile _manifestEntry({String name = 'manifest.json'}) => ArchiveFile.string(name, jsonEncode(_validManifestMap));

ArchiveFile _databaseEntry() => ArchiveFile.bytes('library.db', [1, 2, 3]);

Uint8List _zipEntries(List<ArchiveFile> entries) {
  final output = OutputMemoryStream();
  final encoder = ZipEncoder()..startEncode(output, modified: DateTime.utc(2026, 9, 13));
  for (final entry in entries) {
    encoder.add(entry, autoClose: false);
  }
  encoder.endEncode();
  return output.getBytes();
}

Uint8List _zipWithManifestSymlink() {
  final symlink = ArchiveFile.bytes('manifest.json', utf8.encode('library.db'))..mode = 0xa1ff;
  final bytes = _zipEntries([symlink, _databaseEntry()]);
  _markCentralEntryAsUnix(bytes, 'manifest.json');
  return bytes;
}

void _markCentralEntryAsUnix(Uint8List bytes, String entryName) {
  for (var index = 0; index <= bytes.length - 6; index++) {
    if (bytes[index] == 0x50 && bytes[index + 1] == 0x4b && bytes[index + 2] == 0x01 && bytes[index + 3] == 0x02) {
      final nameLength = bytes[index + 28] | bytes[index + 29] << 8;
      final name = utf8.decode(
        bytes.sublist(index + 46, index + 46 + nameLength),
      );
      if (name != entryName) continue;
      bytes[index + 5] = 3;
      return;
    }
  }
  fail('Central directory entry not found: $entryName');
}

Uint8List _archiveWithManifest(Map<String, Object?> manifest) => _archiveWithManifestText(jsonEncode(manifest));

Uint8List _archiveWithManifestText(String manifest) => _zipEntries([
  ArchiveFile.string('manifest.json', manifest),
  _databaseEntry(),
]);

void _patchCentralUint32(
  Uint8List bytes,
  String entryName, {
  required int offset,
  required int value,
}) {
  for (var index = 0; index <= bytes.length - 46; index++) {
    if (bytes[index] != 0x50 || bytes[index + 1] != 0x4b || bytes[index + 2] != 0x01 || bytes[index + 3] != 0x02) {
      continue;
    }
    final nameLength = bytes[index + 28] | bytes[index + 29] << 8;
    final name = utf8.decode(
      bytes.sublist(index + 46, index + 46 + nameLength),
    );
    if (name != entryName) continue;
    for (var byte = 0; byte < 4; byte++) {
      bytes[index + offset + byte] = value >> (byte * 8) & 0xff;
    }
    return;
  }
  fail('Central directory entry not found: $entryName');
}

void _patchLocalUint32(
  Uint8List bytes,
  String entryName, {
  required int offset,
  required int value,
}) {
  for (var index = 0; index <= bytes.length - 30; index++) {
    if (bytes[index] != 0x50 || bytes[index + 1] != 0x4b || bytes[index + 2] != 0x03 || bytes[index + 3] != 0x04) {
      continue;
    }
    final nameLength = bytes[index + 26] | bytes[index + 27] << 8;
    final name = utf8.decode(
      bytes.sublist(index + 30, index + 30 + nameLength),
    );
    if (name != entryName) continue;
    for (var byte = 0; byte < 4; byte++) {
      bytes[index + offset + byte] = value >> (byte * 8) & 0xff;
    }
    return;
  }
  fail('Local header entry not found: $entryName');
}

void _patchEocdUint32(
  Uint8List bytes, {
  required int offset,
  required int value,
}) {
  for (var index = bytes.length - 22; index >= 0; index--) {
    if (bytes[index] != 0x50 || bytes[index + 1] != 0x4b || bytes[index + 2] != 0x05 || bytes[index + 3] != 0x06) {
      continue;
    }
    for (var byte = 0; byte < 4; byte++) {
      bytes[index + offset + byte] = value >> (byte * 8) & 0xff;
    }
    return;
  }
  fail('End of central directory record not found.');
}

void _overwriteLocalContent(
  Uint8List bytes,
  String entryName, {
  required int value,
}) {
  for (var index = 0; index <= bytes.length - 30; index++) {
    if (bytes[index] != 0x50 || bytes[index + 1] != 0x4b || bytes[index + 2] != 0x03 || bytes[index + 3] != 0x04) {
      continue;
    }
    final compressedSize =
        bytes[index + 18] | bytes[index + 19] << 8 | bytes[index + 20] << 16 | bytes[index + 21] << 24;
    final nameLength = bytes[index + 26] | bytes[index + 27] << 8;
    final extraLength = bytes[index + 28] | bytes[index + 29] << 8;
    final name = utf8.decode(
      bytes.sublist(index + 30, index + 30 + nameLength),
    );
    if (name != entryName) continue;
    final contentStart = index + 30 + nameLength + extraLength;
    bytes.fillRange(contentStart, contentStart + compressedSize, value);
    return;
  }
  fail('Local file entry not found: $entryName');
}

Future<void> _expectInvalidArchive(Uint8List bytes) => _expectFailure(bytes, LibraryBackupFailureKind.invalidArchive);

Future<void> _expectFailure(
  Uint8List bytes,
  LibraryBackupFailureKind kind, {
  BackupArchiveCodec codec = const BackupArchiveCodec(),
}) => expectLater(_decode(bytes, codec: codec), throwsA(_failureKind(kind)));

Matcher _failureKind(LibraryBackupFailureKind kind) =>
    isA<LibraryBackupException>().having((error) => error.kind, 'kind', kind);

/// A temporary directory for one test's archive and database files.
late Directory _directory;

/// Writes [archiveBytes] to a file, decodes it, and returns the decoded
/// manifest facts with the database bytes the decoder wrote.
Future<({DecodedLibraryBackup decoded, Uint8List databaseBytes})> _decode(
  Uint8List archiveBytes, {
  BackupArchiveCodec codec = const BackupArchiveCodec(),
}) async {
  final archivePath = '${_directory.path}/input-${_sequence++}.prepbook';
  final databasePath = '$archivePath.db';
  await File(archivePath).writeAsBytes(archiveBytes, flush: true);
  final decoded = await codec.decodeFile(
    archivePath: archivePath,
    databasePath: databasePath,
  );
  return (decoded: decoded, databaseBytes: await File(databasePath).readAsBytes());
}

/// Encodes [databaseBytes] through a database file and returns the archive
/// bytes the encoder wrote.
Future<Uint8List> _encode(
  List<int> databaseBytes, {
  BackupArchiveCodec codec = const BackupArchiveCodec(),
  int databaseSchemaVersion = 1,
  DateTime? createdAtUtc,
}) async {
  final databasePath = '${_directory.path}/source-${_sequence++}.db';
  final archivePath = '$databasePath.prepbook';
  await File(databasePath).writeAsBytes(databaseBytes, flush: true);
  await codec.encodeFile(
    databasePath: databasePath,
    archivePath: archivePath,
    databaseSchemaVersion: databaseSchemaVersion,
    createdAtUtc: createdAtUtc ?? DateTime.utc(2026, 9, 13),
  );
  return await File(archivePath).readAsBytes();
}

var _sequence = 0;

void _patchCentralUint16(
  Uint8List bytes,
  String entryName, {
  required int offset,
  required int value,
}) {
  final index = _centralHeaderIndex(bytes, entryName);
  bytes[index + offset] = value & 0xff;
  bytes[index + offset + 1] = value >> 8 & 0xff;
}

int _centralHeaderIndex(Uint8List bytes, String entryName) {
  for (var index = 0; index <= bytes.length - 46; index++) {
    if (bytes[index] != 0x50 || bytes[index + 1] != 0x4b || bytes[index + 2] != 0x01 || bytes[index + 3] != 0x02) {
      continue;
    }
    final nameLength = bytes[index + 28] | bytes[index + 29] << 8;
    final name = utf8.decode(bytes.sublist(index + 46, index + 46 + nameLength));
    if (name == entryName) return index;
  }
  fail('Central directory entry not found: $entryName');
}

void _renameLocalEntry(Uint8List bytes, String entryName, String replacement) {
  expect(replacement.length, entryName.length);
  for (var index = 0; index <= bytes.length - 30; index++) {
    if (bytes[index] != 0x50 || bytes[index + 1] != 0x4b || bytes[index + 2] != 0x03 || bytes[index + 3] != 0x04) {
      continue;
    }
    final nameLength = bytes[index + 26] | bytes[index + 27] << 8;
    final name = utf8.decode(bytes.sublist(index + 30, index + 30 + nameLength));
    if (name != entryName) continue;
    bytes.setRange(index + 30, index + 30 + nameLength, utf8.encode(replacement));
    return;
  }
  fail('Local header entry not found: $entryName');
}

const _diskFull = FileSystemException(
  'No space left on device',
  'library.db',
  OSError('No space left on device', 28),
);

/// Opens a real database file whose every write fails the way a full disk
/// does.
Future<RandomAccessFile> _fullDiskSink(String path) async => _FullDiskFile(await File(path).open(mode: FileMode.write));

final class _FullDiskFile implements RandomAccessFile {
  new(this._delegate);

  final RandomAccessFile _delegate;

  @override
  Future<RandomAccessFile> writeFrom(List<int> buffer, [int start = 0, int? end]) => Future.error(_diskFull);

  @override
  Future<void> close() => _delegate.close();

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
