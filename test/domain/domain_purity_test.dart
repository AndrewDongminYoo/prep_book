import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `package:` prefixes a domain file may import or export. Everything else —
/// including any `dart:` entry — is disallowed by default; a later task that
/// genuinely needs one must widen this list deliberately.
const _allowedPackagePrefixes = <String>[
  'package:decimal/',
  'package:rational/',
  'package:meta/',
  'package:prep_book/domain/',
];

/// Matches a whole `import`/`export` directive, from the keyword to its
/// terminating `;`. A conditional directive
/// (`export 'a.dart' if (dart.library.io) 'b.dart';`) carries more than one
/// quoted URI, so the directive is captured whole and every quoted URI
/// inside it is checked — not just the first.
final _directiveStatement = RegExp(r'\b(?:import|export)\b[^;]*;');

/// Matches one quoted URI, either quote style.
final _quotedUri = RegExp("'([^']*)'|\"([^\"]*)\"");

final _lineComment = RegExp(r'//[^\n]*');

// Deliberately excludes newline from the string body: a triple-quoted
// string then survives stripping only partially, which can under-strip
// (false positive, a loud failure to investigate) but can never
// over-strip past a line comment's stray apostrophe and swallow real code
// (false negative, a silent pass). Do not widen this to span newlines.
final _stringLiteral = RegExp(
  r'''r?'(?:[^'\\\n]|\\.)*'|r?"(?:[^"\\\n]|\\.)*"''',
);
// Catches both the decimal-point form (`1.5`, and `1.5e10` with an
// exponent) and the exponent-only form (`1e10`) — Dart infers a `double`
// for either shape. A plain integer literal (`1000`) matches neither
// alternative and must keep passing.
final _floatLiteral = RegExp(
  r'\b\d+\.\d+(?:[eE][+-]?\d+)?\b|\b\d+[eE][+-]?\d+\b',
);
final _doubleKeyword = RegExp(r'\bdouble\b');

/// Plain substrings that must never appear in a domain file, checked
/// against the raw, unstripped source as a second, independent gate. The
/// allowlist above is the primary check; this denylist is deliberately
/// redundant so that anything which slips past the directive parser (e.g.
/// a comment that hides a real semicolon) is still caught by a search that
/// cannot be fooled by parsing tricks. Accepted tradeoff: a banned name
/// appearing inside a domain string literal would also trip this gate —
/// a false positive, which is loud and gets reworded, never a silent pass.
const _bannedSubstrings = <String>[
  'package:flutter/',
  'package:flutter_bloc/',
  'dart:io',
  'dart:ui',
  'package:sqflite',
  'package:pdf',
  'package:http',
];

/// Blanks out string contents and line comments so a legitimate string
/// (e.g. `Decimal.parse('0.001')`) or a dartdoc comment cannot trip the
/// numeric scans below.
String _stripCommentsAndStrings(String source) {
  final withoutStrings = source.replaceAll(_stringLiteral, "''");
  return withoutStrings.replaceAll(_lineComment, '');
}

/// A `package:` URI must start with an allowed prefix. A relative URI may
/// only refer to a sibling inside `lib/domain/`, never escape it via `../`.
bool _isAllowedUri(String uri) {
  if (_allowedPackagePrefixes.any(uri.startsWith)) return true;
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return false;
  return !uri.contains('../');
}

List<File> _dartFilesUnder(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
}

void main() {
  test(
    'every domain import or export resolves inside the domain boundary',
    () {
      final domain = Directory('lib/domain');
      expect(domain.existsSync(), isTrue, reason: 'lib/domain must exist');

      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib/domain')) {
        final source = file.readAsStringSync();
        for (final statement in _directiveStatement.allMatches(source)) {
          final text = statement.group(0)!;
          for (final match in _quotedUri.allMatches(text)) {
            final uri = match.group(1) ?? match.group(2)!;
            if (!_isAllowedUri(uri)) {
              offenders.add('${file.path} references disallowed uri: $uri');
            }
          }
        }
      }

      expect(offenders, isEmpty);
    },
  );

  test(
    'no domain or test source uses double or a floating-point literal',
    () {
      final files = [
        ..._dartFilesUnder('lib/domain'),
        ..._dartFilesUnder('test/domain').where(
          // Excludes this file itself, which necessarily names what it bans.
          (file) => !file.path.endsWith('domain_purity_test.dart'),
        ),
      ];

      final offenders = <String>[];
      for (final file in files) {
        final stripped = _stripCommentsAndStrings(file.readAsStringSync());
        if (_doubleKeyword.hasMatch(stripped) ||
            _floatLiteral.hasMatch(stripped)) {
          offenders.add(file.path);
        }
      }

      expect(offenders, isEmpty);
    },
  );

  test(
    'no domain source contains a banned substring (denylist backstop)',
    () {
      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib/domain')) {
        final source = file.readAsStringSync();
        for (final banned in _bannedSubstrings) {
          if (source.contains(banned)) {
            offenders.add('${file.path} contains banned substring: $banned');
          }
        }
      }

      expect(offenders, isEmpty);
    },
  );
}
