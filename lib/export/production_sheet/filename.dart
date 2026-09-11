import 'package:prep_book/domain/production_run.dart';

final _unsafeCharacters = RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|]');
final _whitespace = RegExp(r'\s+');
final _repeatedHyphens = RegExp('-+');
final _edgePunctuation = RegExp(r'^[.\s-]+|[.\s-]+$');

/// Creates the deterministic PDF filename for one stored production run.
String buildProductionSheetFilename(ProductionRun run) {
  final normalized = run.recipe.name
      .replaceAll(_unsafeCharacters, '-')
      .replaceAll(_whitespace, '-')
      .replaceAll(_repeatedHyphens, '-')
      .replaceAll(_edgePunctuation, '');
  final limited = String.fromCharCodes(
    normalized.runes.take(80),
  ).replaceAll(_edgePunctuation, '');
  final recipeSegment = limited.isEmpty ? 'production-run' : limited;
  final createdAt = run.createdAt.toUtc();
  final timestamp =
      '${_four(createdAt.year)}'
      '${_two(createdAt.month)}'
      '${_two(createdAt.day)}T'
      '${_two(createdAt.hour)}'
      '${_two(createdAt.minute)}'
      '${_two(createdAt.second)}Z';
  return 'production-sheet-$recipeSegment-$timestamp.pdf';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _four(int value) => value.toString().padLeft(4, '0');
