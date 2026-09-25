import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/library_backup/view/android_backup_save.dart';

/// A selected file exposed without native paths or plugin types.
final class PickedLibraryBackup {
  /// Creates a readable selected-file value.
  const new({
    required this.resolveLength,
    required this.openRead,
    this.knownLength,
  });

  /// The size reported without asynchronous I/O, when available.
  final int? knownLength;

  /// Resolves the size before [openRead] is listened to.
  final Future<int?> Function() resolveLength;

  /// Opens a fresh byte stream after the size check succeeds.
  final Stream<Uint8List> Function() openRead;
}

/// Opens the native backup picker.
typedef OpenLibraryBackupPicker = Future<PickedLibraryBackup?> Function();

/// Saves [archive] through the native picker under [suggestedName].
typedef SaveLibraryBackupPicker = Future<bool> Function({
  required String suggestedName,
  required LibraryBackupArchive archive,
});

/// Creates the empty directory a picked backup is staged in.
typedef CreateBackupStagingDirectory = Future<Directory> Function();

/// Native file operations used by the library backup feature.
abstract interface class LibraryBackupPlatform {
  /// Picks one backup and stages it outside memory, or returns `null` when
  /// cancelled. The caller owns the returned archive.
  Future<LibraryBackupArchive?> pickBackup();

  /// Saves [backup], or returns false when cancelled.
  Future<bool> saveBackup(LibraryBackupFile backup);
}

/// Adapts `file_picker` to the path-free presentation interface.
final class FilePickerLibraryBackupPlatform implements LibraryBackupPlatform {
  /// Creates the production adapter or one with injected picker functions.
  const new({
    OpenLibraryBackupPicker? openPicker,
    SaveLibraryBackupPicker? savePicker,
    CreateBackupStagingDirectory? createStagingDirectory,
    int maxBackupBytes = maxLibraryBackupBytes,
  }) : assert(maxBackupBytes > 0, 'maxBackupBytes must be positive.'),
       _openPicker = openPicker ?? _openWithFilePicker,
       _savePicker = savePicker ?? _saveWithFilePicker,
       _createStagingDirectory = createStagingDirectory ?? _createSystemTempDirectory,
       _maxBackupBytes = maxBackupBytes;

  final OpenLibraryBackupPicker _openPicker;
  final SaveLibraryBackupPicker _savePicker;
  final CreateBackupStagingDirectory _createStagingDirectory;
  final int _maxBackupBytes;

  /// Picks a backup and copies it into a staging file as it is read.
  ///
  /// The size is checked before the first byte is read, and every chunk is
  /// checked against it while copying, exactly as when the selection was
  /// collected into one buffer — only now the bytes go to disk, so a
  /// near-limit selection no longer sits in memory until the operator
  /// confirms the restore. A failure removes the staging directory.
  @override
  Future<LibraryBackupArchive?> pickBackup() async {
    try {
      final picked = await _openPicker();
      if (picked == null) return null;
      final length = picked.knownLength ?? await picked.resolveLength();
      if (length == null) {
        throw StateError('The selected backup length could not be determined.');
      }
      if (length > _maxBackupBytes) _throwTooLarge();

      final directory = await _createStagingDirectory();
      try {
        final file = File('${directory.path}/picked.prepbook');
        final output = await file.open(mode: FileMode.write);
        try {
          var offset = 0;
          await for (final chunk in picked.openRead()) {
            if (chunk.length > length - offset) {
              throw StateError('The selected backup size changed while reading.');
            }
            await output.writeFrom(chunk);
            offset += chunk.length;
          }
          if (offset != length) {
            throw StateError('The selected backup size changed while reading.');
          }
        } finally {
          await output.close();
        }
        return _StagedPickedBackup(file: file, length: length, directory: directory);
      } on Object {
        await directory.delete(recursive: true);
        rethrow;
      }
    } on LibraryBackupException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw LibraryBackupException(
        LibraryBackupFailureKind.restoreFailed,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  @override
  Future<bool> saveBackup(LibraryBackupFile backup) async {
    try {
      return await _savePicker(
        suggestedName: backup.suggestedName,
        archive: backup.archive,
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
  }
}

/// A picked backup copied into a staging directory this value owns.
final class _StagedPickedBackup implements LibraryBackupArchive {
  new({required this._file, required this.length, required this._directory});

  final File _file;
  final Directory _directory;
  Future<void>? _discarding;

  @override
  final int length;

  @override
  Stream<List<int>> openRead() => _file.openRead();

  @override
  Future<void> discard() => _discarding ??= _deleteIfPresent(_directory);
}

Future<void> _deleteIfPresent(Directory directory) async {
  if (directory.existsSync()) await directory.delete(recursive: true);
}

Future<Directory> _createSystemTempDirectory() => Directory.systemTemp.createTemp('prep-book-pick-');

Future<PickedLibraryBackup?> _openWithFilePicker() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['prepbook'],
  );
  if (file == null) return null;
  return PickedLibraryBackup(
    knownLength: file.lengthSync(),
    resolveLength: file.length,
    openRead: file.readAsByteStream,
  );
}

Future<bool> _saveWithFilePicker({
  required String suggestedName,
  required LibraryBackupArchive archive,
}) async {
  if (Platform.isAndroid) {
    // Android integration tests exercise this host-unreachable branch.
    // coverage:ignore-start
    return await saveAndroidBackup(
      suggestedName: suggestedName,
      content: archive.openRead(),
    );
    // coverage:ignore-end
  }
  // `file_picker` takes the whole file as one buffer on every other
  // platform, so the archive is read into exactly one allocation here, at
  // the last moment, rather than being held from creation onwards.
  final uri = await FilePicker.saveFile(
    fileName: suggestedName,
    bytes: await _readWhole(archive),
  );
  return uri != null;
}

/// [archive]'s content in one buffer of exactly its declared length.
Future<Uint8List> _readWhole(LibraryBackupArchive archive) async {
  final bytes = Uint8List(archive.length);
  var offset = 0;
  await for (final chunk in archive.openRead()) {
    if (chunk.length > bytes.length - offset) {
      throw StateError('The backup size changed while reading.');
    }
    bytes.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  if (offset != bytes.length) {
    throw StateError('The backup size changed while reading.');
  }
  return bytes;
}

Never _throwTooLarge() {
  throw LibraryBackupException(
    LibraryBackupFailureKind.backupTooLarge,
    cause: const FormatException('The backup exceeds the supported size.'),
    stackTrace: StackTrace.current,
  );
}
