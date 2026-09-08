import 'package:flutter/material.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/recipe_editor/view/recipe_editor_page.dart';

/// Opens the recipe editor.
///
/// One value threaded through the library screen rather than four use cases,
/// and the one place the editor's route is built — so a screen that offers
/// "create" and a row that offers "edit" cannot drift into opening two
/// differently-configured editors.
@immutable
final class RecipeEditorLauncher {
  /// Creates a launcher over the use cases the editor reads and writes
  /// through.
  const RecipeEditorLauncher({
    required this.listLibrary,
    required this.listIngredients,
    required this.saveRecipeRevision,
    required this.saveIngredient,
  });

  /// Reads the recipes the sub-recipe picker offers.
  final ListLibrary listLibrary;

  /// Reads the ingredients the ingredient picker offers.
  final ListIngredients listIngredients;

  /// Stores the edit as the recipe's next revision.
  final SaveRecipeRevision saveRecipeRevision;

  /// Stores an ingredient the operator names while editing.
  final SaveIngredient saveIngredient;

  /// Pushes the editor over [recipe], or over a blank form when it is
  /// `null`, and returns what was stored.
  ///
  /// `null` means the operator left without saving, which is what tells a
  /// caller whether anything needs reading again.
  Future<Recipe?> open(BuildContext context, {Recipe? recipe}) =>
      Navigator.of(context).push<Recipe>(
        MaterialPageRoute(
          builder: (_) => RecipeEditorPage(
            listLibrary: listLibrary,
            listIngredients: listIngredients,
            saveRecipeRevision: saveRecipeRevision,
            saveIngredient: saveIngredient,
            recipe: recipe,
          ),
        ),
      );
}
