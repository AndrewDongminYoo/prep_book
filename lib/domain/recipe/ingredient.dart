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
