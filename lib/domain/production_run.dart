import 'package:meta/meta.dart';
import 'package:prep_book/domain/recipe/recipe.dart';
import 'package:prep_book/domain/scaling/scaled_component.dart';
import 'package:prep_book/domain/units/quantity.dart';
import 'package:prep_book/domain/warnings.dart';

/// Identifies one component for the purpose of an operator override:
/// the recipe it belongs to, together with its id within that recipe.
///
/// A component id is only unique within its own recipe — see
/// [ManualComponentWarning.recipeId] for why keying by component id alone
/// is unsafe once a recipe can expand nested sub-recipes.
typedef OverrideKey = (String recipeId, String componentId);

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
    Map<OverrideKey, Quantity> overrides = const {},
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

  /// Operator-entered replacement values, keyed by the recipe and component
  /// they apply to.
  ///
  /// Keying by [OverrideKey] rather than component id alone avoids the
  /// defect [ManualComponentWarning] used to have: two nested recipes that
  /// happen to share a component id would otherwise collide in this map and
  /// silently drop one operator's override. An override applies to every
  /// occurrence of that recipe within the run — a sub-recipe referenced
  /// twice is the same recipe scaled twice, so an override on it reads as
  /// "the flour in the dough", not "the flour in the second dough". Nothing
  /// in the spec asks for a finer, per-occurrence grain; a path-based key
  /// can be added later if one is ever needed.
  final Map<OverrideKey, Quantity> overrides;

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

  /// This run with an operator value recorded for the component
  /// [componentId] of the recipe [recipeId].
  ///
  /// The calculated result is never rewritten, so the original value stays
  /// available for comparison.
  ///
  /// Named rather than positional: [recipeId] and [componentId] are both
  /// plain strings, so two positional parameters of the same type would
  /// compile and silently swap when transposed, writing an override under
  /// the wrong key.
  ProductionRun override({
    required String recipeId,
    required String componentId,
    required Quantity value,
  }) => _copyWith(overrides: {...overrides, (recipeId, componentId): value});

  ProductionRun _copyWith({
    Map<OverrideKey, Quantity>? overrides,
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
