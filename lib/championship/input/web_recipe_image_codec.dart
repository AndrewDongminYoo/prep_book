import 'dart:js_interop';
import 'dart:typed_data';

import 'package:prep_book/championship/input/recipe_image_reducer.dart';
import 'package:web/web.dart' as web;

/// Decodes and re-encodes a recipe image with the browser's own codecs.
///
/// Only the championship web entrypoint constructs this; no test imports it,
/// so it is absent from the coverage report the same way `bootstrap.dart` is,
/// and its behavior is checked by hand in Chrome (plan Task 8.8).
final class WebRecipeImageCodec implements RecipeImageCodec {
  const new();

  @override
  Future<DecodedRecipeImage> decode(Uint8List bytes, String mimeType) async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    // 'from-image' applies the EXIF orientation, so a portrait phone photo is
    // measured and drawn the way the camera showed it.
    final bitmap = await web.window
        .createImageBitmap(
          blob,
          web.ImageBitmapOptions(imageOrientation: 'from-image'),
        )
        .toDart;
    return _WebDecodedRecipeImage(bitmap);
  }
}

final class _WebDecodedRecipeImage implements DecodedRecipeImage {
  new(this._bitmap);

  final web.ImageBitmap _bitmap;

  @override
  int get width => _bitmap.width;

  @override
  int get height => _bitmap.height;

  @override
  Future<Uint8List> encodeJpeg({
    required int width,
    required int height,
    required double quality,
  }) async {
    final canvas = web.OffscreenCanvas(width, height);
    // JPEG has no alpha channel; without this fill a transparent PNG would
    // come out black wherever it was see-through.
    (canvas.getContext('2d')! as web.OffscreenCanvasRenderingContext2D)
      ..fillStyle = 'white'.toJS
      ..fillRect(0, 0, width, height)
      ..imageSmoothingEnabled = true
      ..imageSmoothingQuality = 'high'
      ..drawImage(_bitmap, 0, 0, width, height);
    final blob = await canvas
        .convertToBlob(
          web.ImageEncodeOptions(type: 'image/jpeg', quality: quality),
        )
        .toDart;
    final buffer = await blob.arrayBuffer().toDart;
    return Uint8List.view(buffer.toDart);
  }

  @override
  void close() => _bitmap.close();
}
