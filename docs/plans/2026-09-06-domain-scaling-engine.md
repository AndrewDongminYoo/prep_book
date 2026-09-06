# Domain Scaling Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the pure-Dart domain layer that turns a saved recipe and a target yield into an exact, batch-decomposed production result with warnings, with no Flutter, storage, file, or network dependency.

**Architecture:** Quantities carry an exact `Rational` amount and a `Unit`; `Decimal` appears only at construction and display boundaries. A `ProductionCalculator` computes the scale ratio, decomposes the run into batches, applies each component's scaling behavior, recurses into sub-recipes, and returns both the unrounded and the rounded quantity for every row. Everything lives under `lib/domain/`, guarded by a test that fails if any file there imports Flutter or a platform library.

**Tech Stack:** Dart 3.12+, `decimal` ^3.2.6 (which brings `rational` ^2.2.3), `flutter_test` for the runner, `very_good_analysis` lints.

**Spec:** `docs/notes/2026-09-06-prepbook-pro-design.md`

## Global Constraints

- Binary floating point is prohibited. `double` must not appear anywhere under `lib/domain/`, including in test expectations.
- No file under `lib/domain/` may import `package:flutter/`, `dart:io`, `dart:ui`, or any storage, PDF, or network package. Task 1 adds the test that enforces this.
- CI requires 100 percent line coverage (`very_good test --coverage --min-coverage 100`). Every task's code must be fully covered by that task's tests.
- Analysis must stay clean under `flutter analyze` with `very_good_analysis` ^10.3.0 and `bloc_lint`.
- Every commit passes the `trunk fmt` pre-commit hook. Stage with `git add <paths>`, then commit the index.
- Commit subjects are conventional commits in English. No AI attribution trailers.
- Korean is not used in domain identifiers or in code comments in this layer; the domain has no user-facing strings.
- Inside a linked worktree, a spell check must pass `--no-gitignore`; without it cspell checks zero files and still reports success. Read the "Files checked" count.

## Representation decision, stated once

The spec says "All quantities use exact decimal values" and "Binary floating-point values are prohibited".
A scale ratio of `T / B` is frequently not representable as a terminating decimal: a 1 kg base scaled to 3 kg is fine, but 1 kg scaled to a third of a batch is `1/3`.

Verified against `decimal` 3.2.6 on 2026-09-06:

```log
Decimal / Decimal                           -> Rational : 1/3
Rational.hasFinitePrecision                 -> whether a finite decimal exists
Rational.toDecimal(scaleOnInfinitePrecision: n) -> Decimal
Rational.floor() / Rational.ceil()          -> BigInt, not Decimal
Decimal.parse('1.0') == Decimal.parse('1')  -> true
Decimal.parse('2.50').toString()            -> 2.5
```

So `Quantity` stores a `Rational`, which is exact for every value a `Decimal` can express and for every ratio between them. `Decimal` is the construction and display type. This honors the spec's intent — no precision is ever lost — while `Decimal` alone could not.

Two consequences the tasks below depend on:

- `Rational.floor()` and `ceil()` return `BigInt`; convert back with `Decimal.fromBigInt`.
- `Decimal.toString()` drops trailing zeros, so display formatting needs an explicit scale and cannot rely on `toString()`.

## File Structure

```log
lib/domain/
├── domain.dart                        barrel; exports the public domain API
├── errors.dart                        sealed DomainError hierarchy
├── warnings.dart                      sealed ProductionWarning hierarchy
├── units/
│   ├── unit.dart                      UnitDimension, Unit, the conversion table
│   ├── quantity.dart                  Quantity: exact Rational amount + Unit
│   └── rounding.dart                  RoundingRule, ScaledQuantity
├── recipe/
│   ├── scaling_behavior.dart          ScalingBehavior enum
│   ├── ingredient.dart                Ingredient
│   ├── component.dart                 ComponentTarget, RecipeComponent
│   └── recipe.dart                    Recipe with base yield and revision
├── graph/
│   └── recipe_dependency_graph.dart   cycle and missing-dependency detection
├── scaling/
│   ├── batch_plan.dart                BatchPlan.decompose
│   ├── scaled_component.dart          ScaledComponent, ProductionResult
│   └── production_calculator.dart     the calculator
└── production_run.dart                immutable ProductionRun snapshot

test/domain/
├── domain_purity_test.dart            the import guard
├── units/{unit,quantity,rounding}_test.dart
├── recipe/{component,recipe}_test.dart
├── graph/recipe_dependency_graph_test.dart
├── scaling/{batch_plan,production_calculator,nested_recipe}_test.dart
├── production_run_test.dart
└── properties/scaling_invariants_test.dart
```

Files that change together live together: a unit and its conversion table are one file, a component and its target are one file. `production_calculator.dart` is the only file that knows about all of them.

---

### Task 1: Domain package boundary and its guard

**Files:**

- Modify: `pubspec.yaml`
- Create: `lib/domain/domain.dart`
- Test: `test/domain/domain_purity_test.dart`

**Interfaces:**

- Consumes: nothing.
- Produces: the `package:prep_book/domain/domain.dart` barrel that every later task exports through, and the `decimal` dependency every later task imports.

- [ ] **Step 1: Write the failing test**

Create `test/domain/domain_purity_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no domain source imports Flutter or a platform library', () {
    const banned = <String>[
      'package:flutter/',
      'package:flutter_bloc/',
      'dart:io',
      'dart:ui',
      'package:sqflite',
      'package:pdf',
      'package:http',
    ];

    final domain = Directory('lib/domain');
    expect(domain.existsSync(), isTrue, reason: 'lib/domain must exist');

    final offenders = <String>[];
    for (final entity in domain.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final reference in banned) {
        // Any quoted reference, so a re-export cannot slip past the guard.
        if (source.contains("'$reference")) {
          offenders.add('${entity.path} references $reference');
        }
      }
    }

    expect(offenders, isEmpty);
  });

  test('no domain source uses double', () {
    final domain = Directory('lib/domain');
    final offenders = <String>[];
    for (final entity in domain.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (RegExp(r'\bdouble\b').hasMatch(source)) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/domain_purity_test.dart`
Expected: FAIL — `lib/domain must exist`.

- [ ] **Step 3: Add the dependency and the barrel**

In `pubspec.yaml`, add to `dependencies`, keeping the list alphabetical:

```yaml
decimal: ^3.2.6
```

Then run `flutter pub get`. This resolves `rational` ^2.2.3 transitively; do not add it explicitly.

Create `lib/domain/domain.dart`:

```dart
/// The pure-Dart production-scaling domain.
///
/// Nothing in this library may import Flutter, storage, files, or the
/// network. `test/domain/domain_purity_test.dart` enforces that.
library;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/domain_purity_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/domain/domain.dart test/domain/domain_purity_test.dart
git commit -m "feat(domain): add the domain library boundary and its import guard"
```

---

### Task 2: Units and the conversion table

**Files:**

- Create: `lib/domain/units/unit.dart`
- Create: `lib/domain/errors.dart`
- Modify: `lib/domain/domain.dart`
- Test: `test/domain/units/unit_test.dart`

**Interfaces:**

- Consumes: the barrel from Task 1.
- Produces:
  - `enum UnitDimension { mass, volume, count, yieldOnly }`
  - `Unit` with `String symbol`, `UnitDimension dimension`, `Decimal factorToCanonical`, `bool canConvertTo(Unit other)`.
  - Constants `Unit.milligram`, `Unit.gram`, `Unit.kilogram`, `Unit.milliliter`, `Unit.liter`, `Unit.teaspoon`, `Unit.tablespoon`, `Unit.portion`.
  - Factories `Unit.count(String symbol)` and `Unit.namedYield(String symbol)`.
  - `sealed class DomainError`, `UndefinedConversionError(Unit from, Unit to)`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/units/unit_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('Unit', () {
    test('mass units share a dimension and convert', () {
      expect(Unit.kilogram.dimension, UnitDimension.mass);
      expect(Unit.gram.canConvertTo(Unit.kilogram), isTrue);
    });

    test('mass does not convert to volume', () {
      expect(Unit.gram.canConvertTo(Unit.milliliter), isFalse);
    });

    test('spoons are defined against milliliters', () {
      expect(Unit.teaspoon.factorToCanonical, Decimal.fromInt(5));
      expect(Unit.tablespoon.factorToCanonical, Decimal.fromInt(15));
    });

    test('two different count units never convert', () {
      final sheet = Unit.count('sheet');
      final bag = Unit.count('bag');
      expect(sheet.canConvertTo(sheet), isTrue);
      expect(sheet.canConvertTo(bag), isFalse);
    });

    test('yield-only units convert only to themselves', () {
      final tray = Unit.namedYield('tray');
      expect(Unit.portion.canConvertTo(Unit.portion), isTrue);
      expect(Unit.portion.canConvertTo(tray), isFalse);
    });

    test('units with the same symbol and dimension are equal', () {
      expect(Unit.count('sheet'), Unit.count('sheet'));
      expect(Unit.count('sheet').hashCode, Unit.count('sheet').hashCode);
    });

    test('describes itself by symbol', () {
      expect(Unit.kilogram.toString(), 'kg');
    });
  });

  group('UndefinedConversionError', () {
    test('names both units in its message', () {
      final error = UndefinedConversionError(Unit.gram, Unit.milliliter);
      expect(error.toString(), contains('g'));
      expect(error.toString(), contains('ml'));
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/units/unit_test.dart`
Expected: FAIL — `Undefined name 'Unit'`.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/errors.dart`:

```dart
import 'package:prep_book/domain/units/unit.dart';

/// Base type for every error the domain raises.
sealed class DomainError implements Exception {
  const DomainError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Raised when two units have no defined conversion between them.
final class UndefinedConversionError extends DomainError {
  UndefinedConversionError(this.from, this.to)
    : super('no defined conversion from ${from.symbol} to ${to.symbol}');

  final Unit from;
  final Unit to;
}
```

Create `lib/domain/units/unit.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';

/// The kinds of quantity the application can express.
enum UnitDimension {
  /// Milligrams, grams, kilograms.
  mass,

  /// Milliliters, litres, teaspoons, tablespoons.
  volume,

  /// Discrete named things: item, sheet, bag.
  count,

  /// Recipe output units that measure nothing else: portion, tray.
  yieldOnly,
}

/// A unit of measure with a defined position in its dimension.
@immutable
final class Unit {
  const Unit._(this.symbol, this.dimension, this.factorToCanonical);

  /// A named count unit. Count units never convert into one another.
  factory Unit.count(String symbol) =>
      Unit._(symbol, UnitDimension.count, Decimal.one);

  /// A recipe-defined output unit. These never convert into one another.
  factory Unit.namedYield(String symbol) =>
      Unit._(symbol, UnitDimension.yieldOnly, Decimal.one);

  static final Unit milligram = Unit._(
    'mg',
    UnitDimension.mass,
    Decimal.parse('0.001'),
  );
  static final Unit gram = Unit._('g', UnitDimension.mass, Decimal.one);
  static final Unit kilogram = Unit._(
    'kg',
    UnitDimension.mass,
    Decimal.fromInt(1000),
  );

  static final Unit milliliter = Unit._(
    'ml',
    UnitDimension.volume,
    Decimal.one,
  );
  static final Unit liter = Unit._(
    'L',
    UnitDimension.volume,
    Decimal.fromInt(1000),
  );
  static final Unit teaspoon = Unit._(
    'tsp',
    UnitDimension.volume,
    Decimal.fromInt(5),
  );
  static final Unit tablespoon = Unit._(
    'tbsp',
    UnitDimension.volume,
    Decimal.fromInt(15),
  );

  static final Unit portion = Unit.namedYield('portion');

  /// The unit's symbol as the operator writes it.
  final String symbol;

  /// The dimension this unit measures.
  final UnitDimension dimension;

  /// How many canonical units one of this unit is worth.
  ///
  /// Grams for mass, milliliters for volume, and one for every count or
  /// yield-only unit, which are never scaled against a sibling.
  final Decimal factorToCanonical;

  /// Whether the dimension defines conversions between distinct units.
  bool get hasDefinedConversions =>
      dimension == UnitDimension.mass || dimension == UnitDimension.volume;

  /// Whether a conversion from this unit to [other] is defined.
  ///
  /// Density is never inferred, so mass never converts to volume.
  bool canConvertTo(Unit other) {
    if (dimension != other.dimension) return false;
    return hasDefinedConversions || symbol == other.symbol;
  }

  @override
  bool operator ==(Object other) =>
      other is Unit && other.symbol == symbol && other.dimension == dimension;

  @override
  int get hashCode => Object.hash(symbol, dimension);

  @override
  String toString() => symbol;
}
```

Add to `lib/domain/domain.dart`:

```dart
export 'package:decimal/decimal.dart' show Decimal;
export 'package:rational/rational.dart' show Rational;

export 'errors.dart';
export 'units/unit.dart';
```

`meta` is already available transitively through `flutter`; no pubspec change is needed for `@immutable`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/units/unit_test.dart`
Expected: PASS, 8 tests.

- [ ] **Step 5: Verify the whole suite and the analyzer**

Run: `flutter analyze && flutter test`
Expected: no analyzer issues, all tests pass.

- [ ] **Step 6: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): add units with an explicit conversion table"
```

---

### Task 3: Quantity

**Files:**

- Create: `lib/domain/units/quantity.dart`
- Modify: `lib/domain/errors.dart`, `lib/domain/domain.dart`
- Test: `test/domain/units/quantity_test.dart`

**Interfaces:**

- Consumes: `Unit`, `UnitDimension`, `UndefinedConversionError` from Task 2.
- Produces:
  - `Quantity` with `Rational amount`, `Unit unit`.
  - `Quantity.fromDecimal(Decimal amount, Unit unit)`, `Quantity.parse(String amount, Unit unit)`, `Quantity.fromRational(Rational amount, Unit unit)`.
  - `Decimal toDecimal({int scaleOnInfinitePrecision = 6})`, `bool get isExactDecimal`.
  - `Quantity scaleBy(Rational ratio)`, `Quantity operator +(Quantity other)`, `Quantity convertTo(Unit target)`, `int compareTo(Quantity other)`, `bool get isZero`.
  - `NegativeQuantityError`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/units/quantity_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('Quantity', () {
    test('keeps a non-terminating ratio exact', () {
      final base = Quantity.parse('1', Unit.kilogram);
      final scaled = base.scaleBy(Rational(BigInt.one, BigInt.from(3)));

      expect(scaled.isExactDecimal, isFalse);
      expect(scaled.amount, Rational(BigInt.one, BigInt.from(3)));
      expect(
        scaled.toDecimal(scaleOnInfinitePrecision: 4),
        Decimal.parse('0.3333'),
      );
    });

    test('scaling by a then b equals scaling by a times b', () {
      final base = Quantity.parse('250.5', Unit.gram);
      final a = Rational(BigInt.from(7), BigInt.from(3));
      final b = Rational(BigInt.from(5), BigInt.from(11));

      expect(base.scaleBy(a).scaleBy(b), base.scaleBy(a * b));
    });

    test('converts within a dimension', () {
      final grams = Quantity.parse('1500', Unit.gram);
      expect(grams.convertTo(Unit.kilogram).amount, Rational.fromInt(3, 2));
      expect(grams.convertTo(Unit.kilogram).unit, Unit.kilogram);
    });

    test('a tablespoon is fifteen milliliters', () {
      final spoon = Quantity.parse('2', Unit.tablespoon);
      expect(spoon.convertTo(Unit.milliliter).amount, Rational.fromInt(30));
    });

    test('rejects a conversion across dimensions', () {
      final grams = Quantity.parse('100', Unit.gram);
      expect(
        () => grams.convertTo(Unit.milliliter),
        throwsA(isA<UndefinedConversionError>()),
      );
    });

    test('rejects a conversion between two count units', () {
      final sheets = Quantity.parse('3', Unit.count('sheet'));
      expect(
        () => sheets.convertTo(Unit.count('bag')),
        throwsA(isA<UndefinedConversionError>()),
      );
    });

    test('adds after converting the operand', () {
      final a = Quantity.parse('1', Unit.kilogram);
      final b = Quantity.parse('500', Unit.gram);
      expect((a + b).amount, Rational.fromInt(3, 2));
      expect((a + b).unit, Unit.kilogram);
    });

    test('refuses to add across dimensions', () {
      final a = Quantity.parse('1', Unit.kilogram);
      final b = Quantity.parse('1', Unit.liter);
      expect(() => a + b, throwsA(isA<UndefinedConversionError>()));
    });

    test('rejects a negative amount', () {
      expect(
        () => Quantity.parse('-1', Unit.gram),
        throwsA(isA<NegativeQuantityError>()),
      );
    });

    test('compares within a dimension', () {
      final a = Quantity.parse('1', Unit.kilogram);
      final b = Quantity.parse('999', Unit.gram);
      expect(a.compareTo(b), greaterThan(0));
      expect(Quantity.parse('0', Unit.gram).isZero, isTrue);
    });

    test('equal values in the same unit are equal', () {
      expect(
        Quantity.parse('1.50', Unit.kilogram),
        Quantity.parse('1.5', Unit.kilogram),
      );
      expect(
        Quantity.parse('1.5', Unit.kilogram).hashCode,
        Quantity.parse('1.5', Unit.kilogram).hashCode,
      );
    });

    test('describes itself with the unit symbol', () {
      expect(Quantity.parse('1.5', Unit.kilogram).toString(), '1.5 kg');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/units/quantity_test.dart`
Expected: FAIL — `Undefined name 'Quantity'`.

- [ ] **Step 3: Write the implementation**

Append to `lib/domain/errors.dart`:

```dart
/// Raised when a quantity would become negative.
final class NegativeQuantityError extends DomainError {
  NegativeQuantityError(this.amount)
    : super('a quantity may not be negative: $amount');

  final Rational amount;
}
```

and add `import 'package:rational/rational.dart';` at the top of that file.

Create `lib/domain/units/quantity.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/units/unit.dart';
import 'package:rational/rational.dart';

/// An exact amount paired with the unit it is measured in.
///
/// The amount is a [Rational] so that a scale ratio such as `1/3` survives
/// without rounding. [toDecimal] is the only place a value is ever
/// approximated, and only when the value has no finite decimal form.
@immutable
final class Quantity implements Comparable<Quantity> {
  /// Creates a quantity from an exact rational amount.
  factory Quantity.fromRational(Rational amount, Unit unit) {
    if (amount.signum < 0) throw NegativeQuantityError(amount);
    return Quantity._(amount, unit);
  }

  /// Creates a quantity from a decimal amount.
  factory Quantity.fromDecimal(Decimal amount, Unit unit) =>
      Quantity.fromRational(amount.toRational(), unit);

  /// Creates a quantity by parsing a decimal literal such as `'250.5'`.
  factory Quantity.parse(String amount, Unit unit) =>
      Quantity.fromDecimal(Decimal.parse(amount), unit);

  const Quantity._(this.amount, this.unit);

  /// The exact amount. Never rounded.
  final Rational amount;

  /// The unit the amount is measured in.
  final Unit unit;

  /// Whether the amount has a terminating decimal representation.
  bool get isExactDecimal => amount.hasFinitePrecision;

  /// Whether the amount is exactly zero.
  bool get isZero => amount == Rational.zero;

  /// The amount as a decimal, approximated only when [isExactDecimal] is
  /// false.
  Decimal toDecimal({int scaleOnInfinitePrecision = 6}) =>
      amount.toDecimal(scaleOnInfinitePrecision: scaleOnInfinitePrecision);

  /// This quantity multiplied by [ratio], exactly.
  Quantity scaleBy(Rational ratio) =>
      Quantity.fromRational(amount * ratio, unit);

  /// This quantity expressed in [target].
  ///
  /// Throws [UndefinedConversionError] when no conversion is defined.
  /// Density is never inferred.
  Quantity convertTo(Unit target) {
    if (unit == target) return this;
    if (!unit.canConvertTo(target)) {
      throw UndefinedConversionError(unit, target);
    }
    final canonical = amount * unit.factorToCanonical.toRational();
    return Quantity.fromRational(
      canonical / target.factorToCanonical.toRational(),
      target,
    );
  }

  /// The sum of this quantity and [other], expressed in this unit.
  Quantity operator +(Quantity other) =>
      Quantity.fromRational(amount + other.convertTo(unit).amount, unit);

  @override
  int compareTo(Quantity other) =>
      amount.compareTo(other.convertTo(unit).amount);

  @override
  bool operator ==(Object other) =>
      other is Quantity && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => '${toDecimal()} ${unit.symbol}';
}
```

Add `export 'units/quantity.dart';` to `lib/domain/domain.dart`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/units/quantity_test.dart`
Expected: PASS, 12 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): add Quantity with exact rational arithmetic"
```

---

### Task 4: Rounding rules and the rounded-versus-exact pair

**Files:**

- Create: `lib/domain/units/rounding.dart`
- Modify: `lib/domain/errors.dart`, `lib/domain/domain.dart`
- Test: `test/domain/units/rounding_test.dart`

**Interfaces:**

- Consumes: `Quantity`, `Unit`, `DomainError`.
- Produces:
  - `RoundingRule.upToIncrement(Decimal increment)` with `Quantity apply(Quantity value)`.
  - `ScaledQuantity` with `Quantity exact`, `Quantity displayed`, `bool get wasRounded`.
  - `ScaledQuantity.unrounded(Quantity value)` and `ScaledQuantity.rounded({required Quantity exact, required RoundingRule rule})`.
  - `InvalidRoundingIncrementError`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/units/rounding_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('RoundingRule', () {
    test('rounds up to the next increment', () {
      final rule = RoundingRule.upToIncrement(Decimal.parse('0.25'));
      final rounded = rule.apply(Quantity.parse('12.34', Unit.kilogram));
      expect(rounded.amount, Decimal.parse('12.5').toRational());
    });

    test('leaves an exact multiple alone', () {
      final rule = RoundingRule.upToIncrement(Decimal.parse('0.25'));
      final rounded = rule.apply(Quantity.parse('12.5', Unit.kilogram));
      expect(rounded.amount, Decimal.parse('12.5').toRational());
    });

    test('rounds a non-terminating amount up', () {
      final rule = RoundingRule.upToIncrement(Decimal.one);
      final third = Quantity.parse('1', Unit.gram)
          .scaleBy(Rational(BigInt.one, BigInt.from(3)));
      expect(rule.apply(third).amount, Rational.one);
    });

    test('rejects a zero or negative increment', () {
      expect(
        () => RoundingRule.upToIncrement(Decimal.zero),
        throwsA(isA<InvalidRoundingIncrementError>()),
      );
      expect(
        () => RoundingRule.upToIncrement(Decimal.parse('-1')),
        throwsA(isA<InvalidRoundingIncrementError>()),
      );
    });
  });

  group('ScaledQuantity', () {
    test('an unrounded value reports no rounding', () {
      final value = Quantity.parse('3', Unit.gram);
      final scaled = ScaledQuantity.unrounded(value);
      expect(scaled.exact, value);
      expect(scaled.displayed, value);
      expect(scaled.wasRounded, isFalse);
    });

    test('keeps the exact value alongside the rounded one', () {
      final exact = Quantity.parse('12.34', Unit.kilogram);
      final scaled = ScaledQuantity.rounded(
        exact: exact,
        rule: RoundingRule.upToIncrement(Decimal.parse('0.25')),
      );
      expect(scaled.exact, exact);
      expect(scaled.displayed.amount, Decimal.parse('12.5').toRational());
      expect(scaled.wasRounded, isTrue);
    });

    test('reports no rounding when the rule changes nothing', () {
      final exact = Quantity.parse('12.5', Unit.kilogram);
      final scaled = ScaledQuantity.rounded(
        exact: exact,
        rule: RoundingRule.upToIncrement(Decimal.parse('0.25')),
      );
      expect(scaled.wasRounded, isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/units/rounding_test.dart`
Expected: FAIL — `Undefined name 'RoundingRule'`.

- [ ] **Step 3: Write the implementation**

Append to `lib/domain/errors.dart`:

```dart
/// Raised when a rounding increment is not strictly positive.
final class InvalidRoundingIncrementError extends DomainError {
  InvalidRoundingIncrementError(this.increment)
    : super('a rounding increment must be positive: $increment');

  final Decimal increment;
}
```

and add `import 'package:decimal/decimal.dart';` at the top of that file.

Create `lib/domain/units/rounding.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/units/quantity.dart';

/// Rounds a display quantity up to the nearest multiple of an increment.
///
/// The spec makes rounding up the default so a kitchen never under-produces.
@immutable
final class RoundingRule {
  /// Creates a rule that rounds up to the nearest [increment].
  factory RoundingRule.upToIncrement(Decimal increment) {
    if (increment <= Decimal.zero) {
      throw InvalidRoundingIncrementError(increment);
    }
    return RoundingRule._(increment);
  }

  const RoundingRule._(this.increment);

  /// The step the displayed value is rounded up to.
  final Decimal increment;

  /// [value] rounded up to the next multiple of [increment].
  Quantity apply(Quantity value) {
    final steps = (value.amount / increment.toRational()).ceil();
    return Quantity.fromRational(
      Decimal.fromBigInt(steps).toRational() * increment.toRational(),
      value.unit,
    );
  }
}

/// A calculated quantity together with what the operator is shown.
///
/// The spec requires the unrounded value to stay visible and stored, so both
/// are kept even when they are identical.
@immutable
final class ScaledQuantity {
  /// A value that carries no rounding rule.
  ScaledQuantity.unrounded(Quantity value) : exact = value, displayed = value;

  /// A value rounded for display by [rule].
  ScaledQuantity.rounded({required this.exact, required RoundingRule rule})
    : displayed = rule.apply(exact);

  /// The calculated value before any rounding.
  final Quantity exact;

  /// The value shown to the operator.
  final Quantity displayed;

  /// Whether rounding changed the value.
  bool get wasRounded => displayed != exact;
}
```

Add `export 'units/rounding.dart';` to `lib/domain/domain.dart`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/units/rounding_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): add increment rounding that preserves the exact value"
```

---

### Task 5: Ingredients, components, and recipes

**Files:**

- Create: `lib/domain/recipe/scaling_behavior.dart`, `lib/domain/recipe/ingredient.dart`, `lib/domain/recipe/component.dart`, `lib/domain/recipe/recipe.dart`
- Modify: `lib/domain/errors.dart`, `lib/domain/domain.dart`
- Test: `test/domain/recipe/component_test.dart`, `test/domain/recipe/recipe_test.dart`

**Interfaces:**

- Consumes: `Quantity`, `Unit`, `RoundingRule`, `DomainError`.
- Produces:
  - `enum ScalingBehavior { proportional, perBatch, fixedOnce, manual }`
  - `Ingredient({required String id, required String name, String? category, required Unit defaultUnit})`
  - `sealed class ComponentTarget`, `IngredientRef(String ingredientId)`, `SubRecipeRef(String recipeId)`
  - `RecipeComponent({required String id, required ComponentTarget target, required Quantity? baseQuantity, required ScalingBehavior behavior, RoundingRule? rounding, String? note, required int displayOrder})`
  - `Recipe({required String id, required int revision, required String name, String? category, required Quantity baseYield, Quantity? maxBatchYield, required List<RecipeComponent> components, List<String> preparationNotes, required DateTime modifiedAt, bool isArchived})`
  - `InvalidBaseYieldError`, `InvalidComponentError`, `IncompatibleYieldUnitError`

- [ ] **Step 1: Write the failing tests**

Create `test/domain/recipe/component_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('RecipeComponent', () {
    test('a numeric behavior requires a base quantity', () {
      expect(
        () => RecipeComponent(
          id: 'c1',
          target: const IngredientRef('flour'),
          baseQuantity: null,
          behavior: ScalingBehavior.proportional,
          displayOrder: 0,
        ),
        throwsA(isA<InvalidComponentError>()),
      );
    });

    test('a manual component may omit its quantity', () {
      final component = RecipeComponent(
        id: 'c1',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        note: 'to taste',
        displayOrder: 0,
      );
      expect(component.baseQuantity, isNull);
      expect(component.behavior, ScalingBehavior.manual);
    });

    test('a manual component may not carry a base quantity', () {
      expect(
        () => RecipeComponent(
          id: 'c1',
          target: const IngredientRef('salt'),
          baseQuantity: Quantity.parse('1', Unit.gram),
          behavior: ScalingBehavior.manual,
          displayOrder: 0,
        ),
        throwsA(isA<InvalidComponentError>()),
      );
    });

    test('an ingredient carries its display name and default unit', () {
      final ingredient = Ingredient(
        id: 'flour',
        name: 'Bread flour',
        defaultUnit: Unit.kilogram,
        category: 'Dry goods',
      );
      expect(ingredient.name, 'Bread flour');
      expect(ingredient.defaultUnit, Unit.kilogram);
      expect(ingredient.category, 'Dry goods');
    });

    test('targets compare by their referenced identifier', () {
      expect(const IngredientRef('flour'), const IngredientRef('flour'));
      expect(const SubRecipeRef('dough'), isNot(const IngredientRef('dough')));
    });
  });
}
```

Create `test/domain/recipe/recipe_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe buildRecipe({Quantity? baseYield, Quantity? maxBatchYield}) {
  return Recipe(
    id: 'r1',
    revision: 1,
    name: 'Baguette',
    baseYield: baseYield ?? Quantity.parse('10', Unit.portion),
    maxBatchYield: maxBatchYield,
    components: [
      RecipeComponent(
        id: 'c1',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  group('Recipe', () {
    test('rejects a zero base yield', () {
      expect(
        () => buildRecipe(baseYield: Quantity.parse('0', Unit.portion)),
        throwsA(isA<InvalidBaseYieldError>()),
      );
    });

    test('rejects a max batch yield in another dimension', () {
      expect(
        () => buildRecipe(maxBatchYield: Quantity.parse('1', Unit.kilogram)),
        throwsA(isA<IncompatibleYieldUnitError>()),
      );
    });

    test('accepts a max batch yield in the same dimension', () {
      final recipe = buildRecipe(
        maxBatchYield: Quantity.parse('4', Unit.portion),
      );
      expect(recipe.maxBatchYield, Quantity.parse('4', Unit.portion));
    });

    test('exposes components in display order', () {
      final recipe = buildRecipe();
      expect(recipe.components.map((c) => c.id), ['c1']);
      expect(recipe.isArchived, isFalse);
      expect(recipe.preparationNotes, isEmpty);
    });

    test('lists the recipes it depends on', () {
      final recipe = Recipe(
        id: 'r1',
        revision: 1,
        name: 'Sandwich',
        baseYield: Quantity.parse('10', Unit.portion),
        components: [
          RecipeComponent(
            id: 'c1',
            target: const SubRecipeRef('dough'),
            baseQuantity: Quantity.parse('2', Unit.portion),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
        modifiedAt: DateTime.utc(2026, 9, 6),
      );
      expect(recipe.subRecipeIds, ['dough']);
    });
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/domain/recipe`
Expected: FAIL — `Undefined name 'RecipeComponent'`.

- [ ] **Step 3: Write the implementation**

Append to `lib/domain/errors.dart`:

```dart
/// Raised when a recipe's base yield is missing, zero, or negative.
final class InvalidBaseYieldError extends DomainError {
  InvalidBaseYieldError(this.recipeId)
    : super('recipe $recipeId has no positive base yield');

  final String recipeId;
}

/// Raised when a component's fields contradict its scaling behavior.
final class InvalidComponentError extends DomainError {
  InvalidComponentError(this.componentId, String reason)
    : super('component $componentId is invalid: $reason');

  final String componentId;
}

/// Raised when a yield is expressed in an incompatible dimension.
final class IncompatibleYieldUnitError extends DomainError {
  IncompatibleYieldUnitError(this.expected, this.actual)
    : super('expected a yield in ${expected.symbol}, got ${actual.symbol}');

  final Unit expected;
  final Unit actual;
}
```

Create `lib/domain/recipe/scaling_behavior.dart`:

```dart
/// How a component's quantity responds to a production run.
enum ScalingBehavior {
  /// Multiplied by the run's scale ratio.
  proportional,

  /// The configured amount, once per batch.
  perBatch,

  /// The configured amount, once for the whole run.
  fixedOnce,

  /// No numeric result until the operator supplies one.
  manual,
}
```

Create `lib/domain/recipe/ingredient.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:prep_book/domain/units/unit.dart';

/// A reusable library entry naming something a recipe consumes.
///
/// The first release attaches no price, stock, supplier, density, or
/// nutrition data.
@immutable
final class Ingredient {
  /// Creates an ingredient.
  const Ingredient({
    required this.id,
    required this.name,
    required this.defaultUnit,
    this.category,
  });

  /// Stable identifier.
  final String id;

  /// The canonical display name.
  final String name;

  /// The unit the ingredient is normally written in.
  final Unit defaultUnit;

  /// Optional grouping label.
  final String? category;
}
```

Create `lib/domain/recipe/component.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/recipe/scaling_behavior.dart';
import 'package:prep_book/domain/units/quantity.dart';
import 'package:prep_book/domain/units/rounding.dart';

/// What a component points at.
@immutable
sealed class ComponentTarget {
  const ComponentTarget();
}

/// A component that consumes a library ingredient.
final class IngredientRef extends ComponentTarget {
  /// Creates a reference to [ingredientId].
  const IngredientRef(this.ingredientId);

  /// The referenced ingredient.
  final String ingredientId;

  @override
  bool operator ==(Object other) =>
      other is IngredientRef && other.ingredientId == ingredientId;

  @override
  int get hashCode => Object.hash('ingredient', ingredientId);
}

/// A component that consumes the output of another recipe.
final class SubRecipeRef extends ComponentTarget {
  /// Creates a reference to [recipeId].
  const SubRecipeRef(this.recipeId);

  /// The referenced recipe.
  final String recipeId;

  @override
  bool operator ==(Object other) =>
      other is SubRecipeRef && other.recipeId == recipeId;

  @override
  int get hashCode => Object.hash('recipe', recipeId);
}

/// One line of a recipe.
@immutable
final class RecipeComponent {
  /// Creates a component, rejecting combinations the domain forbids.
  factory RecipeComponent({
    required String id,
    required ComponentTarget target,
    required Quantity? baseQuantity,
    required ScalingBehavior behavior,
    required int displayOrder,
    RoundingRule? rounding,
    String? note,
  }) {
    if (behavior != ScalingBehavior.manual && baseQuantity == null) {
      throw InvalidComponentError(
        id,
        'a ${behavior.name} component needs a base quantity',
      );
    }
    // A null base quantity means exactly "manual". The calculator relies on
    // that equivalence to branch without an unreachable case.
    if (behavior == ScalingBehavior.manual && baseQuantity != null) {
      throw InvalidComponentError(
        id,
        'a manual component may not carry a base quantity',
      );
    }
    return RecipeComponent._(
      id: id,
      target: target,
      baseQuantity: baseQuantity,
      behavior: behavior,
      displayOrder: displayOrder,
      rounding: rounding,
      note: note,
    );
  }

  const RecipeComponent._({
    required this.id,
    required this.target,
    required this.baseQuantity,
    required this.behavior,
    required this.displayOrder,
    required this.rounding,
    required this.note,
  });

  /// Stable identifier, unique within the recipe.
  final String id;

  /// The ingredient or recipe this line consumes.
  final ComponentTarget target;

  /// The amount written in the recipe, absent only for a manual line.
  final Quantity? baseQuantity;

  /// How the amount responds to a production run.
  final ScalingBehavior behavior;

  /// Optional display rounding.
  final RoundingRule? rounding;

  /// Optional note for the operator.
  final String? note;

  /// Position in the recipe.
  final int displayOrder;
}
```

Create `lib/domain/recipe/recipe.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/recipe/component.dart';
import 'package:prep_book/domain/units/quantity.dart';

/// One revision of a saved production recipe.
///
/// Saving an edit creates a new revision; stored production runs keep the
/// revision they were computed from.
@immutable
final class Recipe {
  /// Creates a recipe revision, rejecting yields the domain forbids.
  factory Recipe({
    required String id,
    required int revision,
    required String name,
    required Quantity baseYield,
    required List<RecipeComponent> components,
    required DateTime modifiedAt,
    String? category,
    Quantity? maxBatchYield,
    List<String> preparationNotes = const [],
    bool isArchived = false,
  }) {
    if (baseYield.isZero) throw InvalidBaseYieldError(id);
    if (maxBatchYield != null &&
        !baseYield.unit.canConvertTo(maxBatchYield.unit)) {
      throw IncompatibleYieldUnitError(baseYield.unit, maxBatchYield.unit);
    }
    return Recipe._(
      id: id,
      revision: revision,
      name: name,
      baseYield: baseYield,
      components: List.unmodifiable(components),
      modifiedAt: modifiedAt,
      category: category,
      maxBatchYield: maxBatchYield,
      preparationNotes: List.unmodifiable(preparationNotes),
      isArchived: isArchived,
    );
  }

  const Recipe._({
    required this.id,
    required this.revision,
    required this.name,
    required this.baseYield,
    required this.components,
    required this.modifiedAt,
    required this.category,
    required this.maxBatchYield,
    required this.preparationNotes,
    required this.isArchived,
  });

  /// Stable identifier, shared across revisions.
  final String id;

  /// Revision number, incremented on every saved edit.
  final int revision;

  /// Display name.
  final String name;

  /// Optional grouping label.
  final String? category;

  /// The output this recipe produces as written.
  final Quantity baseYield;

  /// The largest yield one batch may produce, when the recipe defines one.
  final Quantity? maxBatchYield;

  /// The recipe's lines, in display order.
  final List<RecipeComponent> components;

  /// Ordered preparation notes.
  final List<String> preparationNotes;

  /// When this revision was saved.
  final DateTime modifiedAt;

  /// Whether the recipe is archived.
  final bool isArchived;

  /// The identifiers of every recipe this one references directly.
  List<String> get subRecipeIds => [
    for (final component in components)
      if (component.target case SubRecipeRef(:final recipeId)) recipeId,
  ];
}
```

Add these exports to `lib/domain/domain.dart`:

```dart
export 'recipe/component.dart';
export 'recipe/ingredient.dart';
export 'recipe/recipe.dart';
export 'recipe/scaling_behavior.dart';
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/recipe`
Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): add the recipe, component, and ingredient model"
```

---

### Task 6: Dependency graph validation

**Files:**

- Create: `lib/domain/graph/recipe_dependency_graph.dart`
- Modify: `lib/domain/errors.dart`, `lib/domain/domain.dart`
- Test: `test/domain/graph/recipe_dependency_graph_test.dart`

**Interfaces:**

- Consumes: `Recipe`, `SubRecipeRef`, `DomainError`.
- Produces:
  - `RecipeDependencyGraph(Map<String, Recipe> recipesById)`
  - `List<String>? findCycleFrom(String recipeId)` returning the path including the repeated identifier, or `null`.
  - `void assertResolvable(String recipeId)` throwing `RecipeCycleError` or `MissingDependencyError`.
  - `RecipeCycleError(List<String> path)`, `MissingDependencyError(String recipeId, String missingId)`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/graph/recipe_dependency_graph_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe recipeWith(String id, List<String> subRecipeIds) {
  return Recipe(
    id: id,
    revision: 1,
    name: id,
    baseYield: Quantity.parse('1', Unit.portion),
    components: [
      for (var i = 0; i < subRecipeIds.length; i++)
        RecipeComponent(
          id: '$id-c$i',
          target: SubRecipeRef(subRecipeIds[i]),
          baseQuantity: Quantity.parse('1', Unit.portion),
          behavior: ScalingBehavior.proportional,
          displayOrder: i,
        ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  group('RecipeDependencyGraph', () {
    test('accepts an acyclic graph', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['b']),
        'b': recipeWith('b', ['c']),
        'c': recipeWith('c', []),
      });
      expect(graph.findCycleFrom('a'), isNull);
      expect(() => graph.assertResolvable('a'), returnsNormally);
    });

    test('detects a direct cycle', () {
      final graph = RecipeDependencyGraph({'a': recipeWith('a', ['a'])});
      expect(graph.findCycleFrom('a'), ['a', 'a']);
    });

    test('detects an indirect cycle and names the path', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['b']),
        'b': recipeWith('b', ['c']),
        'c': recipeWith('c', ['a']),
      });
      expect(graph.findCycleFrom('a'), ['a', 'b', 'c', 'a']);
    });

    test('throws with the cycle path attached', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['b']),
        'b': recipeWith('b', ['a']),
      });
      expect(
        () => graph.assertResolvable('a'),
        throwsA(
          isA<RecipeCycleError>().having(
            (e) => e.path,
            'path',
            ['a', 'b', 'a'],
          ),
        ),
      );
    });

    test('reports a missing dependency', () {
      final graph = RecipeDependencyGraph({'a': recipeWith('a', ['ghost'])});
      expect(
        () => graph.assertResolvable('a'),
        throwsA(
          isA<MissingDependencyError>().having(
            (e) => e.missingId,
            'missingId',
            'ghost',
          ),
        ),
      );
    });

    test('reports a missing root', () {
      final graph = RecipeDependencyGraph(const {});
      expect(
        () => graph.assertResolvable('a'),
        throwsA(isA<MissingDependencyError>()),
      );
    });

    test('visits a shared dependency once', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['b', 'c']),
        'b': recipeWith('b', ['d']),
        'c': recipeWith('c', ['d']),
        'd': recipeWith('d', []),
      });
      expect(graph.findCycleFrom('a'), isNull);
      expect(() => graph.assertResolvable('a'), returnsNormally);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/graph`
Expected: FAIL — `Undefined name 'RecipeDependencyGraph'`.

- [ ] **Step 3: Write the implementation**

Append to `lib/domain/errors.dart`:

```dart
/// Raised when a recipe depends on itself, directly or indirectly.
final class RecipeCycleError extends DomainError {
  RecipeCycleError(this.path)
    : super('recipe dependency cycle: ${path.join(' -> ')}');

  /// The dependency path, ending at the identifier that repeats.
  final List<String> path;
}

/// Raised when a referenced recipe is not in the index.
final class MissingDependencyError extends DomainError {
  MissingDependencyError(this.recipeId, this.missingId)
    : super('recipe $recipeId references missing recipe $missingId');

  final String recipeId;
  final String missingId;
}
```

Create `lib/domain/graph/recipe_dependency_graph.dart`:

```dart
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/recipe/recipe.dart';

/// Validates that a recipe's sub-recipe references form a resolvable tree.
final class RecipeDependencyGraph {
  /// Creates a graph over [recipesById].
  RecipeDependencyGraph(Map<String, Recipe> recipesById)
    : _recipes = Map.unmodifiable(recipesById);

  final Map<String, Recipe> _recipes;

  /// The dependency path proving a cycle reachable from [recipeId], or null.
  ///
  /// The returned path ends at the identifier that repeats, so the caller can
  /// show the operator exactly which reference to remove.
  List<String>? findCycleFrom(String recipeId) {
    final path = <String>[];
    final onPath = <String>{};
    final settled = <String>{};

    List<String>? visit(String id) {
      if (onPath.contains(id)) return [...path, id];
      if (settled.contains(id)) return null;

      final recipe = _recipes[id];
      if (recipe == null) return null;

      path.add(id);
      onPath.add(id);
      for (final childId in recipe.subRecipeIds) {
        final cycle = visit(childId);
        if (cycle != null) return cycle;
      }
      onPath.remove(id);
      path.removeLast();
      settled.add(id);
      return null;
    }

    return visit(recipeId);
  }

  /// Throws when [recipeId] cannot be resolved into a finite tree.
  ///
  /// Cycles are reported before missing dependencies, because a cycle makes
  /// the traversal that finds missing references non-terminating.
  void assertResolvable(String recipeId) {
    final cycle = findCycleFrom(recipeId);
    if (cycle != null) throw RecipeCycleError(cycle);

    final seen = <String>{};
    void visit(String id, String parentId) {
      final recipe = _recipes[id];
      if (recipe == null) throw MissingDependencyError(parentId, id);
      if (!seen.add(id)) return;
      for (final childId in recipe.subRecipeIds) {
        visit(childId, id);
      }
    }

    visit(recipeId, recipeId);
  }
}
```

Add `export 'graph/recipe_dependency_graph.dart';` to `lib/domain/domain.dart`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/graph`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): reject recipe dependency cycles before a revision saves"
```

---

### Task 7: Batch decomposition

**Files:**

- Create: `lib/domain/scaling/batch_plan.dart`
- Modify: `lib/domain/domain.dart`
- Test: `test/domain/scaling/batch_plan_test.dart`

**Interfaces:**

- Consumes: `Quantity`, `Unit`.
- Produces:
  - `BatchPlan.decompose({required Quantity target, Quantity? maxBatchYield})`
  - `int fullBatchCount`, `Quantity fullBatchYield`, `Quantity? remainderYield`, `int get batchCount`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/scaling/batch_plan_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('BatchPlan', () {
    test('is a single batch when the recipe defines no maximum', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('30', Unit.portion),
      );
      expect(plan.fullBatchCount, 1);
      expect(plan.fullBatchYield, Quantity.parse('30', Unit.portion));
      expect(plan.remainderYield, isNull);
      expect(plan.batchCount, 1);
    });

    test('divides evenly into full batches', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('30', Unit.portion),
        maxBatchYield: Quantity.parse('10', Unit.portion),
      );
      expect(plan.fullBatchCount, 3);
      expect(plan.remainderYield, isNull);
      expect(plan.batchCount, 3);
    });

    test('adds a remainder batch when it does not divide evenly', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('25', Unit.portion),
        maxBatchYield: Quantity.parse('10', Unit.portion),
      );
      expect(plan.fullBatchCount, 2);
      expect(plan.remainderYield, Quantity.parse('5', Unit.portion));
      expect(plan.batchCount, 3);
    });

    test('is a single remainder batch below one maximum', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('4', Unit.portion),
        maxBatchYield: Quantity.parse('10', Unit.portion),
      );
      expect(plan.fullBatchCount, 0);
      expect(plan.remainderYield, Quantity.parse('4', Unit.portion));
      expect(plan.batchCount, 1);
    });

    test('converts the maximum into the target unit', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('3', Unit.kilogram),
        maxBatchYield: Quantity.parse('1000', Unit.gram),
      );
      expect(plan.fullBatchCount, 3);
      expect(plan.remainderYield, isNull);
    });

    test('handles a fractional remainder exactly', () {
      final plan = BatchPlan.decompose(
        target: Quantity.parse('7.5', Unit.kilogram),
        maxBatchYield: Quantity.parse('2', Unit.kilogram),
      );
      expect(plan.fullBatchCount, 3);
      expect(plan.remainderYield, Quantity.parse('1.5', Unit.kilogram));
      expect(plan.batchCount, 4);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/scaling/batch_plan_test.dart`
Expected: FAIL — `Undefined name 'BatchPlan'`.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/scaling/batch_plan.dart`:

```dart
import 'package:decimal/decimal.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/domain/units/quantity.dart';

/// How a production run is split into batches.
@immutable
final class BatchPlan {
  /// Splits [target] into full batches of [maxBatchYield] plus a remainder.
  ///
  /// Without a maximum the run is a single batch producing the whole target.
  factory BatchPlan.decompose({
    required Quantity target,
    Quantity? maxBatchYield,
  }) {
    if (maxBatchYield == null || maxBatchYield.isZero) {
      return BatchPlan._(
        fullBatchCount: 1,
        fullBatchYield: target,
        remainderYield: null,
      );
    }

    final max = maxBatchYield.convertTo(target.unit);
    final full = (target.amount / max.amount).floor();
    final consumed = max.scaleBy(Decimal.fromBigInt(full).toRational());
    final remainder = Quantity.fromRational(
      target.amount - consumed.amount,
      target.unit,
    );

    return BatchPlan._(
      fullBatchCount: full.toInt(),
      fullBatchYield: max,
      remainderYield: remainder.isZero ? null : remainder,
    );
  }

  const BatchPlan._({
    required this.fullBatchCount,
    required this.fullBatchYield,
    required this.remainderYield,
  });

  /// How many batches produce a full [fullBatchYield].
  final int fullBatchCount;

  /// The yield of one full batch.
  final Quantity fullBatchYield;

  /// The yield of the trailing partial batch, when there is one.
  final Quantity? remainderYield;

  /// Every batch the run performs, counting a non-empty remainder as one.
  int get batchCount => fullBatchCount + (remainderYield == null ? 0 : 1);
}
```

Add `export 'scaling/batch_plan.dart';` to `lib/domain/domain.dart`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/scaling/batch_plan_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): decompose a target yield into full and remainder batches"
```

---

### Task 8: Warnings and the single-level calculator

**Files:**

- Create: `lib/domain/warnings.dart`, `lib/domain/scaling/scaled_component.dart`, `lib/domain/scaling/production_calculator.dart`
- Modify: `lib/domain/domain.dart`
- Test: `test/domain/scaling/production_calculator_test.dart`

**Interfaces:**

- Consumes: `Recipe`, `RecipeComponent`, `ScalingBehavior`, `Quantity`, `ScaledQuantity`, `RoundingRule`, `BatchPlan`, `RecipeDependencyGraph`, `IncompatibleYieldUnitError`.
- Produces:
  - `sealed class ProductionWarning`, `ManualComponentWarning(String componentId)`, `RoundingAdjustedWarning(String componentId)`, `ArchivedDependencyWarning(String recipeId)`.
  - `ScaledComponent` with `RecipeComponent source`, `ScaledQuantity? total`, `List<ScaledQuantity?> perBatch`, `ProductionResult? subRecipe`.
  - `ProductionResult` with `Rational scaleRatio`, `BatchPlan batchPlan`, `List<ScaledComponent> components`, `List<ProductionWarning> warnings`, `bool get hasBlockingWarnings`.
  - `ProductionCalculator.calculate({required Recipe recipe, required Quantity targetYield, Map<String, Recipe> recipeIndex = const {}})`.

Sub-recipe expansion arrives in Task 9; this task leaves `ScaledComponent.subRecipe` null and treats a `SubRecipeRef` line as a plain quantity.

- [ ] **Step 1: Write the failing test**

Create `test/domain/scaling/production_calculator_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe bread({Quantity? maxBatchYield}) {
  return Recipe(
    id: 'bread',
    revision: 1,
    name: 'Bread',
    baseYield: Quantity.parse('10', Unit.portion),
    maxBatchYield: maxBatchYield,
    components: [
      RecipeComponent(
        id: 'flour',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'yeast',
        target: const IngredientRef('yeast'),
        baseQuantity: Quantity.parse('7', Unit.gram),
        behavior: ScalingBehavior.perBatch,
        displayOrder: 1,
      ),
      RecipeComponent(
        id: 'pan-grease',
        target: const IngredientRef('butter'),
        baseQuantity: Quantity.parse('20', Unit.gram),
        behavior: ScalingBehavior.fixedOnce,
        displayOrder: 2,
      ),
      RecipeComponent(
        id: 'salt',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        note: 'to taste',
        displayOrder: 3,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

ScaledComponent componentById(ProductionResult result, String id) =>
    result.components.firstWhere((c) => c.source.id == id);

void main() {
  const calculator = ProductionCalculator();

  group('ProductionCalculator', () {
    test('a target equal to the base yield changes nothing', () {
      final result = calculator.calculate(
        recipe: bread(),
        targetYield: Quantity.parse('10', Unit.portion),
      );
      expect(result.scaleRatio, Rational.one);
      expect(
        componentById(result, 'flour').total!.exact,
        Quantity.parse('1', Unit.kilogram),
      );
    });

    test('scales a proportional component by the ratio', () {
      final result = calculator.calculate(
        recipe: bread(),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      expect(result.scaleRatio, Rational.fromInt(5, 2));
      expect(
        componentById(result, 'flour').total!.exact,
        Quantity.parse('2.5', Unit.kilogram),
      );
    });

    test('keeps a non-terminating ratio exact', () {
      final result = calculator.calculate(
        recipe: bread(),
        targetYield: Quantity.parse('10', Unit.portion).scaleBy(
          Rational(BigInt.one, BigInt.from(3)),
        ),
      );
      final flour = componentById(result, 'flour').total!.exact;
      expect(flour.isExactDecimal, isFalse);
      expect(flour.amount, Rational(BigInt.one, BigInt.from(3)));
    });

    test('multiplies a per-batch component by the batch count', () {
      final result = calculator.calculate(
        recipe: bread(maxBatchYield: Quantity.parse('10', Unit.portion)),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      expect(result.batchPlan.batchCount, 3);
      expect(
        componentById(result, 'yeast').total!.exact,
        Quantity.parse('21', Unit.gram),
      );
    });

    test('includes a fixed-once component exactly once', () {
      final result = calculator.calculate(
        recipe: bread(maxBatchYield: Quantity.parse('10', Unit.portion)),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      expect(
        componentById(result, 'pan-grease').total!.exact,
        Quantity.parse('20', Unit.gram),
      );
    });

    test('leaves a manual component unresolved and warns', () {
      final result = calculator.calculate(
        recipe: bread(),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      expect(componentById(result, 'salt').total, isNull);
      expect(
        result.warnings,
        contains(isA<ManualComponentWarning>()),
      );
      expect(result.hasBlockingWarnings, isTrue);
    });

    test('reports per-batch quantities for every batch', () {
      final result = calculator.calculate(
        recipe: bread(maxBatchYield: Quantity.parse('10', Unit.portion)),
        targetYield: Quantity.parse('25', Unit.portion),
      );
      final flour = componentById(result, 'flour');
      expect(flour.perBatch, hasLength(3));
      expect(flour.perBatch[0]!.exact, Quantity.parse('1', Unit.kilogram));
      expect(flour.perBatch[2]!.exact, Quantity.parse('0.5', Unit.kilogram));
    });

    test('rounds a display quantity and warns that it changed', () {
      final recipe = Recipe(
        id: 'buns',
        revision: 1,
        name: 'Buns',
        baseYield: Quantity.parse('10', Unit.portion),
        components: [
          RecipeComponent(
            id: 'eggs',
            target: const IngredientRef('egg'),
            baseQuantity: Quantity.parse('3', Unit.count('item')),
            behavior: ScalingBehavior.proportional,
            rounding: RoundingRule.upToIncrement(Decimal.one),
            displayOrder: 0,
          ),
        ],
        modifiedAt: DateTime.utc(2026, 9, 6),
      );
      final result = calculator.calculate(
        recipe: recipe,
        targetYield: Quantity.parse('15', Unit.portion),
      );
      final eggs = componentById(result, 'eggs').total!;
      expect(eggs.exact.amount, Rational.fromInt(9, 2));
      expect(eggs.displayed.amount, Rational.fromInt(5));
      expect(result.warnings, contains(const RoundingAdjustedWarning('eggs')));
      expect(result.hasBlockingWarnings, isFalse);
    });

    test('rejects a target yield in another dimension', () {
      expect(
        () => calculator.calculate(
          recipe: bread(),
          targetYield: Quantity.parse('5', Unit.kilogram),
        ),
        throwsA(isA<IncompatibleYieldUnitError>()),
      );
    });

    test('rejects a zero target yield', () {
      expect(
        () => calculator.calculate(
          recipe: bread(),
          targetYield: Quantity.parse('0', Unit.portion),
        ),
        throwsA(isA<InvalidTargetYieldError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/scaling/production_calculator_test.dart`
Expected: FAIL — `Undefined name 'ProductionCalculator'`.

- [ ] **Step 3: Write the implementation**

Append to `lib/domain/errors.dart`:

```dart
/// Raised when a target yield is missing, zero, or negative.
final class InvalidTargetYieldError extends DomainError {
  InvalidTargetYieldError()
    : super('a production run needs a positive target yield');
}
```

Create `lib/domain/warnings.dart`:

```dart
import 'package:meta/meta.dart';

/// Something the operator must see before a run is finalized.
@immutable
sealed class ProductionWarning {
  const ProductionWarning();

  /// Whether the run may not be finalized until this is acknowledged.
  bool get isBlocking;
}

/// A manual component has no numeric result until the operator supplies one.
final class ManualComponentWarning extends ProductionWarning {
  /// Creates the warning for [componentId].
  const ManualComponentWarning(this.componentId);

  /// The component that needs an operator value.
  final String componentId;

  @override
  bool get isBlocking => true;

  @override
  bool operator ==(Object other) =>
      other is ManualComponentWarning && other.componentId == componentId;

  @override
  int get hashCode => Object.hash('manual', componentId);
}

/// Display rounding moved a component away from its calculated value.
final class RoundingAdjustedWarning extends ProductionWarning {
  /// Creates the warning for [componentId].
  const RoundingAdjustedWarning(this.componentId);

  /// The component whose displayed value differs from the exact one.
  final String componentId;

  @override
  bool get isBlocking => false;

  @override
  bool operator ==(Object other) =>
      other is RoundingAdjustedWarning && other.componentId == componentId;

  @override
  int get hashCode => Object.hash('rounding', componentId);
}

/// A referenced recipe is archived.
final class ArchivedDependencyWarning extends ProductionWarning {
  /// Creates the warning for [recipeId].
  const ArchivedDependencyWarning(this.recipeId);

  /// The archived recipe.
  final String recipeId;

  @override
  bool get isBlocking => true;

  @override
  bool operator ==(Object other) =>
      other is ArchivedDependencyWarning && other.recipeId == recipeId;

  @override
  int get hashCode => Object.hash('archived', recipeId);
}
```

Create `lib/domain/scaling/scaled_component.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:prep_book/domain/recipe/component.dart';
import 'package:prep_book/domain/scaling/batch_plan.dart';
import 'package:prep_book/domain/units/rounding.dart';
import 'package:prep_book/domain/warnings.dart';
import 'package:rational/rational.dart';

/// One calculated line of a production result.
@immutable
final class ScaledComponent {
  /// Creates a calculated line.
  const ScaledComponent({
    required this.source,
    required this.total,
    required this.perBatch,
    this.subRecipe,
  });

  /// The recipe line this row was calculated from.
  final RecipeComponent source;

  /// The total for the whole run, absent for an unresolved manual line.
  final ScaledQuantity? total;

  /// The amount for each batch, in batch order.
  final List<ScaledQuantity?> perBatch;

  /// The expanded result when this line references another recipe.
  final ProductionResult? subRecipe;
}

/// The outcome of scaling one recipe to a target yield.
@immutable
final class ProductionResult {
  /// Creates a production result.
  ProductionResult({
    required this.scaleRatio,
    required this.batchPlan,
    required List<ScaledComponent> components,
    required List<ProductionWarning> warnings,
  }) : components = List.unmodifiable(components),
       warnings = List.unmodifiable(warnings);

  /// The proportional ratio, target over base.
  final Rational scaleRatio;

  /// How the run splits into batches.
  final BatchPlan batchPlan;

  /// The calculated lines, in the recipe's display order.
  final List<ScaledComponent> components;

  /// Everything the operator must see, including nested recipes' warnings.
  final List<ProductionWarning> warnings;

  /// Whether any warning must be acknowledged before finalizing.
  bool get hasBlockingWarnings => warnings.any((w) => w.isBlocking);
}
```

Create `lib/domain/scaling/production_calculator.dart`:

```dart
import 'package:prep_book/domain/errors.dart';
import 'package:prep_book/domain/recipe/component.dart';
import 'package:prep_book/domain/recipe/recipe.dart';
import 'package:prep_book/domain/recipe/scaling_behavior.dart';
import 'package:prep_book/domain/scaling/batch_plan.dart';
import 'package:prep_book/domain/scaling/scaled_component.dart';
import 'package:prep_book/domain/units/quantity.dart';
import 'package:prep_book/domain/units/rounding.dart';
import 'package:prep_book/domain/warnings.dart';
import 'package:rational/rational.dart';

/// Turns a recipe and a target yield into an exact production result.
final class ProductionCalculator {
  /// Creates a calculator. It holds no state.
  const ProductionCalculator();

  /// Scales [recipe] to [targetYield].
  ///
  /// [recipeIndex] supplies sub-recipes; it is unused until nested expansion
  /// is added.
  ProductionResult calculate({
    required Recipe recipe,
    required Quantity targetYield,
    Map<String, Recipe> recipeIndex = const {},
  }) {
    if (targetYield.isZero) throw InvalidTargetYieldError();
    if (!recipe.baseYield.unit.canConvertTo(targetYield.unit)) {
      throw IncompatibleYieldUnitError(recipe.baseYield.unit, targetYield.unit);
    }

    final target = targetYield.convertTo(recipe.baseYield.unit);
    final ratio = target.amount / recipe.baseYield.amount;
    final plan = BatchPlan.decompose(
      target: target,
      maxBatchYield: recipe.maxBatchYield,
    );

    final warnings = <ProductionWarning>[];
    final components = [
      for (final component in recipe.components)
        _scale(component, ratio, plan, warnings),
    ];

    return ProductionResult(
      scaleRatio: ratio,
      batchPlan: plan,
      components: components,
      warnings: warnings,
    );
  }

  ScaledComponent _scale(
    RecipeComponent component,
    Rational ratio,
    BatchPlan plan,
    List<ProductionWarning> warnings,
  ) {
    // A null base quantity means manual; RecipeComponent guarantees it.
    final base = component.baseQuantity;
    if (base == null) {
      warnings.add(ManualComponentWarning(component.id));
      return ScaledComponent(
        source: component,
        total: null,
        perBatch: List.filled(plan.batchCount, null),
      );
    }

    final List<Quantity> perBatchExact;
    if (component.behavior == ScalingBehavior.perBatch) {
      perBatchExact = List.filled(plan.batchCount, base);
    } else if (component.behavior == ScalingBehavior.fixedOnce) {
      perBatchExact = [
        base,
        for (var i = 1; i < plan.batchCount; i++)
          Quantity.fromRational(Rational.zero, base.unit),
      ];
    } else {
      perBatchExact = [
        for (final batchRatio in _batchRatios(plan))
          base.scaleBy(ratio * batchRatio),
      ];
    }

    final totalExact = perBatchExact.reduce((a, b) => a + b);
    final total = _present(component, totalExact, warnings);

    return ScaledComponent(
      source: component,
      total: total,
      perBatch: [
        for (final value in perBatchExact) _present(component, value, null),
      ],
    );
  }

  /// Each batch's share of the whole run, in batch order.
  Iterable<Rational> _batchRatios(BatchPlan plan) sync* {
    final whole = plan.fullBatchYield.scaleBy(
      Rational.fromInt(plan.fullBatchCount),
    );
    final remainder = plan.remainderYield;
    final total = remainder == null ? whole : whole + remainder;

    for (var i = 0; i < plan.fullBatchCount; i++) {
      yield plan.fullBatchYield.amount / total.amount;
    }
    if (remainder != null) {
      yield remainder.amount / total.amount;
    }
  }

  ScaledQuantity _present(
    RecipeComponent component,
    Quantity exact,
    List<ProductionWarning>? warnings,
  ) {
    final rule = component.rounding;
    if (rule == null) return ScaledQuantity.unrounded(exact);

    final scaled = ScaledQuantity.rounded(exact: exact, rule: rule);
    if (scaled.wasRounded && warnings != null) {
      warnings.add(RoundingAdjustedWarning(component.id));
    }
    return scaled;
  }
}
```

Add these exports to `lib/domain/domain.dart`:

```dart
export 'scaling/production_calculator.dart';
export 'scaling/scaled_component.dart';
export 'warnings.dart';
```

Note on `_batchRatios`: a proportional component is split across batches in proportion to each batch's yield, so the per-batch values always sum to the total.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/scaling/production_calculator_test.dart`
Expected: PASS, 10 tests.

- [ ] **Step 5: Verify the whole suite**

Run: `flutter analyze && very_good test --coverage --min-coverage 100`
Expected: no analyzer issues, all tests pass, coverage at 100 percent.

- [ ] **Step 6: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): scale a recipe into totals, batches, and warnings"
```

---

### Task 9: Nested sub-recipe expansion

**Files:**

- Modify: `lib/domain/scaling/production_calculator.dart`
- Test: `test/domain/scaling/nested_recipe_test.dart`

**Interfaces:**

- Consumes: everything from Task 8, plus `RecipeDependencyGraph` from Task 6 and `ArchivedDependencyWarning`.
- Produces: `ScaledComponent.subRecipe` populated for every `SubRecipeRef` line, with nested warnings lifted into the parent's `warnings` list. `calculate` now throws `RecipeCycleError` or `MissingDependencyError` when the graph is unresolvable.

- [ ] **Step 1: Write the failing test**

Create `test/domain/scaling/nested_recipe_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe dough({bool isArchived = false}) {
  return Recipe(
    id: 'dough',
    revision: 1,
    name: 'Dough',
    baseYield: Quantity.parse('2', Unit.kilogram),
    isArchived: isArchived,
    components: [
      RecipeComponent(
        id: 'dough-flour',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1.2', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'dough-salt',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

Recipe pie() {
  return Recipe(
    id: 'pie',
    revision: 1,
    name: 'Pie',
    baseYield: Quantity.parse('4', Unit.portion),
    components: [
      RecipeComponent(
        id: 'pie-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  const calculator = ProductionCalculator();

  group('nested recipes', () {
    test('expands a sub-recipe against the parent quantity', () {
      final result = calculator.calculate(
        recipe: pie(),
        targetYield: Quantity.parse('8', Unit.portion),
        recipeIndex: {'dough': dough(), 'pie': pie()},
      );

      final line = result.components.single;
      expect(line.total!.exact, Quantity.parse('2', Unit.kilogram));

      final nested = line.subRecipe!;
      expect(nested.scaleRatio, Rational.one);
      expect(
        nested.components.first.total!.exact,
        Quantity.parse('1.2', Unit.kilogram),
      );
    });

    test('lifts a nested blocking warning into the parent', () {
      final result = calculator.calculate(
        recipe: pie(),
        targetYield: Quantity.parse('8', Unit.portion),
        recipeIndex: {'dough': dough(), 'pie': pie()},
      );
      expect(result.warnings, contains(isA<ManualComponentWarning>()));
      expect(result.hasBlockingWarnings, isTrue);
    });

    test('warns when a dependency is archived', () {
      final result = calculator.calculate(
        recipe: pie(),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough(isArchived: true), 'pie': pie()},
      );
      expect(
        result.warnings,
        contains(const ArchivedDependencyWarning('dough')),
      );
      expect(result.hasBlockingWarnings, isTrue);
    });

    test('rejects a cycle before calculating', () {
      final a = Recipe(
        id: 'a',
        revision: 1,
        name: 'A',
        baseYield: Quantity.parse('1', Unit.portion),
        components: [
          RecipeComponent(
            id: 'a-b',
            target: const SubRecipeRef('a'),
            baseQuantity: Quantity.parse('1', Unit.portion),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
        modifiedAt: DateTime.utc(2026, 9, 6),
      );
      expect(
        () => calculator.calculate(
          recipe: a,
          targetYield: Quantity.parse('2', Unit.portion),
          recipeIndex: {'a': a},
        ),
        throwsA(isA<RecipeCycleError>()),
      );
    });

    test('rejects a missing dependency', () {
      expect(
        () => calculator.calculate(
          recipe: pie(),
          targetYield: Quantity.parse('4', Unit.portion),
          recipeIndex: {'pie': pie()},
        ),
        throwsA(isA<MissingDependencyError>()),
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/scaling/nested_recipe_test.dart`
Expected: FAIL — `line.subRecipe` is null.

- [ ] **Step 3: Modify the calculator**

In `lib/domain/scaling/production_calculator.dart`, add the graph import:

```dart
import 'package:prep_book/domain/graph/recipe_dependency_graph.dart';
```

Validate the graph once at the top of `calculate`, right after the target-yield checks:

```dart
    if (recipeIndex.isNotEmpty) {
      RecipeDependencyGraph(recipeIndex).assertResolvable(recipe.id);
    }
```

Change `_scale` to take the index and to expand a sub-recipe after computing its total. Replace the `return ScaledComponent(...)` at the end of `_scale` with:

```dart
    final expanded = switch (component.target) {
      SubRecipeRef(:final recipeId) when total != null => _expand(
        recipeId,
        total.displayed,
        recipeIndex,
        warnings,
      ),
      _ => null,
    };

    return ScaledComponent(
      source: component,
      total: total,
      perBatch: [
        for (final value in perBatchExact) _present(component, value, null),
      ],
      subRecipe: expanded,
    );
```

and add the expansion helper:

```dart
  ProductionResult? _expand(
    String recipeId,
    Quantity requiredYield,
    Map<String, Recipe> recipeIndex,
    List<ProductionWarning> warnings,
  ) {
    final child = recipeIndex[recipeId];
    if (child == null) return null;
    if (child.isArchived) {
      warnings.add(ArchivedDependencyWarning(recipeId));
    }

    final nested = calculate(
      recipe: child,
      targetYield: requiredYield,
      recipeIndex: recipeIndex,
    );
    warnings.addAll(nested.warnings);
    return nested;
  }
```

Thread `recipeIndex` through the `_scale` call in `calculate` and through its signature. The recursion terminates because `assertResolvable` has already rejected every cycle.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/scaling`
Expected: PASS, all scaling tests including the 5 new ones.

- [ ] **Step 5: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): expand nested sub-recipes recursively"
```

---

### Task 10: The immutable production-run snapshot

**Files:**

- Create: `lib/domain/production_run.dart`
- Modify: `lib/domain/domain.dart`
- Test: `test/domain/production_run_test.dart`

**Interfaces:**

- Consumes: `Recipe`, `Quantity`, `ProductionResult`, `ProductionWarning`.
- Produces:
  - `ProductionRun({required String id, required DateTime createdAt, required Recipe recipe, required Map<String, Recipe> dependencySnapshot, required Quantity targetYield, required ProductionResult result, Map<String, Quantity> overrides, Set<ProductionWarning> acknowledgedWarnings})`
  - `ProductionRun acknowledge(ProductionWarning warning)`, `ProductionRun override(String componentId, Quantity value)`, `bool get isFinalizable`.

- [ ] **Step 1: Write the failing test**

Create `test/domain/production_run_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe soup({String name = 'Soup'}) {
  return Recipe(
    id: 'soup',
    revision: 1,
    name: name,
    baseYield: Quantity.parse('10', Unit.portion),
    components: [
      RecipeComponent(
        id: 'stock',
        target: const IngredientRef('stock'),
        baseQuantity: Quantity.parse('2', Unit.liter),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'pepper',
        target: const IngredientRef('pepper'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

ProductionRun buildRun() {
  const calculator = ProductionCalculator();
  final recipe = soup();
  final target = Quantity.parse('20', Unit.portion);
  return ProductionRun(
    id: 'run-1',
    createdAt: DateTime.utc(2026, 9, 6, 9),
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: target,
    result: calculator.calculate(recipe: recipe, targetYield: target),
  );
}

void main() {
  group('ProductionRun', () {
    test('records the recipe revision it was computed from', () {
      final run = buildRun();
      expect(run.recipeId, 'soup');
      expect(run.recipeRevision, 1);
    });

    test('a later recipe edit does not change the snapshot', () {
      final run = buildRun();
      final edited = soup(name: 'Renamed soup');

      expect(edited.name, 'Renamed soup');
      expect(run.recipe.name, 'Soup');
      expect(
        run.result.components.first.total!.exact,
        Quantity.parse('4', Unit.liter),
      );
    });

    test('is not finalizable while a blocking warning stands', () {
      expect(buildRun().isFinalizable, isFalse);
    });

    test('becomes finalizable once every blocking warning is acknowledged', () {
      final run = buildRun();
      final acknowledged = run.acknowledge(
        const ManualComponentWarning('pepper'),
      );
      expect(acknowledged.isFinalizable, isTrue);
      expect(run.isFinalizable, isFalse);
    });

    test('records an operator override without touching the result', () {
      final run = buildRun();
      final overridden = run.override(
        'stock',
        Quantity.parse('5', Unit.liter),
      );

      expect(overridden.overrides['stock'], Quantity.parse('5', Unit.liter));
      expect(
        overridden.result.components.first.total!.exact,
        Quantity.parse('4', Unit.liter),
      );
      expect(run.overrides, isEmpty);
    });

    test('exposes unmodifiable collections', () {
      final run = buildRun();
      expect(
        () => run.overrides['stock'] = Quantity.parse('1', Unit.liter),
        throwsUnsupportedError,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/production_run_test.dart`
Expected: FAIL — `Undefined name 'ProductionRun'`.

- [ ] **Step 3: Write the implementation**

Create `lib/domain/production_run.dart`:

```dart
import 'package:meta/meta.dart';
import 'package:prep_book/domain/recipe/recipe.dart';
import 'package:prep_book/domain/scaling/scaled_component.dart';
import 'package:prep_book/domain/units/quantity.dart';
import 'package:prep_book/domain/warnings.dart';

/// A finished calculation, frozen at the moment it was computed.
///
/// Editing, archiving, or deleting the source recipe never changes a stored
/// run: the run holds its own copy of the recipe revision and every recipe it
/// depended on.
@immutable
final class ProductionRun {
  /// Creates a run snapshot.
  ProductionRun({
    required this.id,
    required this.createdAt,
    required this.recipe,
    required Map<String, Recipe> dependencySnapshot,
    required this.targetYield,
    required this.result,
    Map<String, Quantity> overrides = const {},
    Set<ProductionWarning> acknowledgedWarnings = const {},
  }) : dependencySnapshot = Map.unmodifiable(dependencySnapshot),
       overrides = Map.unmodifiable(overrides),
       acknowledgedWarnings = Set.unmodifiable(acknowledgedWarnings);

  /// Stable identifier.
  final String id;

  /// When the run was calculated.
  final DateTime createdAt;

  /// The recipe revision the calculation used.
  final Recipe recipe;

  /// Every recipe the calculation depended on, as it was at that moment.
  final Map<String, Recipe> dependencySnapshot;

  /// The yield the operator asked for.
  final Quantity targetYield;

  /// The calculated result.
  final ProductionResult result;

  /// Temporary operator values, keyed by component identifier.
  final Map<String, Quantity> overrides;

  /// Warnings the operator has seen and accepted.
  final Set<ProductionWarning> acknowledgedWarnings;

  /// The identifier of the recipe this run was computed from.
  String get recipeId => recipe.id;

  /// The revision of that recipe.
  int get recipeRevision => recipe.revision;

  /// Whether every blocking warning has been acknowledged.
  bool get isFinalizable => result.warnings
      .where((warning) => warning.isBlocking)
      .every(acknowledgedWarnings.contains);

  /// This run with [warning] marked as seen.
  ProductionRun acknowledge(ProductionWarning warning) =>
      _copyWith(acknowledgedWarnings: {...acknowledgedWarnings, warning});

  /// This run with an operator value recorded for [componentId].
  ///
  /// The calculated result is never rewritten, so the original value stays
  /// available for comparison.
  ProductionRun override(String componentId, Quantity value) =>
      _copyWith(overrides: {...overrides, componentId: value});

  ProductionRun _copyWith({
    Map<String, Quantity>? overrides,
    Set<ProductionWarning>? acknowledgedWarnings,
  }) {
    return ProductionRun(
      id: id,
      createdAt: createdAt,
      recipe: recipe,
      dependencySnapshot: dependencySnapshot,
      targetYield: targetYield,
      result: result,
      overrides: overrides ?? this.overrides,
      acknowledgedWarnings: acknowledgedWarnings ?? this.acknowledgedWarnings,
    );
  }
}
```

Add `export 'production_run.dart';` to `lib/domain/domain.dart`.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/domain/production_run_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): add the immutable production-run snapshot"
```

---

### Task 11: Invariant tests over generated inputs

**Files:**

- Test: `test/domain/properties/scaling_invariants_test.dart`

**Interfaces:**

- Consumes: the whole domain surface. Produces no production code.

This task adds no implementation. If an invariant fails, fix the defect it exposes in the file that owns the behavior, and say which task's code changed in the commit body.

- [ ] **Step 1: Write the invariant tests**

Create `test/domain/properties/scaling_invariants_test.dart`:

```dart
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe proportionalRecipe(String baseYield, String baseQuantity) {
  return Recipe(
    id: 'r',
    revision: 1,
    name: 'R',
    baseYield: Quantity.parse(baseYield, Unit.portion),
    components: [
      RecipeComponent(
        id: 'c',
        target: const IngredientRef('i'),
        baseQuantity: Quantity.parse(baseQuantity, Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  const calculator = ProductionCalculator();
  // A fixed seed keeps a failure reproducible.
  final random = Random(20260906);

  test('scaling by x then y equals scaling by x times y', () {
    for (var i = 0; i < 200; i++) {
      final base = Quantity.parse('${1 + random.nextInt(500)}', Unit.gram);
      final x = Rational(
        BigInt.from(1 + random.nextInt(50)),
        BigInt.from(1 + random.nextInt(50)),
      );
      final y = Rational(
        BigInt.from(1 + random.nextInt(50)),
        BigInt.from(1 + random.nextInt(50)),
      );

      expect(base.scaleBy(x).scaleBy(y), base.scaleBy(x * y));
    }
  });

  test('a positive target never produces a negative quantity', () {
    for (var i = 0; i < 200; i++) {
      final recipe = proportionalRecipe(
        '${1 + random.nextInt(100)}',
        '${1 + random.nextInt(1000)}',
      );
      final result = calculator.calculate(
        recipe: recipe,
        targetYield: Quantity.parse(
          '${1 + random.nextInt(1000)}',
          Unit.portion,
        ),
      );

      for (final component in result.components) {
        expect(component.total!.exact.amount.signum, isNonNegative);
        expect(component.total!.displayed.amount.signum, isNonNegative);
      }
    }
  });

  test('per-batch quantities sum to the total', () {
    for (var i = 0; i < 100; i++) {
      final maxBatch = 1 + random.nextInt(20);
      final target = 1 + random.nextInt(200);
      final recipe = Recipe(
        id: 'r',
        revision: 1,
        name: 'R',
        baseYield: Quantity.parse('10', Unit.portion),
        maxBatchYield: Quantity.parse('$maxBatch', Unit.portion),
        components: [
          RecipeComponent(
            id: 'c',
            target: const IngredientRef('i'),
            baseQuantity: Quantity.parse('500', Unit.gram),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
        modifiedAt: DateTime.utc(2026, 9, 6),
      );

      final result = calculator.calculate(
        recipe: recipe,
        targetYield: Quantity.parse('$target', Unit.portion),
      );

      final component = result.components.single;
      final summed = component.perBatch
          .map((value) => value!.exact)
          .reduce((a, b) => a + b);
      expect(summed, component.total!.exact);
    }
  });

  test('rounding never lowers the displayed value', () {
    for (var i = 0; i < 100; i++) {
      final rule = RoundingRule.upToIncrement(
        Decimal.parse('0.${1 + random.nextInt(8)}'),
      );
      final value = Quantity.parse(
        '${random.nextInt(1000)}.${random.nextInt(100)}',
        Unit.gram,
      );
      final scaled = ScaledQuantity.rounded(exact: value, rule: rule);
      expect(scaled.displayed.compareTo(scaled.exact), greaterThanOrEqualTo(0));
    }
  });
}
```

- [ ] **Step 2: Run the invariant tests**

Run: `flutter test test/domain/properties/scaling_invariants_test.dart`
Expected: PASS, 4 tests. A failure here is a defect in Tasks 3, 4, 7, or 8 — fix it there, not by weakening the invariant.

- [ ] **Step 3: Run the full gate**

Run: `flutter analyze && very_good test --coverage --min-coverage 100 && dart run bloc_tools:bloc lint .`
Expected: clean analyzer, all tests pass, coverage at 100 percent, no bloc lint issues.

- [ ] **Step 4: Commit**

```bash
git add test/domain
git commit -m "test(domain): add scaling invariants over generated inputs"
```

---

### Task 12: Document the domain in CLAUDE.md

**Files:**

- Modify: `CLAUDE.md`

**Interfaces:**

- Consumes: the finished domain. Produces no code.

- [ ] **Step 1: Replace the "Current state versus target architecture" section**

The section currently says none of the six units exist. Replace its second paragraph with:

```markdown
The design document defines six isolated units as the target layout:
presentation, application, domain, persistence, export, and migration.
`lib/domain/` now exists and is complete for units, quantities, rounding, the
recipe model, dependency validation, batch decomposition, scaling, nested
recipes, and the production-run snapshot. The other five units are still
targets to build, not directories to look for.

`test/domain/domain_purity_test.dart` enforces the pure-Dart rule
mechanically: it fails if any file under `lib/domain/` imports Flutter, a
platform library, or uses `double`.
```

- [ ] **Step 2: Record the representation decision**

Under "Invariants that no linter or test will catch for you", replace the exact-decimal bullet with:

```markdown
- **Exact arithmetic only; no binary floating point.** `Quantity` stores a
  `Rational`, because a scale ratio such as `1/3` has no finite decimal form
  and the spec forbids losing it. `Decimal` is the construction and display
  type only. `double` must never appear under `lib/domain/`; the purity test
  fails the build if it does.
```

- [ ] **Step 3: Verify the documentation gates**

Run `trunk fmt CLAUDE.md`, then the spell check below.
Expected: no formatting changes needed, 0 spelling issues over 6 files.

```sh
cspell --config cspell.json --no-progress --no-gitignore \
  --exclude '.superpowers/**' '**/*.md'
```

The `--no-gitignore` flag is required inside a linked worktree: `.git` is a file there rather than a directory, cspell's ignore-file resolution fails, and it silently checks zero files while reporting no issues.
Always read the "Files checked" count, never the issue count alone.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: record the finished domain layer and its representation decision"
```

---

## Coverage against the spec

| Spec section                                                | Task |
| ----------------------------------------------------------- | ---- |
| Quantity and unit model, supported dimensions               | 2, 3 |
| No inferred density, no automatic mass-to-volume conversion | 2, 3 |
| Free-form amounts as manual components                      | 5, 8 |
| Scale ratio `T / B`, positive and dimensionally compatible  | 8    |
| Batch decomposition `floor(T / M)` plus remainder           | 7    |
| `proportional`, `perBatch`, `fixedOnce`, `manual` semantics | 8    |
| Rounding increment, unrounded value preserved               | 4, 8 |
| Sub-recipes scaled recursively                              | 9    |
| Acyclic dependency graph, path named on rejection           | 6    |
| Missing or archived dependencies                            | 6, 9 |
| Immutable production-run snapshot                           | 10   |
| Domain unit depends on nothing outside pure Dart            | 1    |
| Domain unit tests listed in the spec's testing strategy     | 2-9  |
| Property and invariant tests                                | 11   |

Deferred to later plans, by design: persistence and transactions, the application use cases, the responsive presentation layer, PDF export, library backup and restore, and the development-only spreadsheet migration tool. Operator overrides are modeled in Task 10 but the review workflow that applies them belongs to the application layer.
