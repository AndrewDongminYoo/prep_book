import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `package:` prefixes a `lib/presentation/` source may import or export.
/// Everything else is disallowed by default; a later screen that genuinely
/// needs one must widen this list deliberately.
///
/// `package:prep_book/persistence/` is absent on purpose. The screen reads
/// through the application layer's use cases, so a repository type never
/// appears here — that is what makes the boundary true rather than merely
/// documented.
///
/// `dart:async` is here for `unawaited`, which the screen needs to start
/// its first read without awaiting it.
const _allowedUriPrefixes = <String>[
  'dart:async',
  'dart:typed_data',
  'package:pdf/',
  'package:prep_book/application/',
  'package:prep_book/domain/',
  'package:prep_book/l10n/',
  'package:prep_book/presentation/',
  'package:bloc/',
  'package:flutter/',
  'package:flutter_bloc/',
  'package:intl/',
  'package:meta/',
  'package:printing/',
  'package:prep_book/export/',
];

/// Matches a whole `import`/`export` directive, from the keyword to its
/// terminating `;`. A conditional directive
/// (`export 'a.dart' if (dart.library.io) 'b.dart';`) carries more than one
/// quoted URI, so the directive is captured whole and every quoted URI
/// inside it is checked — not just the first. Ported from
/// `test/application/application_boundary_test.dart`, which ported it from
/// `test/domain/domain_purity_test.dart`.
final _directiveStatement = RegExp(r'\b(?:import|export)\b[^;]*;');

/// Matches one quoted URI, either quote style.
final _quotedUri = RegExp("'([^']*)'|\"([^\"]*)\"");

/// A `package:`/`dart:` URI must start with an allowed prefix. A relative
/// URI may only refer to a sibling inside `lib/presentation/`, never escape
/// it via `../`.
bool _isAllowedUri(String uri) {
  if (_allowedUriPrefixes.any(uri.startsWith)) return true;
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return false;
  return !uri.contains('../');
}

/// Plain substrings that must never appear in a presentation source,
/// checked against the raw, unstripped source as a second, independent
/// gate.
///
/// The allowlist above is the primary check; this denylist is deliberately
/// redundant, because the allowlist alone was demonstrably bypassable on
/// the application branch: an apostrophe in a doc comment above a forbidden
/// directive pairs with that directive's opening quote, so
/// [_directiveStatement] captures a span whose first quoted "URI" is the
/// prose between them and the real URI is never extracted. A raw substring
/// search cannot be fooled that way. Do not remove either gate, and do not
/// merge the pair into one.
///
/// `prep_book/persistence/sqflite/` is subsumed by the broader
/// `prep_book/persistence/` and is listed anyway, so the guard reads as the
/// requirement it implements. `RecipeRepository` is here because the brief
/// forbids the screen naming it even in prose, which no import check could
/// catch.
///
/// Accepted tradeoff, inherited from the two guards this one is ported
/// from: a banned name inside a presentation string literal or comment
/// trips this gate too — a false positive, which is loud and gets reworded,
/// never a silent pass.
const _bannedSubstrings = <String>[
  'package:sqflite',
  'prep_book/persistence/',
  'prep_book/persistence/sqflite/',
  'RecipeRepository',
];

/// Every `.dart` file directly or transitively under [path].
///
/// Asserts [path] exists rather than silently answering "nothing here" for
/// a directory that isn't there. Both scans below share this helper, and a
/// missing directory must fail loudly for either of them — reporting a
/// non-existent tree as clean is the vacuity hole that made an earlier
/// version of this guard scan zero files.
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
  test('the guard scans the presentation sources that exist', () {
    // Without this, both gates below pass vacuously the day a rename
    // empties the directory they read.
    expect(_dartFilesUnder('lib/presentation'), isNotEmpty);
  });

  test(
    'every presentation import or export resolves inside the allowed set',
    () {
      final offenders = <String>[];
      for (final file in _dartFilesUnder('lib/presentation')) {
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

  test('no presentation source contains a banned substring (denylist)', () {
    final offenders = <String>[];
    for (final file in _dartFilesUnder('lib/presentation')) {
      final source = file.readAsStringSync();
      for (final banned in _bannedSubstrings) {
        if (source.contains(banned)) {
          offenders.add('${file.path} contains banned substring: $banned');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
