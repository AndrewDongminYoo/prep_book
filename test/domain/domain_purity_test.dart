import 'dart:io';

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

/// Unwraps redundant parentheses so `(1) / (3)` is recognised as the integer
/// division it is.
Expression _unparenthesized(Expression expression) {
  var current = expression;
  while (current is ParenthesizedExpression) {
    current = current.expression;
  }
  return current;
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

  @override
  void visitBinaryExpression(BinaryExpression node) {
    // In Dart `/` always yields a double, including between two integers;
    // `~/` is the truncating one. The left operand selects the operator, so
    // an integer literal there means `int./` and therefore a double, whatever
    // the right operand turns out to be. That is safe against the domain's own
    // divisions without needing types: an integer literal cannot be the left
    // operand of a Rational division at all, because Rational is not a `num`
    // and the analyzer rejects it outright.
    //
    // The converse does not hold. A literal on the right says nothing about
    // the left operand's type, and the domain divides Rationals at six call
    // sites, so requiring a literal there would report every one of them. Both
    // directions are pinned by tests.
    if (node.operator.type == TokenType.SLASH &&
        _unparenthesized(node.leftOperand) is IntegerLiteral) {
      violations.add('integer division yields a double: $node');
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
  // Every bypass this guard has had is pinned here as a planted construct.
  // A reading of the patterns has never caught one; only planting has.
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

    test('an integer divided by an integer, which yields a double', () {
      expect(findNumericViolations('final a = 1 / 3;'), isNotEmpty);
    });

    test('an integer division wrapped in parentheses', () {
      expect(findNumericViolations('final a = (1) / (3);'), isNotEmpty);
    });

    test('a division whose left operand alone is an integer literal', () {
      expect(findNumericViolations('final a = 1 / count;'), isNotEmpty);
    });

    test('an integer division inside a string interpolation', () {
      expect(
        findNumericViolations(r"String f() => 'x ${1 / 3}';"),
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

    test('an exact division between non-literal operands', () {
      expect(findNumericViolations('final a = x.amount / y.amount;'), isEmpty);
    });

    // The known limit, pinned rather than left to be rediscovered. A literal on
    // the right says nothing about the left operand's type, and the left is
    // what selects the operator.
    test('a division whose right operand alone is an integer literal', () {
      expect(findNumericViolations('final a = x.amount / 3;'), isEmpty);
    });

    test('a truncating integer division', () {
      expect(findNumericViolations('final a = 7 ~/ 2;'), isEmpty);
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
}
