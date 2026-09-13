import 'dart:io';
import 'dart:typed_data';

/// The narrow file operations required by database snapshot and replacement.
abstract interface class BackupFiles {
  Future<int> length(String path);

  Future<int?> lengthIfExists(String path);

  Future<Uint8List> readBytes(String path);

  Future<void> writeBytes(String path, Uint8List bytes, {required bool flush});

  Future<void> copy(String source, String destination, {required bool flush});

  Future<void> renameReplacing(String source, String destination);

  Future<void> deleteIfExists(String path);

  Future<void> deleteDatabaseSidecars(String databasePath);
}

/// `dart:io` implementation used on the supported mobile platforms.
final class IoBackupFiles implements BackupFiles {
  const IoBackupFiles();

  @override
  Future<int> length(String path) => File(path).length();

  @override
  Future<int?> lengthIfExists(String path) => Future.sync(() {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.lengthSync();
  });

  @override
  Future<Uint8List> readBytes(String path) => File(path).readAsBytes();

  @override
  Future<void> writeBytes(
    String path,
    Uint8List bytes, {
    required bool flush,
  }) async {
    await File(path).writeAsBytes(bytes, flush: flush);
  }

  @override
  Future<void> copy(
    String source,
    String destination, {
    required bool flush,
  }) async {
    final bytes = await File(source).readAsBytes();
    await File(destination).writeAsBytes(bytes, flush: flush);
  }

  @override
  Future<void> renameReplacing(String source, String destination) async {
    await File(source).rename(destination);
  }

  @override
  Future<void> deleteIfExists(String path) async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }

  @override
  Future<void> deleteDatabaseSidecars(String databasePath) async {
    for (final suffix in const ['-wal', '-shm', '-journal']) {
      await deleteIfExists('$databasePath$suffix');
    }
  }
}
