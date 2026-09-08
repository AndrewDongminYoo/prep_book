import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/bootstrap.dart';
import 'package:prep_book/presentation/presentation.dart';

Future<void> main() async {
  await bootstrap(
    (recipes, ingredients) => App(
      listLibrary: ListLibrary(recipes),
      searchLibrary: SearchLibrary(recipes),
      editor: RecipeEditorLauncher(
        listLibrary: ListLibrary(recipes),
        listIngredients: ListIngredients(ingredients),
        saveRecipeRevision: SaveRecipeRevision(recipes, const SystemClock()),
        saveIngredient: SaveIngredient(ingredients),
      ),
    ),
  );
}
