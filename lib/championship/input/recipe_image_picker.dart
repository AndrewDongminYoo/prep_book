import 'dart:typed_data';

abstract interface class RecipeImagePicker {
  Future<SelectedRecipeImage?> pick();
}

final class SelectedRecipeImage {
  factory SelectedRecipeImage({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) => SelectedRecipeImage._(
    name: name,
    mimeType: mimeType,
    bytes: Uint8List.fromList(bytes),
  );

  const SelectedRecipeImage._({
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
  const RecipeImagePickerException(this.failure);

  final RecipeImagePickerFailure failure;

  @override
  String toString() => 'RecipeImagePickerException(${failure.name})';
}
