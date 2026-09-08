import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `package:`/`dart:` prefixes a `lib/application/` source may import or
/// export. Everything else is disallowed by default; a later task that
/// genuinely needs one must widen this list deliberately.
const _allowedUriPrefixes = <String>[
  'package:prep_book/domain/',
  'package:prep_book/persistence/repositories.dart',
  'package:prep_book/application/',
  'package:meta/',
  'dart:',
];

/// Matches a whole `import`/`export` directive, from the keyword to its
/// terminating `;`. A conditional directive
/// (`export 'a.dart' if (dart.library.io) 'b.dart';`) carries more than one
/// quoted URI, so the directive is captured whole and every quoted URI
/// inside it is checked — not just the first. Reuses the shape of
/// `test/domain/domain_purity_test.dart`'s import-allowlist check.
final _directiveStatement = RegExp(r'\b(?:import|export)\b[^;]*;');

/// Matches one quoted URI, either quote style.
final _quotedUri = RegExp("'([^']*)'|\"([^\"]*)\"");

/// A `package:`/`dart:` URI must start with an allowed prefix. A relative
/// URI may only refer to a sibling inside `lib/application/`, never escape
/// it via `../`.
bool _isAllowedUri(String uri) {
  if (_allowedUriPrefixes.any(uri.startsWith)) return true;
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
    'every application import or export resolves inside the allowed set',
    () {
      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib/application')) {
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
}
