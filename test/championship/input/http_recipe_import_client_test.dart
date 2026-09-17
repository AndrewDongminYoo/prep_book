import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prep_book/championship/input/http_recipe_import_client.dart';
import 'package:prep_book/championship/input/recipe_import_client.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';

Map<String, Object?> _draftJson() {
  final json = jsonDecode(
    File(
      'assets/championship/sample_croissant_draft.json',
    ).readAsStringSync(),
  ) as Map<String, Object?>;
  return {...json, 'sourceKind': 'text'};
}

void main() {
  const endpoint = 'https://demo.example/api/extract-recipe';

  test('posts one exact JSON request without provider authorization', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls += 1;
      expect(request.method, 'POST');
      expect(request.url, Uri.parse(endpoint));
      expect(request.headers['authorization'], isNull);
      expect(request.headers['content-type'], startsWith('application/json'));
      expect(jsonDecode(request.body), {
        'sourceKind': 'text',
        'text': 'Dough\nFlour 100 g',
        'imageDataUrl': null,
        'locale': 'en',
      });
      return http.Response(jsonEncode(_draftJson()), 200);
    });
    final importClient = HttpRecipeImportClient(
      client: client,
      endpoint: Uri.parse(endpoint),
    );

    final draft = await importClient.extract(
      TextRecipeImportRequest('Dough\nFlour 100 g'),
      locale: 'en',
    );

    expect(calls, 1);
    expect(draft.sourceKind.name, 'text');
    expect(draft.recipe.name.value, 'Croissant dough');
  });

  test('maps every stable endpoint error without retrying', () async {
    const stableErrors = [
      (RecipeImportFailureCode.methodNotAllowed, 'method_not_allowed'),
      (RecipeImportFailureCode.invalidContentType, 'invalid_content_type'),
      (RecipeImportFailureCode.invalidRequest, 'invalid_request'),
      (RecipeImportFailureCode.unsupportedSource, 'unsupported_source'),
      (RecipeImportFailureCode.sourceTooLarge, 'source_too_large'),
      (RecipeImportFailureCode.serviceUnconfigured, 'service_unconfigured'),
      (RecipeImportFailureCode.serviceBusy, 'service_busy'),
      (RecipeImportFailureCode.serviceTimeout, 'service_timeout'),
      (RecipeImportFailureCode.invalidModelOutput, 'invalid_model_output'),
      (RecipeImportFailureCode.serviceFailure, 'service_failure'),
    ];
    for (final (code, wireCode) in stableErrors) {
      var calls = 0;
      final client = MockClient((_) async {
        calls += 1;
        return http.Response(
          jsonEncode({
            'error': {'code': wireCode, 'message': 'Safe message.'},
          }),
          400,
        );
      });
      final importClient = HttpRecipeImportClient(
        client: client,
        endpoint: Uri.parse(endpoint),
      );

      await expectLater(
        importClient.extract(TextRecipeImportRequest('Dough'), locale: 'ko'),
        throwsA(
          isA<RecipeImportException>()
              .having((error) => error.code, 'code', code)
              .having((error) => error.message, 'message', 'Safe message.'),
        ),
      );
      expect(calls, 1);
    }
  });

  test('rejects malformed success output as invalid model output', () async {
    final importClient = HttpRecipeImportClient(
      client: MockClient(
        (_) async => http.Response('{"schemaVersion":1}', 200),
      ),
      endpoint: Uri.parse(endpoint),
    );

    await expectLater(
      importClient.extract(TextRecipeImportRequest('Dough'), locale: 'en'),
      throwsA(
        isA<RecipeImportException>().having(
          (error) => error.code,
          'code',
          RecipeImportFailureCode.invalidModelOutput,
        ),
      ),
    );
  });

  test('times out once without an automatic retry', () async {
    var calls = 0;
    final client = MockClient((_) {
      calls += 1;
      return Completer<http.Response>().future;
    });
    final importClient = HttpRecipeImportClient(
      client: client,
      endpoint: Uri.parse(endpoint),
      timeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      importClient.extract(TextRecipeImportRequest('Dough'), locale: 'en'),
      throwsA(
        isA<RecipeImportException>().having(
          (error) => error.code,
          'code',
          RecipeImportFailureCode.serviceTimeout,
        ),
      ),
    );
    expect(calls, 1);
  });

  test(
    'maps transport and malformed error responses to service failure',
    () async {
      for (final client in [
        MockClient((_) async => throw const SocketException('offline')),
        MockClient((_) async => http.Response('{"error":{}}', 500)),
      ]) {
        final importClient = HttpRecipeImportClient(
          client: client,
          endpoint: Uri.parse(endpoint),
        );

        await expectLater(
          importClient.extract(TextRecipeImportRequest('Dough'), locale: 'en'),
          throwsA(
            isA<RecipeImportException>().having(
              (error) => error.code,
              'code',
              RecipeImportFailureCode.serviceFailure,
            ),
          ),
        );
      }
    },
  );
}
