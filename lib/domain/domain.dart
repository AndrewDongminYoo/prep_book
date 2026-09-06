/// The pure-Dart production-scaling domain.
///
/// Nothing in this library may import Flutter, storage, files, or the
/// network. `test/domain/domain_purity_test.dart` enforces that.
library;

export 'package:decimal/decimal.dart' show Decimal;
export 'package:rational/rational.dart' show Rational;

export 'errors.dart';
export 'units/quantity.dart';
export 'units/unit.dart';
