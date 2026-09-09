/// The pure-Dart production-scaling domain.
///
/// Nothing in this library may import Flutter, storage, files, or the
/// network. `test/domain/domain_purity_test.dart` enforces that.
library;

// `RationalExt` alongside `Decimal` because `ProductionResult.scaleRatio` is
// a bare `Rational`, and that extension is the only way to render one: a run
// scaled to one third of its base yield has no finite decimal form, and
// `Rational.toString` writes it as `1/3` rather than as a number a kitchen
// reads. Named here rather than left to a consumer's own
// `package:decimal/decimal.dart` import, which the presentation layer's
// boundary test refuses.
export 'package:decimal/decimal.dart' show Decimal, RationalExt;
export 'package:rational/rational.dart' show Rational;

export 'errors.dart';
export 'graph/recipe_dependency_graph.dart';
export 'production_run.dart';
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
