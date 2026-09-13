import 'dart:typed_data';

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

  test('rejects images over the decoded size limit', () async {
    final picker = FilePickerRecipeImagePicker(
      pickFiles: (_) async => [
        _file(bytes: Uint8List(recipeImportMaxImageBytes + 1)),
      ],
    );

    await expectLater(
      picker.pick(),
      throwsA(isA<RecipeImagePickerException>()),
    );
  });
}
