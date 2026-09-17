import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/library_backup/view/library_backup_platform.dart';

void main() {
  test('rejects declared oversize before listening to the stream', () async {
    var listened = false;
    final platform = FilePickerLibraryBackupPlatform(
      maxBackupBytes: 3,
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
  });

  test('resolves unknown size then collects exact chunks', () async {
    var lengthCalls = 0;
    final first = Uint8List.fromList([1, 2]);
    final second = Uint8List.fromList([3]);
    final platform = FilePickerLibraryBackupPlatform(
      maxBackupBytes: 3,
      openPicker: () async => PickedLibraryBackup(
        resolveLength: () async {
          lengthCalls++;
          return 3;
        },
        openRead: () => Stream.fromIterable([first, second]),
      ),
    );

    final bytes = await platform.pickBackup();

    expect(lengthCalls, 1);
    expect(bytes, [1, 2, 3]);
    expect(identical(bytes, first), isFalse);
  });

  test('reports an unavailable selected-file length without reading it', () async {
    var listened = false;
    final platform = FilePickerLibraryBackupPlatform(
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
  });

  test('rejects a file whose size changes while it is read', () async {
    final platform = FilePickerLibraryBackupPlatform(
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
  });

  test('stops when a chunk exceeds the resolved length', () async {
    var chunksRead = 0;
    final platform = FilePickerLibraryBackupPlatform(
      maxBackupBytes: 4,
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
  });

  test('open and save cancellation are neutral', () async {
    final platform = FilePickerLibraryBackupPlatform(
      openPicker: () async => null,
      savePicker: ({required suggestedName, required bytes}) async => false,
    );

    expect(await platform.pickBackup(), isNull);
    expect(
      await platform.saveBackup(
        LibraryBackupFile(
          bytes: Uint8List.fromList([1]),
          suggestedName: 'library.prepbook',
        ),
      ),
      isFalse,
    );
  });

  test('save passes exact value and returns picker result', () async {
    String? receivedName;
    Uint8List? receivedBytes;
    final platform = FilePickerLibraryBackupPlatform(
      savePicker: ({required suggestedName, required bytes}) async {
        receivedName = suggestedName;
        receivedBytes = bytes;
        return true;
      },
    );
    final backup = LibraryBackupFile(
      bytes: Uint8List.fromList([7, 8]),
      suggestedName: 'backup.prepbook',
    );

    expect(await platform.saveBackup(backup), isTrue);
    expect(receivedName, 'backup.prepbook');
    expect(receivedBytes, [7, 8]);
  });

  test('default bindings delegate to file_picker', () async {
    final previous = FilePickerPlatform.instance;
    final file = _TestPlatformFile(Uint8List.fromList([4, 5]));
    final picker = _TestFilePickerPlatform(file);
    FilePickerPlatform.instance = picker;
    addTearDown(() => FilePickerPlatform.instance = previous);
    const platform = FilePickerLibraryBackupPlatform();

    expect(await platform.pickBackup(), [4, 5]);
    expect(picker.pickType, FileType.custom);
    expect(picker.allowedExtensions, ['prepbook']);
    expect(
      await platform.saveBackup(
        LibraryBackupFile(
          bytes: Uint8List.fromList([6, 7]),
          suggestedName: 'native.prepbook',
        ),
      ),
      isTrue,
    );
    expect(picker.savedName, 'native.prepbook');
    expect(picker.savedBytes, [6, 7]);
    expect(picker.savedMimeType, 'application/octet-stream');
  });

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
        savePicker: ({required suggestedName, required bytes}) async => throw saveError,
      ).saveBackup(
        LibraryBackupFile(
          bytes: Uint8List.fromList([1]),
          suggestedName: 'backup.prepbook',
        ),
      ),
      throwsA(
        _failureWithCause(LibraryBackupFailureKind.saveFailed, saveError),
      ),
    );
  });
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
