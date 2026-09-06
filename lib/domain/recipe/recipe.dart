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
