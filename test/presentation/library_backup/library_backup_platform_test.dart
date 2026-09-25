import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/library_backup/view/library_backup_platform.dart';

import '../../application/fakes.dart';

void main() {
  late Directory root;
  late List<Directory> stagingDirectories;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('prep-book-platform-');
    stagingDirectories = [];
  });

  tearDown(() => root.delete(recursive: true));

  Future<Directory> createStagingDirectory() async {
    final directory = await Directory(
      '${root.path}/staging-${stagingDirectories.length}',
    ).create();
    stagingDirectories.add(directory);
    return directory;
  }

  test('rejects declared oversize before listening or staging', () async {
    var listened = false;
    final platform = FilePickerLibraryBackupPlatform(
      maxBackupBytes: 3,
      createStagingDirectory: createStagingDirectory,
      openPicker: () async => PickedLibraryBackup(
        knownLength: 4,
        resolveLength: () async => 4,
        openRead: () {
          listened = true;
          return Stream.value(Uint8List.fromList([1]));
        },
      ),
    );

    await expectLater(
      platform.pickBackup(),
      throwsA(_failureKind(LibraryBackupFailureKind.backupTooLarge)),
    );

    expect(listened, isFalse);
    expect(stagingDirectories, isEmpty);
  });

  test('resolves unknown size then stages exact chunks on disk', () async {
    var lengthCalls = 0;
    final platform = FilePickerLibraryBackupPlatform(
      maxBackupBytes: 3,
      createStagingDirectory: createStagingDirectory,
      openPicker: () async => PickedLibraryBackup(
        resolveLength: () async {
          lengthCalls++;
          return 3;
        },
        openRead: () => Stream.fromIterable([
          Uint8List.fromList([1, 2]),
          Uint8List.fromList([3]),
        ]),
      ),
    );

    final archive = (await platform.pickBackup())!;

    expect(lengthCalls, 1);
    expect(archive.length, 3);
    final staged = stagingDirectories.single.listSync();
    expect(staged, hasLength(1));
    expect(await (staged.single as File).readAsBytes(), [1, 2, 3]);
    expect(await _readAll(archive), [1, 2, 3]);
    expect(await _readAll(archive), [1, 2, 3], reason: 'each read reopens the file');

    final discarding = archive.discard();
    expect(archive.discard(), same(discarding));
    await discarding;
    expect(stagingDirectories.single.existsSync(), isFalse);
  });

  test('reports an unavailable selected-file length without reading it', () async {
    var listened = false;
    final platform = FilePickerLibraryBackupPlatform(
      createStagingDirectory: createStagingDirectory,
      openPicker: () async => PickedLibraryBackup(
        resolveLength: () async => null,
        openRead: () {
          listened = true;
          return Stream.value(Uint8List.fromList([1]));
        },
      ),
    );

    await expectLater(
      platform.pickBackup(),
      throwsA(_failureKind(LibraryBackupFailureKind.restoreFailed)),
    );

    expect(listened, isFalse);
    expect(stagingDirectories, isEmpty);
  });

  test('rejects a file that ends short and removes what it staged', () async {
    final platform = FilePickerLibraryBackupPlatform(
      createStagingDirectory: createStagingDirectory,
      openPicker: () async => PickedLibraryBackup(
        knownLength: 2,
        resolveLength: () async => 2,
        openRead: () => Stream.value(Uint8List.fromList([1])),
      ),
    );

    await expectLater(
      platform.pickBackup(),
      throwsA(_failureKind(LibraryBackupFailureKind.restoreFailed)),
    );

    expect(stagingDirectories.single.existsSync(), isFalse);
  });

  test('stops when a chunk exceeds the resolved length', () async {
    var chunksRead = 0;
    final platform = FilePickerLibraryBackupPlatform(
      maxBackupBytes: 4,
      createStagingDirectory: createStagingDirectory,
      openPicker: () async => PickedLibraryBackup(
        knownLength: 2,
        resolveLength: () async => 2,
        openRead: () async* {
          chunksRead++;
          yield Uint8List.fromList([1, 2]);
          chunksRead++;
          yield Uint8List.fromList([3]);
          chunksRead++;
          yield Uint8List.fromList([4]);
        },
      ),
    );

    await expectLater(
      platform.pickBackup(),
      throwsA(_failureKind(LibraryBackupFailureKind.restoreFailed)),
    );

    expect(chunksRead, 2);
    expect(stagingDirectories.single.existsSync(), isFalse);
  });

  test('a staging directory that cannot be created fails the pick', () async {
    final stagingError = StateError('no temporary directory');
    var listened = false;
    final platform = FilePickerLibraryBackupPlatform(
      createStagingDirectory: () async => throw stagingError,
      openPicker: () async => PickedLibraryBackup(
        knownLength: 1,
        resolveLength: () async => 1,
        openRead: () {
          listened = true;
          return Stream.value(Uint8List.fromList([1]));
        },
      ),
    );

    await expectLater(
      platform.pickBackup(),
      throwsA(
        _failureWithCause(LibraryBackupFailureKind.restoreFailed, stagingError),
      ),
    );
    expect(listened, isFalse);
  });

  test('open and save cancellation are neutral', () async {
    final platform = FilePickerLibraryBackupPlatform(
      openPicker: () async => null,
      savePicker: ({required suggestedName, required archive}) async => false,
      createStagingDirectory: createStagingDirectory,
    );

    expect(await platform.pickBackup(), isNull);
    expect(stagingDirectories, isEmpty);
    expect(
      await platform.saveBackup(
        LibraryBackupFile(
          archive: MemoryBackupArchive([1]),
          suggestedName: 'library.prepbook',
        ),
      ),
      isFalse,
    );
  });

  test('save passes the exact archive and returns the picker result', () async {
    String? receivedName;
    LibraryBackupArchive? receivedArchive;
    final platform = FilePickerLibraryBackupPlatform(
      savePicker: ({required suggestedName, required archive}) async {
        receivedName = suggestedName;
        receivedArchive = archive;
        return true;
      },
    );
    final archive = MemoryBackupArchive([7, 8]);
    final backup = LibraryBackupFile(
      archive: archive,
      suggestedName: 'backup.prepbook',
    );

    expect(await platform.saveBackup(backup), isTrue);
    expect(receivedName, 'backup.prepbook');
    expect(receivedArchive, same(archive));
    expect(archive.discardCount, 0, reason: 'the caller owns the archive');
  });

  test('default bindings delegate to file_picker', () async {
    final previous = FilePickerPlatform.instance;
    final file = _TestPlatformFile(Uint8List.fromList([4, 5]));
    final picker = _TestFilePickerPlatform(file);
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    const platform = FilePickerLibraryBackupPlatform();

    final picked = (await platform.pickBackup())!;
    addTearDown(picked.discard);
    expect(await _readAll(picked), [4, 5]);
    expect(picker.pickType, FileType.custom);
    expect(picker.allowedExtensions, ['prepbook']);
    final saved = MemoryBackupArchive([6, 7, 8], chunkSize: 2);
    expect(
      await platform.saveBackup(
        LibraryBackupFile(archive: saved, suggestedName: 'native.prepbook'),
      ),
      isTrue,
    );
    expect(picker.savedName, 'native.prepbook');
    expect(picker.savedBytes, [6, 7, 8]);
    expect(picker.savedMimeType, 'application/octet-stream');
    expect(saved.readCount, 1);
  });

  for (final (description, content) in [
    ('shorter', [1]),
    ('longer', [1, 2, 3]),
  ]) {
    test('the default save refuses an archive $description than it reports', () async {
      final previous = FilePickerPlatform.instance;
      final picker = _TestFilePickerPlatform(null);
      FilePickerPlatform.instance = picker;
      addTearDown(() => FilePickerPlatform.instance = previous);
      const platform = FilePickerLibraryBackupPlatform();

      await expectLater(
        platform.saveBackup(
          LibraryBackupFile(
            archive: _MisreportedArchive(content, reportedLength: 2),
            suggestedName: 'native.prepbook',
          ),
        ),
        throwsA(_failureKind(LibraryBackupFailureKind.saveFailed)),
      );
      expect(picker.savedName, isNull);
    });
  }

  test('maps open and save exceptions without exposing paths', () async {
    final openError = StateError('open picker path');
    final saveError = StateError('save picker path');

    await expectLater(
      FilePickerLibraryBackupPlatform(
        openPicker: () async => throw openError,
      ).pickBackup(),
      throwsA(
        _failureWithCause(LibraryBackupFailureKind.restoreFailed, openError),
      ),
    );
    await expectLater(
      FilePickerLibraryBackupPlatform(
        savePicker: ({required suggestedName, required archive}) async => throw saveError,
      ).saveBackup(
        LibraryBackupFile(
          archive: MemoryBackupArchive([1]),
          suggestedName: 'backup.prepbook',
        ),
      ),
      throwsA(
        _failureWithCause(LibraryBackupFailureKind.saveFailed, saveError),
      ),
    );
  });
}

Future<List<int>> _readAll(LibraryBackupArchive archive) => archive.openRead().expand((chunk) => chunk).toList();

/// An archive whose content disagrees with the length it reports.
final class _MisreportedArchive implements LibraryBackupArchive {
  new(this._content, {required this.reportedLength});

  final List<int> _content;
  final int reportedLength;

  @override
  int get length => reportedLength;

  @override
  Stream<List<int>> openRead() => Stream.value(_content);

  @override
  Future<void> discard() async {}
}

Matcher _failureKind(LibraryBackupFailureKind kind) =>
    isA<LibraryBackupException>().having((error) => error.kind, 'kind', kind);

Matcher _failureWithCause(LibraryBackupFailureKind kind, Object cause) => isA<LibraryBackupException>()
    .having((error) => error.kind, 'kind', kind)
    .having((error) => error.cause, 'cause', same(cause))
    .having((error) => error.stackTrace, 'stackTrace', isNotNull);

final class _TestPlatformFile extends PlatformFile {
  new(this._bytes);

  final Uint8List _bytes;

  @override
  String get name => 'backup.prepbook';

  @override
  Uri get uri => Uri.parse('content://prepbook/backup');

  @override
  Never get xFile => throw UnimplementedError();

  @override
  int lengthSync() => _bytes.length;

  @override
  Future<int> length() async => _bytes.length;

  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList(_bytes);

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(_bytes);
}

final class _TestFilePickerPlatform extends FilePickerPlatform {
  new(this.file);

  final PlatformFile? file;
  FileType? pickType;
  List<String>? allowedExtensions;
  String? savedName;
  Uint8List? savedBytes;
  String? savedMimeType;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus status)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    pickType = type;
    this.allowedExtensions = allowedExtensions;
    return file;
  }

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    void Function(FilePickerStatus status)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    savedName = fileName;
    savedBytes = Uint8List.fromList(bytes);
    savedMimeType = mimeType;
    return Uri.parse('content://prepbook/saved');
  }
}
