import 'package:prep_book/championship/import/recipe_draft_verifier.dart';
import 'package:prep_book/championship/import/unit_alias_resolver.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/domain/domain.dart';

final class ChampionshipRecipeBundle {
  ChampionshipRecipeBundle({
    required this.recipe,
    required List<Ingredient> ingredients,
  }) : ingredients = List.unmodifiable(ingredients),
       ingredientSnapshot = Map.unmodifiable({
         for (final ingredient in ingredients) ingredient.id: ingredient,
       });

  final Recipe recipe;
  final List<Ingredient> ingredients;
  final Map<String, Ingredient> ingredientSnapshot;
}

final class ChampionshipRecipeMapper {
  const ChampionshipRecipeMapper({this.units = const UnitAliasResolver()});

  final UnitAliasResolver units;

  ChampionshipRecipeBundle map(
    VerifiedRecipeDraft draft, {
    required DateTime modifiedAt,
  }) {
    final ingredientNames = <String, String>{};
    for (final component in draft.components) {
      ingredientNames.putIfAbsent(
        _normalizeName(component.name),
        component.name.trim,
      );
    }
    final ingredientIds = <String, String>{};
    var ingredientIndex = 0;
    for (final normalizedName in ingredientNames.keys) {
      ingredientIndex += 1;
      ingredientIds[normalizedName] =
          'championship-ingredient-$ingredientIndex';
    }
    final ingredients = <Ingredient>[
      for (final MapEntry(key: normalizedName, value: name)
          in ingredientNames.entries)
        Ingredient(
          id: ingredientIds[normalizedName]!,
          name: name,
          defaultUnit: _defaultUnit(draft, normalizedName),
        ),
    ];

    final baseYieldUnit = _resolveRequired(draft.recipe.baseYield.unit);
    final recipe = Recipe(
      id: 'championship-recipe-1',
      revision: 1,
      name: draft.recipe.name.trim(),
      baseYield: Quantity.parse(draft.recipe.baseYield.amount, baseYieldUnit),
      maxBatchYield: switch (draft.recipe.maxBatchYield) {
        final maxBatchYield? => Quantity.parse(
          maxBatchYield.amount,
          _resolveRequired(maxBatchYield.unit),
        ),
        null => null,
      },
      components: [
        for (var index = 0; index < draft.components.length; index += 1)
          _mapComponent(draft.components[index], ingredientIds, index),
      ],
      preparationNotes: draft.recipe.preparationNotes,
      modifiedAt: modifiedAt,
    );
    return ChampionshipRecipeBundle(recipe: recipe, ingredients: ingredients);
  }

  RecipeComponent _mapComponent(
    VerifiedRecipeComponent component,
    Map<String, String> ingredientIds,
    int index,
  ) {
    final behavior = _mapBehavior(component.behavior);
    return RecipeComponent(
      id: 'championship-component-${index + 1}',
      target: IngredientRef(ingredientIds[_normalizeName(component.name)]!),
      baseQuantity: behavior == ScalingBehavior.manual
          ? null
          : Quantity.parse(
              component.amount!,
              _resolveRequired(component.unit!),
            ),
      behavior: behavior,
      displayOrder: index,
      note: component.note,
    );
  }

  Unit _defaultUnit(VerifiedRecipeDraft draft, String normalizedName) {
    for (final component in draft.components) {
      if (_normalizeName(component.name) == normalizedName &&
          component.unit != null) {
        return _resolveRequired(component.unit!);
      }
    }
    return Unit.count('manual');
  }

  Unit _resolveRequired(String value) => units.resolve(value)!;
}

String _normalizeName(String value) => value.trim().toLowerCase();

ScalingBehavior _mapBehavior(DraftScalingBehavior behavior) =>
    switch (behavior) {
      DraftScalingBehavior.proportional => ScalingBehavior.proportional,
      DraftScalingBehavior.perBatch => ScalingBehavior.perBatch,
      DraftScalingBehavior.fixedOnce => ScalingBehavior.fixedOnce,
      DraftScalingBehavior.manual => ScalingBehavior.manual,
    };
