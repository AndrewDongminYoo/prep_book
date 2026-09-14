import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';

void main() {
  group('TextRecipeImportRequest', () {
    test('preserves source text and emits the exact endpoint shape', () {
      const source = '  Dough\nFlour 100 g  ';
      final request = TextRecipeImportRequest(source);

      expect(request.text, source);
      expect(request.toJson('en'), {
        'sourceKind': 'text',
        'text': source,
        'imageDataUrl': null,
        'locale': 'en',
      });
    });

    test('accepts exactly 20,000 Unicode scalar values', () {
      final request = TextRecipeImportRequest('🥐' * 20000);

      expect((request.toJson('ko')['text']! as String).runes.length, 20000);
    });

    test('rejects blank and over-limit text', () {
      expect(() => TextRecipeImportRequest(' \n\t '), throwsArgumentError);
      expect(() => TextRecipeImportRequest('🥐' * 20001), throwsArgumentError);
    });
  });

  group('ImageRecipeImportRequest', () {
    test('encodes copied bytes only when serialized', () {
      final source = Uint8List.fromList([1, 2, 3]);
      final request = ImageRecipeImportRequest(
        bytes: source,
        mimeType: 'image/png',
      );
      source[0] = 9;

      expect(request.toJson('ko'), {
        'sourceKind': 'image',
        'text': null,
        'imageDataUrl': 'data:image/png;base64,AQID',
        'locale': 'ko',
      });
      expect(base64Decode('AQID'), [1, 2, 3]);
    });

    test('accepts every supported MIME type at the exact size limit', () {
      for (final mimeType in const ['image/jpeg', 'image/png', 'image/webp']) {
        final request = ImageRecipeImportRequest(
          bytes: Uint8List(recipeImportMaxImageBytes),
          mimeType: mimeType,
        );

        expect(request.mimeType, mimeType);
      }
    });

    test('rejects empty, unsupported, and over-limit image data', () {
      expect(
        () => ImageRecipeImportRequest(
          bytes: Uint8List(0),
          mimeType: 'image/png',
        ),
        throwsArgumentError,
      );
      expect(
        () => ImageRecipeImportRequest(
          bytes: Uint8List.fromList([1]),
          mimeType: 'image/heic',
        ),
        throwsArgumentError,
      );
      expect(
        () => ImageRecipeImportRequest(
          bytes: Uint8List(recipeImportMaxImageBytes + 1),
          mimeType: 'image/png',
        ),
        throwsArgumentError,
      );
    });
  });

  test('rejects unsupported locales for either request kind', () {
    expect(
      () => TextRecipeImportRequest('Dough').toJson('fr'),
      throwsArgumentError,
    );
    expect(
      () => ImageRecipeImportRequest(
        bytes: Uint8List.fromList([1]),
        mimeType: 'image/png',
      ).toJson('fr'),
      throwsArgumentError,
    );
  });
}
