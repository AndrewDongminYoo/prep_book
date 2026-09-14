import 'package:prep_book/championship/input/recipe_import_request.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';

abstract interface class RecipeImportClient {
  Future<ExtractedRecipeDraft> extract(
    RecipeImportRequest request, {
    required String locale,
  });
}

enum RecipeImportFailureCode {
  methodNotAllowed('method_not_allowed'),
  invalidContentType('invalid_content_type'),
  invalidRequest('invalid_request'),
  unsupportedSource('unsupported_source'),
  sourceTooLarge('source_too_large'),
  serviceUnconfigured('service_unconfigured'),
  serviceBusy('service_busy'),
  serviceTimeout('service_timeout'),
  invalidModelOutput('invalid_model_output'),
  serviceFailure('service_failure');

  const RecipeImportFailureCode(this.wireName);

  final String wireName;

  static RecipeImportFailureCode? fromWireName(String wireName) {
    for (final code in values) {
      if (code.wireName == wireName) return code;
    }
    return null;
  }
}

final class RecipeImportException implements Exception {
  const RecipeImportException(this.code, this.message);

  final RecipeImportFailureCode code;
  final String message;

  @override
  String toString() => 'RecipeImportException(${code.wireName})';
}
