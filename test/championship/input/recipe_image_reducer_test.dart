import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/input/recipe_image_picker.dart';
import 'package:prep_book/championship/input/recipe_image_reducer.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';

import '../championship_test_harness.dart';

const int _mib = 1024 * 1024;

SelectedRecipeImage _image({
  int byteCount = 100 * 1024,
  String mimeType = 'image/png',
  String name = 'recipe.png',
}) => SelectedRecipeImage(
  name: name,
  mimeType: mimeType,
  bytes: Uint8List(byteCount)..[0] = 137,
);

void main() {
  test('sends a small image within both limits unchanged', () async {
    final codec = FakeRecipeImageCodec(
      encodedBytesFor: (_) => fail('must not encode'),
    );
    final image = _image();

    final prepared = await RecipeImageReducer(codec: codec).reduce(image);

    expect(prepared.image.bytes, image.bytes);
    expect(prepared.image.mimeType, 'image/png');
    expect(prepared.image.name, 'recipe.png');
    expect(prepared.width, 1200);
    expect(prepared.height, 800);
    expect(prepared.originalByteCount, 100 * 1024);
    expect(prepared.wasReduced, isFalse);
    expect(codec.decodeCalls.single.$2, 'image/png');
    expect(codec.encodeCalls, isEmpty);
    expect(codec.closeCount, 1);
  });

  test('reduces a large wide photo at the first rung', () async {
    final codec = FakeRecipeImageCodec(
      width: 3024,
      height: 4032,
      encodedBytesFor: (_) => _mib,
    );
    final image = _image(
      byteCount: 4 * _mib,
      mimeType: 'image/jpeg',
      name: 'IMG_0001.jpg',
    );
    final before = Uint8List.fromList(image.bytes);

    final prepared = await RecipeImageReducer(codec: codec).reduce(image);

    expect(codec.encodeCalls, [(width: 1536, height: 2048, quality: 0.85)]);
    expect(prepared.image.bytes.length, _mib);
    expect(prepared.image.mimeType, 'image/jpeg');
    expect(prepared.image.name, 'IMG_0001.jpg');
    expect(prepared.width, 1536);
    expect(prepared.height, 2048);
    expect(prepared.originalByteCount, 4 * _mib);
    expect(prepared.wasReduced, isTrue);
    expect(image.bytes, before, reason: 'the selection is never mutated');
    expect(codec.closeCount, 1);
  });

  test(
    'reduces an image within the byte limit but over the edge limit',
    () async {
      final codec = FakeRecipeImageCodec(
        width: 4000,
        height: 3000,
        encodedBytesFor: (_) => 900 * 1024,
      );

      final prepared = await RecipeImageReducer(
        codec: codec,
      ).reduce(_image(byteCount: 2 * _mib));

      expect(codec.encodeCalls, [(width: 2048, height: 1536, quality: 0.85)]);
      expect(prepared.wasReduced, isTrue);
    },
  );

  test(
    're-encodes a heavy image at its own size instead of upscaling',
    () async {
      final codec = FakeRecipeImageCodec(
        width: 1000,
        encodedBytesFor: (_) => 300 * 1024,
      );

      final prepared = await RecipeImageReducer(
        codec: codec,
      ).reduce(_image(byteCount: 5 * _mib));

      expect(codec.encodeCalls, [(width: 1000, height: 800, quality: 0.85)]);
      expect(prepared.width, 1000);
      expect(prepared.height, 800);
      expect(prepared.image.mimeType, 'image/jpeg');
      expect(prepared.wasReduced, isTrue);
    },
  );

  test('walks down the ladder until the result fits', () async {
    final codec = FakeRecipeImageCodec(
      width: 3000,
      height: 4000,
      encodedBytesFor: (call) => switch (call.height) {
        2048 => 4 * _mib,
        1600 => recipeImportMaxImageBytes + 1,
        _ => 2 * _mib,
      },
    );

    final prepared = await RecipeImageReducer(
      codec: codec,
    ).reduce(_image(byteCount: 9 * _mib, mimeType: 'image/jpeg'));

    expect(codec.encodeCalls, [
      (width: 1536, height: 2048, quality: 0.85),
      (width: 1200, height: 1600, quality: 0.80),
      (width: 960, height: 1280, quality: 0.75),
    ]);
    expect(prepared.width, 960);
    expect(prepared.height, 1280);
    expect(prepared.image.bytes.length, 2 * _mib);
    expect(codec.closeCount, 1);
  });

  test('a result exactly at the limit fits', () async {
    final codec = FakeRecipeImageCodec(
      width: 3000,
      height: 3000,
      encodedBytesFor: (_) => recipeImportMaxImageBytes,
    );

    final prepared = await RecipeImageReducer(
      codec: codec,
    ).reduce(_image(byteCount: 9 * _mib));

    expect(codec.encodeCalls, hasLength(1));
    expect(prepared.image.bytes.length, recipeImportMaxImageBytes);
  });

  test('fails as too large once the ladder is exhausted', () async {
    final codec = FakeRecipeImageCodec(
      width: 3000,
      height: 4000,
      encodedBytesFor: (_) => recipeImportMaxImageBytes + 1,
    );

    await expectLater(
      RecipeImageReducer(codec: codec).reduce(_image(byteCount: 9 * _mib)),
      throwsA(
        isA<RecipeImageReducerException>().having(
          (e) => e.failure,
          'failure',
          RecipeImageReducerFailure.tooLarge,
        ),
      ),
    );
    expect(codec.encodeCalls, hasLength(3));
    expect(codec.closeCount, 1);
  });

  test('a decode failure surfaces as undecodable', () async {
    final codec = FakeRecipeImageCodec(
      width: 0,
      height: 0,
      encodedBytesFor: (_) => fail('must not encode'),
      decodeError: StateError('not an image'),
    );

    await expectLater(
      RecipeImageReducer(codec: codec).reduce(_image()),
      throwsA(
        isA<RecipeImageReducerException>().having(
          (e) => e.failure,
          'failure',
          RecipeImageReducerFailure.undecodable,
        ),
      ),
    );
    expect(codec.closeCount, 0);
  });

  test(
    'an encode failure closes the handle and surfaces as undecodable',
    () async {
      final codec = FakeRecipeImageCodec(
        width: 3000,
        height: 3000,
        encodedBytesFor: (_) => throw StateError('canvas lost'),
      );

      await expectLater(
        RecipeImageReducer(codec: codec).reduce(_image(byteCount: 9 * _mib)),
        throwsA(
          isA<RecipeImageReducerException>().having(
            (e) => e.failure,
            'failure',
            RecipeImageReducerFailure.undecodable,
          ),
        ),
      );
      expect(codec.closeCount, 1);
    },
  );

  test('the ladder and limits are the documented constants', () {
    expect(recipeImportMaxImageEdge, 2048);
    expect(recipeImageReductionLadder, [
      (longestEdge: 2048, quality: 0.85),
      (longestEdge: 1600, quality: 0.80),
      (longestEdge: 1280, quality: 0.75),
    ]);
    expect(
      const RecipeImageReducerException(
        RecipeImageReducerFailure.tooLarge,
      ).toString(),
      'RecipeImageReducerException(tooLarge)',
    );
  });
}
