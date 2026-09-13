import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:prep_book/championship/input/recipe_image_picker.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';

typedef PickRecipeImageFiles =
    Future<List<RecipeImagePickerFile>> Function(
      RecipeImagePickerOptions options,
    );

final class RecipeImagePickerOptions {
  const RecipeImagePickerOptions({
    required this.allowMultiple,
    required this.loadBytesInMemory,
    required this.allowedExtensions,
  });

  final bool allowMultiple;
  final bool loadBytesInMemory;
  final List<String> allowedExtensions;
}

final class RecipeImagePickerFile {
  const RecipeImagePickerFile({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String? mimeType;
  final Uint8List? bytes;
}

final class FilePickerRecipeImagePicker implements RecipeImagePicker {
  const FilePickerRecipeImagePicker({PickRecipeImageFiles? pickFiles})
    : _injections = (pickFiles: pickFiles);

  static const _options = RecipeImagePickerOptions(
    allowMultiple: false,
    loadBytesInMemory: true,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
  );

  final ({PickRecipeImageFiles? pickFiles}) _injections;

  @override
  Future<SelectedRecipeImage?> pick() async {
    final files = await (_injections.pickFiles ?? _pickPlatformFiles)(_options);
    if (files.isEmpty) return null;
    if (files.length != 1) {
      throw const RecipeImagePickerException(
        RecipeImagePickerFailure.multipleFiles,
      );
    }

    final file = files.single;
    final extension = _extensionOf(file.name);
    final expectedMimeType = switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (expectedMimeType == null) {
      throw const RecipeImagePickerException(
        RecipeImagePickerFailure.unsupportedExtension,
      );
    }
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw const RecipeImagePickerException(
        RecipeImagePickerFailure.missingBytes,
      );
    }
    if (bytes.length > recipeImportMaxImageBytes) {
      throw const RecipeImagePickerException(
        RecipeImagePickerFailure.sourceTooLarge,
      );
    }
    final detectedMimeType = _detectImageMimeType(bytes);
    if (detectedMimeType == null) {
      throw const RecipeImagePickerException(
        RecipeImagePickerFailure.unsupportedMimeType,
      );
    }
    final declaredMimeType = file.mimeType;
    if (declaredMimeType != null &&
        (!recipeImportImageMimeTypes.contains(declaredMimeType) ||
            declaredMimeType != detectedMimeType)) {
      throw const RecipeImagePickerException(
        RecipeImagePickerFailure.mimeExtensionMismatch,
      );
    }
    if (detectedMimeType != expectedMimeType) {
      throw const RecipeImagePickerException(
        RecipeImagePickerFailure.mimeExtensionMismatch,
      );
    }
    return SelectedRecipeImage(
      name: file.name,
      mimeType: detectedMimeType,
      bytes: bytes,
    );
  }
}

// The browser picker itself is verified by the web acceptance pass. Unit tests
// inject the normalized file shape so they never open an OS dialog.
// coverage:ignore-start
Future<List<RecipeImagePickerFile>> _pickPlatformFiles(
  RecipeImagePickerOptions options,
) async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: options.allowedExtensions,
  );
  if (file == null) return const [];
  Uint8List? bytes;
  String? mimeType;
  try {
    bytes = await file.readAsBytes();
    mimeType = file.xFile.mimeType;
  } on Object {
    // The public picker maps unreadable selections to the missing-bytes error.
  }
  return [
    RecipeImagePickerFile(name: file.name, mimeType: mimeType, bytes: bytes),
  ];
}
// coverage:ignore-end

String? _extensionOf(String name) {
  final separator = name.lastIndexOf('.');
  if (separator <= 0 || separator == name.length - 1) return null;
  return name.substring(separator + 1).toLowerCase();
}

String? _detectImageMimeType(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'image/webp';
  }
  return null;
}
