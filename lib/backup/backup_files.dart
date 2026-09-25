import 'dart:io';

import 'package:prep_book/application/application.dart';

/// The narrow file operations required by database snapshot and replacement.
abstract interface class BackupFiles {
  Future<int> length(String path);

  Future<int?> lengthIfExists(String path);

  /// Opens a chunked read of the whole file at [path].
  Stream<List<int>> openRead(String path);

  /// Writes every chunk of [content] to [path], replacing what was there,
  /// and returns how many bytes were written.
  Future<int> writeStream(
    String path,
    Stream<List<int>> content, {
    required bool flush,
  });

  Future<void> copy(String source, String destination, {required bool flush});

  Future<void> renameReplacing(String source, String destination);

  Future<void> deleteIfExists(String path);

  Future<void> deleteDatabaseSidecars(String databasePath);

  /// Creates a new, empty directory for temporary files and returns its path.
  Future<String> createTemporaryDirectory(String prefix);

  /// Removes the directory at [path] and everything in it, if it exists.
  Future<void> deleteDirectory(String path);
}

/// `dart:io` implementation used on the supported mobile platforms.
final class IoBackupFiles implements BackupFiles {
  const new();

  @override
  Future<int> length(String path) => File(path).length();

  @override
  Future<int?> lengthIfExists(String path) => Future.sync(() {
    final file = File(path);
    if (!file.existsSync()) return null;
    return file.lengthSync();
  });

  @override
  Stream<List<int>> openRead(String path) => File(path).openRead();

  @override
  Future<int> writeStream(
    String path,
    Stream<List<int>> content, {
    required bool flush,
  }) async {
    final output = await File(path).open(mode: FileMode.write);
    var written = 0;
    try {
      await for (final chunk in content) {
        await output.writeFrom(chunk);
        written += chunk.length;
      }
      if (flush) await output.flush();
    } finally {
      await output.close();
    }
    return written;
  }

  @override
  Future<void> copy(
    String source,
    String destination, {
    required bool flush,
  }) async {
    await writeStream(destination, openRead(source), flush: flush);
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

  @override
  Future<String> createTemporaryDirectory(String prefix) async => (await Directory.systemTemp.createTemp(prefix)).path;

  @override
  Future<void> deleteDirectory(String path) async {
    final directory = Directory(path);
    if (directory.existsSync()) await directory.delete(recursive: true);
  }
}

/// A backup archive stored in a file inside a temporary directory that this
/// value owns, so [discard] removes the directory and everything staged in
/// it alongside the archive.
final class StagedBackupArchive implements LibraryBackupArchive {
  /// Creates an archive over the file at [path], [length] bytes long, whose
  /// temporary directory is removed on [discard].
  new({
    required this.path,
    required this.length,
    required this._directory,
    required this._files,
  });

  /// The archive file.
  final String path;

  @override
  final int length;

  final String _directory;
  final BackupFiles _files;
  Future<void>? _discarding;

  @override
  Stream<List<int>> openRead() => _files.openRead(path);

  @override
  Future<void> discard() => _discarding ??= _files.deleteDirectory(_directory);
}
