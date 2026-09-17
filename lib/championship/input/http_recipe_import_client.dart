import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:prep_book/championship/input/recipe_import_client.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';

final class HttpRecipeImportClient implements RecipeImportClient {
  const new({
    required http.Client client,
    required Uri endpoint,
    Duration timeout = const Duration(seconds: 27),
  }) : _config = (client: client, endpoint: endpoint, timeout: timeout);

  final ({http.Client client, Uri endpoint, Duration timeout}) _config;

  @override
  Future<ExtractedRecipeDraft> extract(
    RecipeImportRequest request, {
    required String locale,
  }) async {
    try {
      final response = await _config.client
          .post(
            _config.endpoint,
            headers: const {'content-type': 'application/json'},
            body: jsonEncode(request.toJson(locale)),
          )
          .timeout(_config.timeout);
      if (response.statusCode != 200) {
        throw _errorFrom(response);
      }
      return _draftFrom(response);
    } on RecipeImportException {
      rethrow;
    } on TimeoutException {
      throw const RecipeImportException(
        RecipeImportFailureCode.serviceTimeout,
        'The extraction request timed out.',
      );
    } on Object {
      throw const RecipeImportException(
        RecipeImportFailureCode.serviceFailure,
        'The extraction service could not complete the request.',
      );
    }
  }
}

ExtractedRecipeDraft _draftFrom(http.Response response) {
  try {
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<String, Object?>) throw const FormatException();
    return ExtractedRecipeDraft.fromJson(value);
  } on Object {
    throw const RecipeImportException(
      RecipeImportFailureCode.invalidModelOutput,
      'The extraction result was invalid.',
    );
  }
}

RecipeImportException _errorFrom(http.Response response) {
  try {
    final value = jsonDecode(utf8.decode(response.bodyBytes));
    if (value is! Map<String, Object?>) throw const FormatException();
    final error = value['error'];
    if (error is! Map<String, Object?>) throw const FormatException();
    final wireCode = error['code'];
    final message = error['message'];
    if (wireCode is! String || message is! String || message.trim().isEmpty) {
      throw const FormatException();
    }
    final code = RecipeImportFailureCode.fromWireName(wireCode);
    if (code == null) throw const FormatException();
    return RecipeImportException(code, message);
  } on RecipeImportException {
    rethrow;
  } on Object {
    return const RecipeImportException(
      RecipeImportFailureCode.serviceFailure,
      'The extraction service could not complete the request.',
    );
  }
}
