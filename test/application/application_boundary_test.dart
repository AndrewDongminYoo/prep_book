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

/// Plain substrings that must never appear in an application-layer source,
/// checked against the raw, unstripped source as a second, independent
/// gate. The allowlist above is the primary check; this denylist is
/// deliberately redundant so that anything which slips past the directive
/// parser — such as an apostrophe in a doc comment pairing with a directive's
/// opening quote and hiding the whole `import` from `_directiveStatement` —
/// is still caught by a search that cannot be fooled by parsing tricks.
/// Accepted tradeoff: a banned name appearing inside an application string
/// literal would also trip this gate — a false positive, which is loud and
/// gets reworded, never a silent pass. Mirrors
/// `test/domain/domain_purity_test.dart`'s denylist.
const _bannedSubstrings = <String>[
  'package:flutter/',
  'package:sqflite',
  'prep_book/persistence/sqflite/',
];

/// Every `.dart` file directly or transitively under [path].
///
/// Asserts [path] exists rather than silently answering "nothing here" for
/// a directory that isn't there. Both scans below share this helper, and a
/// missing directory must fail loudly for either of them — reporting a
/// non-existent tree as clean is the exact vacuity hole an earlier fix round
/// closed for the allowlist scan alone.
List<File> _dartFilesUnder(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    throw StateError('$path does not exist, so nothing was checked.');
  }
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

  test(
    'no application source contains a banned substring (denylist backstop)',
    () {
      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib/application')) {
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
