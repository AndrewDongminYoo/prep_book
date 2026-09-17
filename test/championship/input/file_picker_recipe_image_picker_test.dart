import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/input/file_picker_recipe_image_picker.dart';
import 'package:prep_book/championship/input/recipe_image_picker.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';

RecipeImagePickerFile _file({
  String name = 'recipe.png',
  String? mimeType = 'image/png',
  Uint8List? bytes,
}) => RecipeImagePickerFile(
  name: name,
  mimeType: mimeType,
  bytes: bytes ?? _pngBytes(),
);

Uint8List _pngBytes() => Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]);

void main() {
  test('detects valid web bytes when MIME metadata is absent', () async {
    final fixtures = [
      ('recipe.jpg', Uint8List.fromList([255, 216, 255]), 'image/jpeg'),
      ('recipe.png', _pngBytes(), 'image/png'),
      (
        'recipe.webp',
        Uint8List.fromList([82, 73, 70, 70, 0, 0, 0, 0, 87, 69, 66, 80]),
        'image/webp',
      ),
    ];
    for (final (name, bytes, expectedMimeType) in fixtures) {
      final picker = FilePickerRecipeImagePicker(
        pickFiles: (_) async => [
          RecipeImagePickerFile(name: name, mimeType: null, bytes: bytes),
        ],
      );

      final selected = await picker.pick();

      expect(selected?.mimeType, expectedMimeType);
    }
  });

  test('requests one in-memory custom image and copies its bytes', () async {
    RecipeImagePickerOptions? options;
    final source = _pngBytes();
    final picker = FilePickerRecipeImagePicker(
      pickFiles: (received) async {
        options = received;
        return [_file(bytes: source)];
      },
    );

    final selected = await picker.pick();
    source[0] = 9;

    expect(options?.allowMultiple, isFalse);
    expect(options?.loadBytesInMemory, isTrue);
    expect(options?.allowedExtensions, ['jpg', 'jpeg', 'png', 'webp']);
    expect(selected?.name, 'recipe.png');
    expect(selected?.mimeType, 'image/png');
    expect(selected?.bytes, [137, 80, 78, 71, 13, 10, 26, 10]);
  });

  test('returns null when selection is cancelled', () async {
    final picker = FilePickerRecipeImagePicker(pickFiles: (_) async => []);

    expect(await picker.pick(), isNull);
  });

  test('reports an unavailable selected-file length as unreadable', () async {
    final previous = FilePickerPlatform.instance;
    final file = _NullLengthPlatformFile();
    FilePickerPlatform.instance = _NullLengthFilePickerPlatform(file);
    addTearDown(() => FilePickerPlatform.instance = previous);

    await expectLater(
      const FilePickerRecipeImagePicker().pick(),
      throwsA(
        isA<RecipeImagePickerException>().having(
          (error) => error.failure,
          'failure',
          RecipeImagePickerFailure.missingBytes,
        ),
      ),
    );
    expect(file.readAttempted, isFalse);
  });

  test('rejects multiple files and absent bytes', () async {
    final multiple = FilePickerRecipeImagePicker(
      pickFiles: (_) async => [_file(), _file(name: 'second.png')],
    );
    final absent = FilePickerRecipeImagePicker(
      pickFiles: (_) async => [
        const RecipeImagePickerFile(
          name: 'recipe.png',
          mimeType: 'image/png',
          bytes: null,
        ),
      ],
    );

    await expectLater(
      multiple.pick(),
      throwsA(isA<RecipeImagePickerException>()),
    );
    await expectLater(
      absent.pick(),
      throwsA(isA<RecipeImagePickerException>()),
    );
  });

  test('rejects unsupported extensions and MIME mismatches', () async {
    for (final file in [
      _file(name: 'recipe.heic', mimeType: 'image/heic'),
      _file(mimeType: 'image/jpeg'),
      _file(name: 'recipe'),
      _file(name: 'recipe.webp', mimeType: null),
      _file(mimeType: null, bytes: Uint8List.fromList([1, 2, 3])),
    ]) {
      final picker = FilePickerRecipeImagePicker(
        pickFiles: (_) async => [file],
      );

      await expectLater(
        picker.pick(),
        throwsA(isA<RecipeImagePickerException>()),
      );
    }
  });

  test('rejects images over the selection size limit', () async {
    final picker = FilePickerRecipeImagePicker(
      pickFiles: (_) async => [
        _file(bytes: Uint8List(recipeImportMaxSelectedImageBytes + 1)),
      ],
    );

    await expectLater(
      picker.pick(),
      throwsA(
        isA<RecipeImagePickerException>().having(
          (e) => e.failure,
          'failure',
          RecipeImagePickerFailure.sourceTooLarge,
        ),
      ),
    );
  });

  test('accepts an image over the upload limit for the reducer', () async {
    final bytes = Uint8List(recipeImportMaxImageBytes + 1)..setAll(0, _pngBytes());
    final picker = FilePickerRecipeImagePicker(
      pickFiles: (_) async => [_file(bytes: bytes)],
    );

    final selected = await picker.pick();

    expect(selected?.bytes.length, recipeImportMaxImageBytes + 1);
    expect(recipeImportMaxSelectedImageBytes, 32 * 1024 * 1024);
  });
}

final class _NullLengthFilePickerPlatform extends FilePickerPlatform {
  new(this.file);

  final _NullLengthPlatformFile file;

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
  }) async => file;
}

final class _NullLengthPlatformFile extends PlatformFile {
  bool readAttempted = false;

  @override
  String get name => 'recipe.png';

  @override
  Uri get uri => Uri.parse('content://prepbook/recipe');

  @override
  Never get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => null;

  @override
  Future<int?> length() async => null;

  @override
  Future<Uint8List> readAsBytes() async {
    readAttempted = true;
    return _pngBytes();
  }

  @override
  Stream<Uint8List> readAsByteStream() => throw StateError('must not read');
}
