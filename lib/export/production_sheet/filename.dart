import 'package:prep_book/domain/production_run.dart';

const _filenameMaxBytes = 255;
const _recipeMaxCodePoints = 80;
const _prefix = 'production-sheet-';
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
  final createdAt = run.createdAt.toUtc();
  final timestamp =
      '${_four(createdAt.year)}'
      '${_two(createdAt.month)}'
      '${_two(createdAt.day)}T'
      '${_two(createdAt.hour)}'
      '${_two(createdAt.minute)}'
      '${_two(createdAt.second)}Z';
  final suffix = '-$timestamp.pdf';
  final recipeByteLimit = _filenameMaxBytes - '$_prefix$suffix'.length;
  final codePointLimited = String.fromCharCodes(
    normalized.runes.take(_recipeMaxCodePoints),
  );
  final limited = _limitUtf8Bytes(
    codePointLimited,
    recipeByteLimit,
  ).replaceAll(_edgePunctuation, '');
  final recipeSegment = limited.isEmpty ? 'production-run' : limited;
  return '$_prefix$recipeSegment$suffix';
}

String _limitUtf8Bytes(String value, int maxBytes) {
  final result = <int>[];
  var byteCount = 0;
  for (final rune in value.runes) {
    final runeBytes = _utf8ByteLength(rune);
    if (byteCount + runeBytes > maxBytes) break;
    result.add(rune);
    byteCount += runeBytes;
  }
  return String.fromCharCodes(result);
}

int _utf8ByteLength(int rune) {
  if (rune <= 0x7f) return 1;
  if (rune <= 0x7ff) return 2;
  if (rune <= 0xffff) return 3;
  return 4;
}

String _two(int value) => value.toString().padLeft(2, '0');

String _four(int value) => value.toString().padLeft(4, '0');
