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

/// Prefix operators that keep an integer an integer. Dart defines no unary
/// plus, and `!` takes a boolean, so these two are the whole set.
final _integerPrefixOperators = <TokenType>{TokenType.MINUS, TokenType.TILDE};

/// Binary operators that leave an integer receiver an integer whatever the
/// right operand is, for two different reasons.
///
/// `int.~/` is declared to return an `int` for any `num` it accepts, so
/// `7 ~/ 2.5` really is an `int`. The bitwise and shift operators arrive at the
/// same place by another route: they refuse a non-`int` right operand at
/// compile time, so any code that compiles has an `int` on both sides. Either
/// way the right operand needs no inspection.
final _integerPreservingOperators = <TokenType>{
  TokenType.TILDE_SLASH,
  TokenType.AMPERSAND,
  TokenType.BAR,
  TokenType.CARET,
  TokenType.LT_LT,
  TokenType.GT_GT,
  TokenType.GT_GT_GT,
};

/// Binary operators that produce an integer only when both operands are.
/// `int.+` is declared to return `num`, and `1 + 2.5` is a double, so an
/// integer on the left settles nothing by itself. `/` is absent from both sets
/// deliberately: it is the operator that produces the double being looked for.
final _integerBothOperandOperators = <TokenType>{
  TokenType.PLUS,
  TokenType.MINUS,
  TokenType.STAR,
  TokenType.PERCENT,
};

/// Whether the parser alone settles [expression] as an integer.
///
/// This is the boundary the whole integer-division rule converges on, and it
/// is drawn on a principle rather than on the shapes reported so far. An
/// integer literal qualifies, and so does any integer operator applied to
/// expressions that qualify — which closes `-1`, `~1`, `(1)`, `1 + 2` and
/// every nesting of them in one rule instead of one round each.
///
/// A cast qualifies too, because the cast names the type in the source: no
/// resolution is needed to read `v as int`. A nullable cast does not, and
/// neither does a cast to `num`, since neither settles the receiver as an
/// integer. A conditional qualifies when both of its arms do.
///
/// An identifier or a method call does not qualify, however obviously integral
/// it looks. `1.abs()` is an `int` at runtime, but reading a return type is
/// precisely the work a parsed tree cannot do, and guessing would report the
/// domain's own `Rational` arithmetic. That is now the whole of what sits
/// outside this function, and it sits outside because the parser genuinely
/// cannot reach it rather than because it has not been implemented. Those
/// cases are pinned as accepted by tests; closing them needs resolved types,
/// which is tracked separately.
bool _isSyntacticInteger(Expression expression) {
  final node = _unparenthesized(expression);
  if (node is IntegerLiteral) return true;
  if (node is AsExpression) {
    final type = node.type;
    return type is NamedType &&
        type.name.lexeme == 'int' &&
        type.question == null;
  }
  if (node is ConditionalExpression) {
    return _isSyntacticInteger(node.thenExpression) &&
        _isSyntacticInteger(node.elseExpression);
  }
  if (node is PrefixExpression &&
      _integerPrefixOperators.contains(node.operator.type)) {
    return _isSyntacticInteger(node.operand);
  }
  if (node is BinaryExpression) {
    if (_integerPreservingOperators.contains(node.operator.type)) {
      return _isSyntacticInteger(node.leftOperand);
    }
    if (_integerBothOperandOperators.contains(node.operator.type)) {
      return _isSyntacticInteger(node.leftOperand) &&
          _isSyntacticInteger(node.rightOperand);
    }
  }
  return false;
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
    // `~/` is the truncating one. The left operand selects the operator, so a
    // receiver the parser settles as an integer means `int./` and therefore a
    // double, whatever the right operand turns out to be. That is safe against
    // the domain's own divisions without needing types: an integer cannot be
    // the left operand of a Rational division at all, because Rational is not
    // a `num` and the analyzer rejects it outright.
    //
    // The converse does not hold. A literal on the right says nothing about
    // the left operand's type, and the domain divides Rationals at six call
    // sites, so requiring a literal there would report every one of them. Both
    // directions are pinned by tests.
    if (node.operator.type == TokenType.SLASH &&
        _isSyntacticInteger(node.leftOperand)) {
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

    test('a division by a negated integer receiver', () {
      expect(findNumericViolations('final a = -1 / 3;'), isNotEmpty);
    });

    test('a division by a bitwise-complemented integer receiver', () {
      expect(findNumericViolations('final a = ~1 / 3;'), isNotEmpty);
    });

    test('a division whose receiver is integer arithmetic', () {
      expect(findNumericViolations('final a = (1 + 2) / 3;'), isNotEmpty);
    });

    test('a division by a negated integer receiver over a variable', () {
      expect(findNumericViolations('final a = -1 / count;'), isNotEmpty);
    });

    test('a division whose receiver is a truncating division', () {
      // `int.~/` returns an int for any operand it accepts, so the right
      // operand's type does not matter here.
      expect(findNumericViolations('final a = (7 ~/ count) / 3;'), isNotEmpty);
    });

    test('a division whose receiver is a bitwise expression', () {
      // A bitwise operator on an int refuses a non-int right operand at
      // compile time, so anything that compiles yields an int.
      expect(findNumericViolations('final a = (7 & mask) / 3;'), isNotEmpty);
    });

    test('a division whose receiver is a shifted integer', () {
      expect(findNumericViolations('final a = (7 >>> bits) / 3;'), isNotEmpty);
    });

    test('a division whose receiver is explicitly cast to an integer', () {
      // The cast names the type in the source, so no resolution is needed.
      expect(findNumericViolations('final a = (v as int) / 3;'), isNotEmpty);
    });

    test('a division whose receiver is a conditional of integers', () {
      expect(findNumericViolations('final a = (f ? 1 : 2) / 3;'), isNotEmpty);
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

    // The known limits, pinned rather than left to be rediscovered. This guard
    // reads a parsed tree and has no types, so it reports only receivers the
    // parser alone settles as integers. Everything below yields a double at
    // runtime and is deliberately not reported; closing these needs resolved
    // types, which is a separate decision.
    test('a division whose right operand alone is an integer literal', () {
      // A literal on the right says nothing about the left operand's type,
      // and the left is what selects the operator.
      expect(findNumericViolations('final a = x.amount / 3;'), isEmpty);
    });

    test('a division whose receiver is a method call on an integer', () {
      // `1.abs()` is an int at runtime, but resolving a return type is
      // exactly the work a parsed tree cannot do.
      expect(findNumericViolations('final a = 1.abs() / 3;'), isEmpty);
    });

    test('a method call on an integer literal, which is not a double', () {
      expect(findNumericViolations('final a = 1.abs();'), isEmpty);
    });

    test('a division whose receiver adds an unknown operand', () {
      // Unlike `~/`, `int.+` returns a double for a double operand, so a
      // literal on the left settles nothing here. `1 + half` is a double.
      expect(findNumericViolations('final a = (1 + other) / 3;'), isEmpty);
    });

    test('a division whose receiver takes a modulo of an unknown operand', () {
      expect(findNumericViolations('final a = (1 % other) / 3;'), isEmpty);
    });

    test('a division whose receiver is cast to a nullable integer', () {
      // `int?` is not an integer receiver, and `/` cannot be applied to it
      // without a null check anyway.
      expect(findNumericViolations('final a = (v as int?) / 3;'), isEmpty);
    });

    test('a division whose receiver is cast to num', () {
      // `num` may hold either, so the cast settles nothing about `int./`.
      expect(findNumericViolations('final a = (v as num) / 3;'), isEmpty);
    });

    test('a division whose receiver is a conditional with one unknown arm', () {
      expect(findNumericViolations('final a = (f ? 1 : other) / 3;'), isEmpty);
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
