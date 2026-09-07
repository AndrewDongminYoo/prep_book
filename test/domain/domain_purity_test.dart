import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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

/// Reports every prohibited floating-point construct in [source], one
/// description per finding, or an empty list when the source is clean.
///
/// Walks the parsed syntax tree rather than matching patterns against text.
/// Six of this guard's eleven historical bypasses were text-handling failures
/// — an apostrophe in prose, a semicolon in a comment, a literal shape the
/// pattern did not anticipate, an expression hidden inside a string
/// interpolation — and the tree removes that whole class rather than one
/// alternation at a time. Comments are absent from the tree, so they cannot
/// produce a finding; the body of a string is likewise absent, while an
/// interpolated expression is a real child node and is visited like any other
/// code.
///
/// Takes source text rather than a file so that every bypass, past and future,
/// can be pinned by a test that plants the construct directly. A reading of
/// this guard has never caught one of its own holes; only planting has.
List<String> findNumericViolations(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  if (parsed.errors.isNotEmpty) {
    // Fail closed. Source that does not parse has not been checked, and
    // reporting it clean would be the silent pass this guard exists to stop.
    return ['does not parse, so it was never checked: ${parsed.errors.first}'];
  }

  final visitor = _NumericVisitor();
  parsed.unit.visitChildren(visitor);
  return visitor.violations;
}

class _NumericVisitor extends RecursiveAstVisitor<void> {
  final violations = <String>[];

  @override
  void visitDoubleLiteral(DoubleLiteral node) {
    // Every literal Dart infers as binary floating point arrives here,
    // whatever its written shape: 1.5, .5, 1e10, 1.5e-3, 1_000.5.
    violations.add('floating-point literal: $node');
    super.visitDoubleLiteral(node);
  }

  @override
  void visitNamedType(NamedType node) {
    if (node.name.lexeme == 'double') {
      violations.add('binary floating-point type: $node');
    }
    super.visitNamedType(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // Catches the type used as a value rather than as an annotation, such as
    // a static call on it. A type annotation arrives as a NamedType instead,
    // so the two overrides do not double-report the same occurrence.
    if (node.name == 'double') {
      violations.add('binary floating-point type: $node');
    }
    super.visitSimpleIdentifier(node);
  }
}

/// Divisions under [directories] whose resolved result is a `double`, which is
/// every division Dart evaluates as binary floating point.
///
/// Resolves the sources rather than parsing them, and reads the result type
/// rather than the receiver's. `Rational`'s own division returns a `Rational`,
/// so exact arithmetic is excluded by the very test that reports numeric
/// division, with no special case naming it.
///
/// That is what the parsed version could never do. It spent six review rounds
/// approximating "is this receiver a number" and still could not see an
/// identifier, a method's return type, a getter, or a type parameter bounded
/// by `num`.
///
/// Fails closed: a file that does not resolve is itself reported, and so is any
/// expected file the resolver never reached. "Nothing was checked" must never
/// look like "nothing was wrong" — this repository has already met that shape
/// once, when cspell reported zero issues from zero files checked.
Future<List<String>> findDivisionViolations(List<String> directories) async {
  final expected = directories
      .expand(_dartFilesUnder)
      .map((file) => file.absolute.path)
      .toSet();

  final collection = AnalysisContextCollection(
    includedPaths: directories
        .map((path) => Directory(path).absolute.path)
        .toList(),
    sdkPath: _dartSdkPath(),
  );

  final violations = <String>[];
  final resolvedPaths = <String>{};

  for (final context in collection.contexts) {
    for (final path in context.contextRoot.analyzedFiles()) {
      if (!path.endsWith('.dart')) continue;
      final result = await context.currentSession.getResolvedUnit(path);
      if (result is! ResolvedUnitResult) {
        violations.add(
          '$path did not resolve (${result.runtimeType}), '
          'so it was never checked',
        );
        continue;
      }
      resolvedPaths.add(result.path);
      final visitor = _DivisionVisitor(result.path);
      result.unit.visitChildren(visitor);
      violations.addAll(visitor.violations);
    }
  }

  final unreached = expected.difference(resolvedPaths);
  if (unreached.isNotEmpty) {
    violations.add(
      '${unreached.length} of ${expected.length} expected files were never '
      'resolved, so this is not a clean result: '
      '${unreached.take(3).join(', ')}',
    );
  }

  return violations;
}

/// Locates the Dart SDK that `flutter test` runs against.
///
/// The analyzer's own discovery reads `Platform.resolvedExecutable`, which here
/// is `flutter_tester` rather than a Dart binary, and dies inside SDK
/// construction with a `PathNotFoundException` on `libraries.dart`. So the path
/// is passed explicitly, and `FLUTTER_ROOT` is the only reliable source for it
/// in this environment.
///
/// Its absence throws rather than falling back. A guard that cannot read the
/// SDK cannot read anything, and must not answer "clean".
String _dartSdkPath() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null || root.isEmpty) {
    throw StateError(
      'FLUTTER_ROOT is unset, so no Dart SDK can be located and nothing can '
      'be resolved. Refusing to report a clean result.',
    );
  }
  final sdk = '$root/bin/cache/dart-sdk';
  if (!Directory(sdk).existsSync()) {
    throw StateError(
      'No Dart SDK at $sdk, so nothing can be resolved. '
      'Refusing to report a clean result.',
    );
  }
  return sdk;
}

class _DivisionVisitor extends RecursiveAstVisitor<void> {
  _DivisionVisitor(this.path);

  final String path;
  final violations = <String>[];

  @override
  void visitBinaryExpression(BinaryExpression node) {
    // Read the result type, not the receiver's. `num./` is declared to return
    // a `double`, so the resolved result answers the question directly, and
    // `Rational.\/` — which returns a `Rational` — is excluded by the same
    // test rather than by a special case naming it.
    //
    // Asking about the receiver instead means enumerating which types count,
    // and that enumeration is never finished: a receiver typed by a parameter
    // bounded by `num` is none of `num`, `int` or `double`, yet member lookup
    // goes through the bound and the division still produces a double.
    if (node.operator.type == TokenType.SLASH) {
      final result = node.staticType;
      if (result != null && result.isDartCoreDouble) {
        violations.add('$path: division yields a double: $node');
      }
    }
    super.visitBinaryExpression(node);
  }
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
  // The forms issue #5 recorded as beyond a parser's reach. Each is planted in
  // a real file, because resolution needs one — a source string has no types.
  // One resolution serves the whole group; it costs about a second.
  group('findDivisionViolations resolves what parsing could not', () {
    const probeDirectory = 'test/_division_probe';
    late List<String> violations;

    setUpAll(() async {
      Directory(probeDirectory).createSync(recursive: true);
      File('$probeDirectory/probe.dart').writeAsStringSync('''
import 'package:rational/rational.dart';

int counter() => 3;
int get batches => 4;

final byMethodReturn = 1 / counter();
final byIdentifier = counter() / 3;
final byStaticMethod = int.parse('1') / 3;
final byGetter = batches / 3;
final byNullAssertion = (counter() as int?)! / 3;
final byNullCoalescing = ((counter() as int?) ?? 0) / 3;

num byTypeParameter<T extends num>(T value) => value / 2;

Rational exact(Rational a, Rational b) => a / b;
''');
      violations = await findDivisionViolations([probeDirectory]);
    });

    tearDownAll(() {
      Directory(probeDirectory).deleteSync(recursive: true);
    });

    test("a method's return type", () {
      expect(violations, contains(contains('1 / counter()')));
    });

    test('an identifier resolved through a function call', () {
      expect(violations, contains(contains('counter() / 3')));
    });

    test("a static method's return type", () {
      expect(violations, contains(contains("int.parse('1') / 3")));
    });

    test('a getter', () {
      expect(violations, contains(contains('batches / 3')));
    });

    test('a null assertion', () {
      expect(violations, contains(contains('(counter() as int?)! / 3')));
    });

    test('a null-coalescing receiver', () {
      expect(violations, contains(contains('?? 0) / 3')));
    });

    test('a receiver whose type is a parameter bounded by num', () {
      // `T extends num` is not `num`, `int` or `double`, but member lookup
      // goes through the bound, so `/` still produces a double.
      expect(violations, contains(contains('value / 2')));
    });

    test('and leaves an exact Rational division alone', () {
      // The control. Resolution excludes this by its type, where every
      // syntactic version had to approximate it.
      expect(violations, isNot(contains(contains('a / b'))));
    });
  });

  // Every literal-shaped bypass this guard has had is pinned here as a planted
  // construct. A reading of the patterns never caught one; only planting did.
  // Division is not here: it needs types, and lives in the resolved gate above.
  group('findNumericViolations detects', () {
    test('a plain decimal literal', () {
      expect(findNumericViolations('final a = 1.5;'), isNotEmpty);
    });

    test('an exponent-only literal', () {
      expect(findNumericViolations('final a = 1e10;'), isNotEmpty);
    });

    test('a leading-dot literal, which Dart accepts as a double', () {
      expect(findNumericViolations('final a = .5;'), isNotEmpty);
    });

    test('a float literal inside a string interpolation', () {
      expect(
        findNumericViolations(r"String f(int x) => 'value ${1.5 * x}';"),
        isNotEmpty,
      );
    });

    test('the binary floating-point type in a signature', () {
      expect(findNumericViolations('double f() => 0;'), isNotEmpty);
    });

    test('the binary floating-point type as a static receiver', () {
      expect(findNumericViolations("final a = double.parse('1');"), isNotEmpty);
    });
  });

  group('findNumericViolations accepts', () {
    test('an integer literal', () {
      expect(findNumericViolations('final a = 1000;'), isEmpty);
    });

    test('digits inside a string, so Decimal.parse stays usable', () {
      expect(findNumericViolations("final a = P.parse('0.001');"), isEmpty);
    });

    test('a decimal in a line comment', () {
      expect(findNumericViolations('// 2.5 in prose\nfinal a = 1;'), isEmpty);
    });

    test('a decimal in a block comment', () {
      expect(findNumericViolations('/* 2.5 */\nfinal a = 1;'), isEmpty);
    });

    test('a decimal in a doc comment', () {
      expect(findNumericViolations('/// 2.5 in prose\nfinal a = 1;'), isEmpty);
    });

    test('a method call on an integer literal, which is not a double', () {
      // `1.abs()` must not be read as the double literal `1.`.
      expect(findNumericViolations('final a = 1.abs();'), isEmpty);
    });
  });

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
        for (final violation in findNumericViolations(
          file.readAsStringSync(),
        )) {
          offenders.add('${file.path}: $violation');
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

  test(
    'no domain source divides a number',
    () async {
      // The one gate that resolves rather than parses, and the only check
      // here that tells a `Rational` division from a numeric one exactly.
      //
      // Scoped to `lib/domain` alone, unlike the scans above. The invariant
      // is about domain arithmetic, and resolution is not free: measured on
      // this machine `lib/domain` costs about 1.5 seconds, while adding
      // `test/domain` took the whole suite from roughly 3 seconds to 21.
      // Test sources stay covered for `double` literals and the `double`
      // type by the parsed scan, which is where a test would realistically
      // introduce one.
      final violations = await findDivisionViolations(['lib/domain']);

      expect(violations, isEmpty);
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
