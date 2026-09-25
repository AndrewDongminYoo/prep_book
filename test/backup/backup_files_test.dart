import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/backup/backup_files.dart';

void main() {
  late Directory directory;
  late BackupFiles files;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prep-book-files-');
    files = const IoBackupFiles();
  });

  tearDown(() => directory.delete(recursive: true));

  test('writes a chunked stream, measures, and reads exact bytes', () async {
    final target = '${directory.path}/library.db';
    await File(target).writeAsBytes(List.filled(16, 7), flush: true);

    final written = await files.writeStream(
      target,
      Stream.fromIterable([
        [0, 1],
        <int>[],
        [2, 255],
      ]),
      flush: true,
    );

    expect(written, 4);
    expect(await files.length(target), 4);
    expect(await files.lengthIfExists(target), 4);
    expect(
      await files.openRead(target).expand((chunk) => chunk).toList(),
      [0, 1, 2, 255],
    );
  });

  test('a failing stream propagates after closing the partial file', () async {
    final target = '${directory.path}/partial.db';
    final failure = StateError('source failed');
    Stream<List<int>> failingSource() async* {
      yield [1, 2];
      throw failure;
    }

    await expectLater(
      files.writeStream(target, failingSource(), flush: false),
      throwsA(same(failure)),
    );

    expect(await File(target).readAsBytes(), [1, 2]);
    await File(target).delete();
  });

  test('copies exact bytes with the requested flush', () async {
    final source = '${directory.path}/source.db';
    final destination = '${directory.path}/copy.db';
    await File(source).writeAsBytes([3, 4, 5], flush: true);

    await files.copy(source, destination, flush: true);

    expect(await File(destination).readAsBytes(), [3, 4, 5]);
  });

  test('renameReplacing atomically replaces the destination', () async {
    final source = '${directory.path}/candidate.db';
    final destination = '${directory.path}/library.db';
    await File(source).writeAsBytes([1], flush: true);
    await File(destination).writeAsBytes([9], flush: true);

    await files.renameReplacing(source, destination);

    expect(await File(destination).readAsBytes(), [1]);
    expect(File(source).existsSync(), isFalse);
  });

  test('deleteIfExists is harmless when the path is missing', () async {
    final missingPath = '${directory.path}/missing.db';

    expect(await files.lengthIfExists(missingPath), isNull);
    await files.deleteIfExists(missingPath);
  });

  test('deletes only sidecars for the exact database path', () async {
    final databasePath = '${directory.path}/library.db';
    final exactSidecars = [
      '$databasePath-wal',
      '$databasePath-shm',
      '$databasePath-journal',
    ];
    final unrelated = [
      '${directory.path}/other.db-wal',
      '${directory.path}/library.db-copy',
    ];
    for (final path in [...exactSidecars, ...unrelated]) {
      await File(path).writeAsString('sentinel');
    }

    await files.deleteDatabaseSidecars(databasePath);

    expect(exactSidecars.where((path) => File(path).existsSync()), isEmpty);
    expect(unrelated.where((path) => File(path).existsSync()), hasLength(2));
  });

  test('creates and deletes a temporary directory with its contents', () async {
    final path = await files.createTemporaryDirectory('prep-book-files-test-');
    await File('$path/nested.prepbook').writeAsBytes([1], flush: true);

    expect(Directory(path).existsSync(), isTrue);
    expect(path.split(Platform.pathSeparator).last, startsWith('prep-book-files-test-'));

    await files.deleteDirectory(path);
    await files.deleteDirectory(path);

    expect(Directory(path).existsSync(), isFalse);
  });

  test('a staged archive reads its file and discards its directory once', () async {
    final stagingDirectory = await Directory('${directory.path}/staged').create();
    final archivePath = '${stagingDirectory.path}/backup.prepbook';
    await File(archivePath).writeAsBytes([4, 5, 6], flush: true);
    final recording = _DeleteCountingFiles();
    final archive = StagedBackupArchive(
      path: archivePath,
      length: 3,
      directory: stagingDirectory.path,
      files: recording,
    );

    expect(archive.length, 3);
    expect(await archive.openRead().expand((chunk) => chunk).toList(), [4, 5, 6]);

    final first = archive.discard();
    final second = archive.discard();
    expect(second, same(first));
    await first;

    expect(recording.deletedDirectories, [stagingDirectory.path]);
    expect(stagingDirectory.existsSync(), isFalse);
  });
}

final class _DeleteCountingFiles implements BackupFiles {
  static const _delegate = IoBackupFiles();
  final deletedDirectories = <String>[];

  @override
  Stream<List<int>> openRead(String path) => _delegate.openRead(path);

  @override
  Future<void> deleteDirectory(String path) {
    deletedDirectories.add(path);
    return _delegate.deleteDirectory(path);
  }

  @override
  Object? noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
