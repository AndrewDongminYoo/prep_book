import 'dart:math' as math;
import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:prep_book/championship/input/recipe_image_picker.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';

/// The longest edge, in pixels, an uploaded image may keep.
///
/// The provider's high-detail mode spends at most 2,500 patches of 32 px, so
/// nothing a 2,048 px edge discards would have reached the model.
const int recipeImportMaxImageEdge = 2048;

/// One reduction attempt: the longest edge to scale to and the JPEG quality.
typedef RecipeImageReductionStep = ({int longestEdge, double quality});

/// The attempts made, in order, until the encoded image fits
/// [recipeImportMaxImageBytes].
const recipeImageReductionLadder = <RecipeImageReductionStep>[
  (longestEdge: 2048, quality: 0.85),
  (longestEdge: 1600, quality: 0.80),
  (longestEdge: 1280, quality: 0.75),
];

/// Decodes one selected image so it can be measured and re-encoded.
abstract interface class RecipeImageCodec {
  Future<DecodedRecipeImage> decode(Uint8List bytes, String mimeType);
}

/// One decoded image, oriented as it should be viewed.
abstract interface class DecodedRecipeImage {
  int get width;
  int get height;

  /// Renders the image at exactly [width] by [height] over an opaque white
  /// background and encodes it as JPEG at [quality].
  Future<Uint8List> encodeJpeg({
    required int width,
    required int height,
    required double quality,
  });

  void close();
}

/// The image as it will be uploaded, with what was done to the selection.
@immutable
final class PreparedRecipeImage {
  const PreparedRecipeImage({
    required this.image,
    required this.width,
    required this.height,
    required this.originalByteCount,
    required this.wasReduced,
  });

  final SelectedRecipeImage image;
  final int width;
  final int height;
  final int originalByteCount;
  final bool wasReduced;
}

enum RecipeImageReducerFailure { undecodable, tooLarge }

final class RecipeImageReducerException implements Exception {
  const RecipeImageReducerException(this.failure);

  final RecipeImageReducerFailure failure;

  @override
  String toString() => 'RecipeImageReducerException(${failure.name})';
}

/// Brings a selected image under the upload limits before it is sent.
///
/// An image already within [recipeImportMaxImageBytes] and
/// [recipeImportMaxImageEdge] is passed through untouched, so a screenshot
/// keeps its lossless PNG bytes; anything else is scaled and re-encoded as
/// JPEG down [recipeImageReductionLadder] until it fits.
final class RecipeImageReducer {
  const RecipeImageReducer({required this.codec});

  final RecipeImageCodec codec;

  Future<PreparedRecipeImage> reduce(SelectedRecipeImage image) async {
    final DecodedRecipeImage decoded;
    try {
      decoded = await codec.decode(image.bytes, image.mimeType);
    } on Object {
      throw const RecipeImageReducerException(
        RecipeImageReducerFailure.undecodable,
      );
    }
    try {
      final longestEdge = math.max(decoded.width, decoded.height);
      if (image.bytes.length <= recipeImportMaxImageBytes &&
          longestEdge <= recipeImportMaxImageEdge) {
        return PreparedRecipeImage(
          image: image,
          width: decoded.width,
          height: decoded.height,
          originalByteCount: image.bytes.length,
          wasReduced: false,
        );
      }
      for (final step in recipeImageReductionLadder) {
        final scale = math.min(1, step.longestEdge / longestEdge);
        final width = math.max(1, (decoded.width * scale).round());
        final height = math.max(1, (decoded.height * scale).round());
        final Uint8List bytes;
        try {
          bytes = await decoded.encodeJpeg(
            width: width,
            height: height,
            quality: step.quality,
          );
        } on Object {
          throw const RecipeImageReducerException(
            RecipeImageReducerFailure.undecodable,
          );
        }
        if (bytes.length <= recipeImportMaxImageBytes) {
          return PreparedRecipeImage(
            image: SelectedRecipeImage(
              name: image.name,
              mimeType: 'image/jpeg',
              bytes: bytes,
            ),
            width: width,
            height: height,
            originalByteCount: image.bytes.length,
            wasReduced: true,
          );
        }
      }
      throw const RecipeImageReducerException(
        RecipeImageReducerFailure.tooLarge,
      );
    } finally {
      decoded.close();
    }
  }
}
