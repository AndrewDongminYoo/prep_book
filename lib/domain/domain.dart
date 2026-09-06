/// The pure-Dart production-scaling domain.
///
/// Nothing in this library may import Flutter, storage, files, or the
/// network. `test/domain/domain_purity_test.dart` enforces that.
library;

export 'package:decimal/decimal.dart' show Decimal;
export 'package:rational/rational.dart' show Rational;

export 'errors.dart';
export 'graph/recipe_dependency_graph.dart';
export 'recipe/component.dart';
export 'recipe/ingredient.dart';
export 'recipe/recipe.dart';
export 'recipe/scaling_behavior.dart';
export 'scaling/batch_plan.dart';
export 'scaling/production_calculator.dart';
export 'scaling/scaled_component.dart';
export 'units/quantity.dart';
export 'units/rounding.dart';
export 'units/unit.dart';
export 'warnings.dart';
