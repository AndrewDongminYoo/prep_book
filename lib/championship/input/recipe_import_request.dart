import 'dart:convert';
import 'dart:typed_data';

const int recipeImportMaxTextScalars = 20000;
const int recipeImportMaxImageBytes = 3 * 1024 * 1024;
const recipeImportImageMimeTypes = {'image/jpeg', 'image/png', 'image/webp'};

sealed class RecipeImportRequest {
  const new();

  Map<String, Object?> toJson(String locale);
}

final class TextRecipeImportRequest extends RecipeImportRequest {
  factory(String text) {
    if (text.trim().isEmpty) {
      throw ArgumentError.value(text, 'text', 'must not be blank');
    }
    if (text.runes.length > recipeImportMaxTextScalars) {
      throw ArgumentError.value(text.length, 'text', 'is too large');
    }
    return TextRecipeImportRequest._(text);
  }

  const new _(this.text);

  final String text;

  @override
  Map<String, Object?> toJson(String locale) {
    _validateLocale(locale);
    return {
      'sourceKind': 'text',
      'text': text,
      'imageDataUrl': null,
      'locale': locale,
    };
  }
}

final class ImageRecipeImportRequest extends RecipeImportRequest {
  factory({
    required Uint8List bytes,
    required String mimeType,
  }) {
    if (!recipeImportImageMimeTypes.contains(mimeType)) {
      throw ArgumentError.value(mimeType, 'mimeType', 'is unsupported');
    }
    if (bytes.isEmpty) {
      throw ArgumentError.value(bytes.length, 'bytes', 'must not be empty');
    }
    if (bytes.length > recipeImportMaxImageBytes) {
      throw ArgumentError.value(bytes.length, 'bytes', 'is too large');
    }
    return ImageRecipeImportRequest._(Uint8List.fromList(bytes), mimeType);
  }

  const new _(this._bytes, this.mimeType);

  final Uint8List _bytes;
  final String mimeType;

  @override
  Map<String, Object?> toJson(String locale) {
    _validateLocale(locale);
    return {
      'sourceKind': 'image',
      'text': null,
      'imageDataUrl': 'data:$mimeType;base64,${base64Encode(_bytes)}',
      'locale': locale,
    };
  }
}

void _validateLocale(String locale) {
  if (locale != 'ko' && locale != 'en') {
    throw ArgumentError.value(locale, 'locale', 'must be ko or en');
  }
}
