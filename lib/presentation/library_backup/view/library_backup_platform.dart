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
  final Future<int> Function() resolveLength;

  /// Opens a fresh byte stream after the size check succeeds.
  final Stream<Uint8List> Function() openRead;
}

/// Opens the native backup picker.
typedef OpenLibraryBackupPicker = Future<PickedLibraryBackup?> Function();

/// Saves backup bytes through the native picker.
typedef SaveLibraryBackupPicker = Future<bool> Function({
  required String suggestedName,
  required Uint8List bytes,
});

/// Native file operations used by the library backup feature.
abstract interface class LibraryBackupPlatform {
  /// Picks and reads one backup, or returns `null` when cancelled.
  Future<Uint8List?> pickBackup();

  /// Saves [backup], or returns false when cancelled.
  Future<bool> saveBackup(LibraryBackupFile backup);
}

/// Adapts `file_picker` to the path-free presentation interface.
final class FilePickerLibraryBackupPlatform implements LibraryBackupPlatform {
  /// Creates the production adapter or one with injected picker functions.
  const new({
    OpenLibraryBackupPicker? openPicker,
    SaveLibraryBackupPicker? savePicker,
    int maxBackupBytes = maxLibraryBackupBytes,
  }) : assert(maxBackupBytes > 0, 'maxBackupBytes must be positive.'),
       _openPicker = openPicker ?? _openWithFilePicker,
       _savePicker = savePicker ?? _saveWithFilePicker,
       _maxBackupBytes = maxBackupBytes;

  final OpenLibraryBackupPicker _openPicker;
  final SaveLibraryBackupPicker _savePicker;
  final int _maxBackupBytes;

  @override
  Future<Uint8List?> pickBackup() async {
    try {
      final picked = await _openPicker();
      if (picked == null) return null;
      final length = picked.knownLength ?? await picked.resolveLength();
      if (length > _maxBackupBytes) _throwTooLarge();

      final bytes = Uint8List(length);
      var offset = 0;
      await for (final chunk in picked.openRead()) {
        if (chunk.length > length - offset) {
          throw StateError('The selected backup size changed while reading.');
        }
        bytes.setRange(offset, offset + chunk.length, chunk);
        offset += chunk.length;
      }
      if (offset != length) {
        throw StateError('The selected backup size changed while reading.');
      }
      return bytes;
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
        bytes: backup.bytes,
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
  required Uint8List bytes,
}) async {
  if (Platform.isAndroid) {
    // Android integration tests exercise this host-unreachable branch.
    // coverage:ignore-start
    return await saveAndroidBackup(suggestedName: suggestedName, bytes: bytes);
    // coverage:ignore-end
  }
  final uri = await FilePicker.saveFile(fileName: suggestedName, bytes: bytes);
  return uri != null;
}

Never _throwTooLarge() {
  throw LibraryBackupException(
    LibraryBackupFailureKind.backupTooLarge,
    cause: const FormatException('The backup exceeds the supported size.'),
    stackTrace: StackTrace.current,
  );
}
