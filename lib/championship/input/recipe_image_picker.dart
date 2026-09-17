import 'dart:typed_data';

/// The largest file the picker reads into memory.
///
/// A camera photo is commonly larger than the upload limit; the reducer brings
/// it under that limit afterwards, so this bound only protects memory.
const int recipeImportMaxSelectedImageBytes = 32 * 1024 * 1024;

abstract interface class RecipeImagePicker {
  Future<SelectedRecipeImage?> pick();
}

final class SelectedRecipeImage {
  factory({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) => SelectedRecipeImage._(
    name: name,
    mimeType: mimeType,
    bytes: Uint8List.fromList(bytes),
  );

  const new _({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;
}

enum RecipeImagePickerFailure {
  multipleFiles,
  missingBytes,
  unsupportedExtension,
  unsupportedMimeType,
  mimeExtensionMismatch,
  sourceTooLarge,
}

final class RecipeImagePickerException implements Exception {
  const new(this.failure);

  final RecipeImagePickerFailure failure;

  @override
  String toString() => 'RecipeImagePickerException(${failure.name})';
}
