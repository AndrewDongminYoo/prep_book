import 'package:prep_book/championship/import/unit_alias_resolver.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/championship/model/review_recipe_draft.dart';
import 'package:prep_book/domain/domain.dart';

sealed class RecipeDraftVerification {
  const RecipeDraftVerification();
}

final class RecipeDraftVerified extends RecipeDraftVerification {
  const RecipeDraftVerified(this.draft);

  final VerifiedRecipeDraft draft;
}

final class RecipeDraftRejected extends RecipeDraftVerification {
  RecipeDraftRejected(List<String> issues) : issues = List.unmodifiable(issues);

  final List<String> issues;
}

final class VerifiedYieldDraft {
  const VerifiedYieldDraft._({required this.amount, required this.unit});

  final String amount;
  final String unit;
}

final class VerifiedRecipeDetails {
  VerifiedRecipeDetails._({
    required this.name,
    required this.baseYield,
    required this.maxBatchYield,
    required List<String> preparationNotes,
  }) : preparationNotes = List.unmodifiable(preparationNotes);

  final String name;
  final VerifiedYieldDraft baseYield;
  final VerifiedYieldDraft? maxBatchYield;
  final List<String> preparationNotes;
}

final class VerifiedRecipeComponent {
  const VerifiedRecipeComponent._({
    required this.name,
    required this.amount,
    required this.unit,
    required this.behavior,
    required this.note,
  });

  final String name;
  final String? amount;
  final String? unit;
  final DraftScalingBehavior behavior;
  final String? note;
}

final class VerifiedRecipeDraft {
  VerifiedRecipeDraft._({
    required this.sourceKind,
    required this.recipe,
    required List<VerifiedRecipeComponent> components,
  }) : components = List.unmodifiable(components);

  final RecipeImportSourceKind sourceKind;
  final VerifiedRecipeDetails recipe;
  final List<VerifiedRecipeComponent> components;
}

final class RecipeDraftVerifier {
  const RecipeDraftVerifier({this.units = const UnitAliasResolver()});

  final UnitAliasResolver units;

  RecipeDraftVerification verify(ReviewRecipeDraft draft) {
    final issues = <String>[];
    _requireText(draft.recipe.name, 'recipe.name', issues);

    final baseUnit = _requireUnit(
      draft.recipe.baseYield.unit,
      'recipe.baseYield.unit',
      issues,
    );
    _requirePositiveAmount(
      draft.recipe.baseYield.amount,
      'recipe.baseYield.amount',
      issues,
    );

    final maxBatchYield = draft.recipe.maxBatchYield;
    if (maxBatchYield == null) {
      if (!draft.recipe.isMaxBatchYieldAbsentConfirmed) {
        issues.add('recipe.maxBatchYield absence must be confirmed.');
      }
    } else {
      _requirePositiveAmount(
        maxBatchYield.amount,
        'recipe.maxBatchYield.amount',
        issues,
      );
      final maxUnit = _requireUnit(
        maxBatchYield.unit,
        'recipe.maxBatchYield.unit',
        issues,
      );
      if (baseUnit != null &&
          maxUnit != null &&
          !baseUnit.canConvertTo(maxUnit)) {
        issues.add('recipe.maxBatchYield.unit must be compatible.');
      }
    }

    for (var index = 0; index < draft.recipe.preparationNotes.length; index++) {
      _requireText(
        draft.recipe.preparationNotes[index],
        'recipe.preparationNotes[$index]',
        issues,
      );
    }

    if (draft.components.isEmpty) {
      issues.add('The recipe must contain at least one component.');
    }
    for (var index = 0; index < draft.components.length; index++) {
      final component = draft.components[index];
      final path = 'components[$index]';
      _requireText(component.name, '$path.name', issues);
      _requireBehavior(component.behavior, '$path.behavior', issues);
      if (component.note case final note?) {
        _requireText(note, '$path.note', issues);
      }

      if (component.behavior.value == DraftScalingBehavior.manual) {
        if (component.amount.value != null || component.unit.value != null) {
          issues.add('$path manual components cannot contain quantities.');
        }
      } else {
        _requirePositiveAmount(component.amount, '$path.amount', issues);
        _requireUnit(component.unit, '$path.unit', issues);
      }
    }

    if (issues.isNotEmpty) return RecipeDraftRejected(issues);
    return RecipeDraftVerified(
      VerifiedRecipeDraft._(
        sourceKind: draft.sourceKind,
        recipe: VerifiedRecipeDetails._(
          name: draft.recipe.name.value!,
          baseYield: VerifiedYieldDraft._(
            amount: draft.recipe.baseYield.amount.value!,
            unit: draft.recipe.baseYield.unit.value!,
          ),
          maxBatchYield: maxBatchYield == null
              ? null
              : VerifiedYieldDraft._(
                  amount: maxBatchYield.amount.value!,
                  unit: maxBatchYield.unit.value!,
                ),
          preparationNotes: [
            for (final note in draft.recipe.preparationNotes) note.value!,
          ],
        ),
        components: [
          for (final component in draft.components)
            VerifiedRecipeComponent._(
              name: component.name.value!,
              amount: component.amount.value,
              unit: component.unit.value,
              behavior: component.behavior.value!,
              note: component.note?.value,
            ),
        ],
      ),
    );
  }

  void _requireText(
    ReviewField<String> field,
    String path,
    List<String> issues,
  ) {
    _requireConfirmed(field, path, issues);
    if (field.value == null || field.value!.trim().isEmpty) {
      issues.add('$path must not be blank.');
    }
  }

  void _requirePositiveAmount(
    ReviewField<String> field,
    String path,
    List<String> issues,
  ) {
    _requireConfirmed(field, path, issues);
    final value = field.value;
    if (value == null) {
      issues.add('$path must contain a quantity.');
      return;
    }
    try {
      final quantity = Quantity.parse(value, Unit.gram);
      if (quantity.isZero) issues.add('$path must be greater than zero.');
    } on Object {
      issues.add('$path must be a positive decimal string.');
    }
  }

  Unit? _requireUnit(
    ReviewField<String> field,
    String path,
    List<String> issues,
  ) {
    _requireConfirmed(field, path, issues);
    final unit = units.resolve(field.value);
    if (unit == null) issues.add('$path must contain a supported unit.');
    return unit;
  }

  void _requireBehavior(
    ReviewField<DraftScalingBehavior> field,
    String path,
    List<String> issues,
  ) {
    _requireConfirmed(field, path, issues);
    if (field.value == null) issues.add('$path must contain a behavior.');
  }

  void _requireConfirmed<T>(
    ReviewField<T> field,
    String path,
    List<String> issues,
  ) {
    if (!field.isConfirmed) issues.add('$path must be confirmed.');
    for (final issue in field.activeIssues) {
      issues.add('$path: $issue');
    }
  }
}
