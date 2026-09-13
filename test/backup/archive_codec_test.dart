import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/persistence/persistence.dart';

void main() {
  group('BackupArchiveCodec', () {
    test('round-trips the exact version 1 envelope', () {
      final databaseBytes = Uint8List.fromList([0, 1, 2, 255]);
      final createdAtUtc = DateTime.utc(2026, 9, 13, 1, 2, 3);
      const codec = BackupArchiveCodec();

      final encoded = codec.encode(
        databaseBytes: databaseBytes,
        databaseSchemaVersion: 1,
        createdAtUtc: createdAtUtc,
      );
      final archive = ZipDecoder().decodeBytes(encoded);
      final decoded = codec.decode(encoded);

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
      expect(decoded.databaseBytes, databaseBytes);
      expect(() => decoded.databaseBytes[0] = 9, throwsUnsupportedError);
      expect(decoded.databaseSchemaVersion, 1);
      expect(decoded.createdAtUtc, createdAtUtc);
    });

    test('builds the suggested name from zero-padded local fields', () {
      final localCreatedAt = DateTime(2026, 3, 4, 5, 6, 7);

      final name = buildLibraryBackupFilename(localCreatedAt);

      expect(name, 'prepbook-backup-20260304-050607.prepbook');
    });

    group('archive structure', () {
      test('maps a malformed ZIP stream to invalid archive', () {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchEocdUint32(bytes, offset: 16, value: 0x7fffffff);

        _expectInvalidArchive(bytes);
      });

      test('maps a database decompression failure to invalid archive', () {
        final bytes = _zipEntries([
          _manifestEntry(),
          ArchiveFile.bytes('library.db', List<int>.filled(1024, 0)),
        ]);
        _overwriteLocalContent(bytes, 'library.db', value: 0xff);

        _expectInvalidArchive(bytes);
      });

      test('maps a corrupt local entry header to invalid archive', () {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchLocalUint32(bytes, 'library.db', offset: 0, value: 0);

        _expectInvalidArchive(bytes);
      });

      test('rejects every missing required entry', () {
        _expectInvalidArchive(_zipEntries([_databaseEntry()]));
        _expectInvalidArchive(_zipEntries([_manifestEntry()]));
      });

      test('rejects duplicate entry names', () {
        _expectInvalidArchive(
          _zipEntries([_manifestEntry(), _manifestEntry(), _databaseEntry()]),
        );
      });

      test('rejects directories, symbolic links, and nested paths', () {
        _expectInvalidArchive(
          _zipEntries([
            ArchiveFile.directory('manifest.json'),
            _databaseEntry(),
          ]),
        );
        _expectInvalidArchive(_zipWithManifestSymlink());
        _expectInvalidArchive(
          _zipEntries([
            _manifestEntry(name: 'folder/manifest.json'),
            _databaseEntry(),
          ]),
        );
      });

      test('rejects additional entries', () {
        _expectInvalidArchive(
          _zipEntries([
            _manifestEntry(),
            _databaseEntry(),
            ArchiveFile.string('notes.txt', 'not allowed'),
          ]),
        );
      });
    });

    group('manifest', () {
      test('rejects every missing required field', () {
        for (final field in _validManifestMap.keys) {
          final manifest = Map<String, Object?>.of(_validManifestMap)
            ..remove(field);

          _expectFailure(
            _archiveWithManifest(manifest),
            LibraryBackupFailureKind.invalidArchive,
          );
        }
      });

      test('rejects malformed JSON and a non-object root', () {
        _expectFailure(
          _archiveWithManifestText('{'),
          LibraryBackupFailureKind.invalidArchive,
        );
        _expectFailure(
          _archiveWithManifestText('[]'),
          LibraryBackupFailureKind.invalidArchive,
        );
      });

      test('rejects required fields with the wrong type', () {
        final wrongValues = <String, Object?>{
          'format': 1,
          'formatVersion': '1',
          'databaseSchemaVersion': '1',
          'createdAtUtc': 1,
          'databaseEntry': 1,
        };
        for (final entry in wrongValues.entries) {
          final manifest = Map<String, Object?>.of(_validManifestMap)
            ..[entry.key] = entry.value;

          _expectFailure(
            _archiveWithManifest(manifest),
            LibraryBackupFailureKind.invalidArchive,
          );
        }
      });

      test('rejects another format and unsupported format version', () {
        _expectFailure(
          _archiveWithManifest({..._validManifestMap, 'format': 'another_app'}),
          LibraryBackupFailureKind.unsupportedFormat,
        );
        _expectFailure(
          _archiveWithManifest({..._validManifestMap, 'formatVersion': 2}),
          LibraryBackupFailureKind.unsupportedFormat,
        );
      });

      test('rejects zero and future database schema versions', () {
        _expectFailure(
          _archiveWithManifest({
            ..._validManifestMap,
            'databaseSchemaVersion': 0,
          }),
          LibraryBackupFailureKind.invalidArchive,
        );
        _expectFailure(
          _archiveWithManifest({
            ..._validManifestMap,
            'databaseSchemaVersion': currentSchemaVersion + 1,
          }),
          LibraryBackupFailureKind.incompatibleSchema,
        );
      });

      test('rejects a different database entry name', () {
        _expectFailure(
          _archiveWithManifest({
            ..._validManifestMap,
            'databaseEntry': 'other.db',
          }),
          LibraryBackupFailureKind.invalidArchive,
        );
      });

      test('requires a valid timestamp written with the UTC designator', () {
        for (final value in [
          'not-a-timestamp',
          '2026-09-13T01:02:03.000',
          '2026-09-13T01:02:03.000+00:00',
          '2026-02-31T00:00:00.000Z',
        ]) {
          _expectFailure(
            _archiveWithManifest({..._validManifestMap, 'createdAtUtc': value}),
            LibraryBackupFailureKind.invalidArchive,
          );
        }
      });

      test('ignores unknown fields for a compatible writer', () {
        final decoded = const BackupArchiveCodec().decode(
          _archiveWithManifest({..._validManifestMap, 'writerVersion': '2.0'}),
        );

        expect(decoded.databaseBytes, [1, 2, 3]);
      });
    });

    group('integrity and size limits', () {
      test('checks the encoded archive limit before ZIP decoding', () {
        const codec = BackupArchiveCodec(maxArchiveBytes: 3);

        _expectFailure(
          Uint8List.fromList([0, 1, 2, 3]),
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('rejects oversized database bytes before encoding', () {
        const codec = BackupArchiveCodec(maxDatabaseBytes: 2);

        expect(
          () => codec.encode(
            databaseBytes: Uint8List.fromList([1, 2, 3]),
            databaseSchemaVersion: 1,
            createdAtUtc: DateTime.utc(2026, 9, 13),
          ),
          throwsA(_failureKind(LibraryBackupFailureKind.backupTooLarge)),
        );
      });

      test('rejects an encoded archive that exceeds its limit', () {
        const codec = BackupArchiveCodec(maxArchiveBytes: 64);

        expect(
          () => codec.encode(
            databaseBytes: Uint8List.fromList([1]),
            databaseSchemaVersion: 1,
            createdAtUtc: DateTime.utc(2026, 9, 13),
          ),
          throwsA(_failureKind(LibraryBackupFailureKind.backupTooLarge)),
        );
      });

      test('checks declared database size before reading entry content', () {
        final oversized = ArchiveFile.noData('library.db')
          ..size = 3
          ..compression = CompressionType.none;
        final bytes = _zipEntries([_manifestEntry(), oversized]);
        _patchCentralUint32(bytes, 'library.db', offset: 16, value: 1);
        const codec = BackupArchiveCodec(maxDatabaseBytes: 2);

        _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('bounds decompressed database bytes when the header lies', () {
        final bytes = _zipEntries([
          _manifestEntry(),
          ArchiveFile.bytes('library.db', List<int>.filled(32, 0)),
        ]);
        _patchCentralUint32(bytes, 'library.db', offset: 24, value: 1);
        const codec = BackupArchiveCodec(maxDatabaseBytes: 8);

        _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      for (final compression in [CompressionType.none, CompressionType.bzip2]) {
        test('decodes a ${compression.name} database entry within bounds', () {
          final database = ArchiveFile.bytes('library.db', [1, 2, 3])
            ..compression = compression;
          final bytes = _zipEntries([_manifestEntry(), database]);

          final decoded = const BackupArchiveCodec().decode(bytes);

          expect(decoded.databaseBytes, [1, 2, 3]);
        });
      }

      test('checks declared database size before decoding a symlink', () {
        final symlink = ArchiveFile.bytes(
          'library.db',
          utf8.encode('target.db'),
        )..mode = 0xa1ff;
        final bytes = _zipEntries([_manifestEntry(), symlink]);
        _markCentralEntryAsUnix(bytes, 'library.db');
        const codec = BackupArchiveCodec(maxDatabaseBytes: 2);

        _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('checks declared manifest size against its dedicated limit', () {
        final bytes = _zipEntries([
          ArchiveFile.string(
            'manifest.json',
            '${' ' * 1024}${jsonEncode(_validManifestMap)}',
          ),
          _databaseEntry(),
        ]);
        const codec = BackupArchiveCodec(maxManifestBytes: 128);

        _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('bounds manifest expansion when its declared size lies', () {
        final bytes = _zipEntries([
          ArchiveFile.string(
            'manifest.json',
            '${' ' * 1024}${jsonEncode(_validManifestMap)}',
          ),
          _databaseEntry(),
        ]);
        _patchCentralUint32(bytes, 'manifest.json', offset: 24, value: 1);
        const codec = BackupArchiveCodec(maxManifestBytes: 128);

        _expectFailure(
          bytes,
          LibraryBackupFailureKind.backupTooLarge,
          codec: codec,
        );
      });

      test('rejects an entry whose content does not match its CRC', () {
        final bytes = _archiveWithManifest(_validManifestMap);
        _patchCentralUint32(bytes, 'library.db', offset: 16, value: 1);
        _patchLocalUint32(bytes, 'library.db', offset: 14, value: 1);

        _expectFailure(bytes, LibraryBackupFailureKind.invalidArchive);
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

ArchiveFile _manifestEntry({String name = 'manifest.json'}) =>
    ArchiveFile.string(name, jsonEncode(_validManifestMap));

ArchiveFile _databaseEntry() => ArchiveFile.bytes('library.db', [1, 2, 3]);

Uint8List _zipEntries(List<ArchiveFile> entries) {
  final output = OutputMemoryStream();
  final encoder = ZipEncoder()
    ..startEncode(output, modified: DateTime.utc(2026, 9, 13));
  for (final entry in entries) {
    encoder.add(entry, autoClose: false);
  }
  encoder.endEncode();
  return output.getBytes();
}

Uint8List _zipWithManifestSymlink() {
  final symlink = ArchiveFile.bytes('manifest.json', utf8.encode('library.db'))
    ..mode = 0xa1ff;
  final bytes = _zipEntries([symlink, _databaseEntry()]);
  _markCentralEntryAsUnix(bytes, 'manifest.json');
  return bytes;
}

void _markCentralEntryAsUnix(Uint8List bytes, String entryName) {
  for (var index = 0; index <= bytes.length - 6; index++) {
    if (bytes[index] == 0x50 &&
        bytes[index + 1] == 0x4b &&
        bytes[index + 2] == 0x01 &&
        bytes[index + 3] == 0x02) {
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

Uint8List _archiveWithManifest(Map<String, Object?> manifest) =>
    _archiveWithManifestText(jsonEncode(manifest));

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
    if (bytes[index] != 0x50 ||
        bytes[index + 1] != 0x4b ||
        bytes[index + 2] != 0x01 ||
        bytes[index + 3] != 0x02) {
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
    if (bytes[index] != 0x50 ||
        bytes[index + 1] != 0x4b ||
        bytes[index + 2] != 0x03 ||
        bytes[index + 3] != 0x04) {
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
    if (bytes[index] != 0x50 ||
        bytes[index + 1] != 0x4b ||
        bytes[index + 2] != 0x05 ||
        bytes[index + 3] != 0x06) {
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
    if (bytes[index] != 0x50 ||
        bytes[index + 1] != 0x4b ||
        bytes[index + 2] != 0x03 ||
        bytes[index + 3] != 0x04) {
      continue;
    }
    final compressedSize =
        bytes[index + 18] |
        bytes[index + 19] << 8 |
        bytes[index + 20] << 16 |
        bytes[index + 21] << 24;
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

void _expectInvalidArchive(Uint8List bytes) {
  _expectFailure(bytes, LibraryBackupFailureKind.invalidArchive);
}

void _expectFailure(
  Uint8List bytes,
  LibraryBackupFailureKind kind, {
  BackupArchiveCodec codec = const BackupArchiveCodec(),
}) {
  expect(() => codec.decode(bytes), throwsA(_failureKind(kind)));
}

Matcher _failureKind(LibraryBackupFailureKind kind) =>
    isA<LibraryBackupException>().having((error) => error.kind, 'kind', kind);
