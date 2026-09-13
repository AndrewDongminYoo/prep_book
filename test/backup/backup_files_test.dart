import 'dart:io';
import 'dart:typed_data';

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

  test('writes, measures, and reads exact bytes', () async {
    final target = '${directory.path}/library.db';
    final bytes = Uint8List.fromList([0, 1, 2, 255]);

    await files.writeBytes(target, bytes, flush: true);

    expect(await files.length(target), 4);
    expect(await files.readBytes(target), bytes);
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
    await files.deleteIfExists('${directory.path}/missing.db');
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
}
