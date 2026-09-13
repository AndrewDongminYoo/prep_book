import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/bootstrap.dart';
import 'package:prep_book/presentation/presentation.dart';

Future<void> main() async {
  await bootstrap(
    builder:
        ({
          required recipes,
          required ingredients,
          required runs,
          required createLibraryBackup,
          required restoreLibraryBackup,
          required restored,
          required restoreFailure,
        }) => App(
          listLibrary: ListLibrary(recipes),
          searchLibrary: SearchLibrary(recipes),
          editor: RecipeEditorLauncher(
            listLibrary: ListLibrary(recipes),
            listIngredients: ListIngredients(ingredients),
            saveRecipeRevision: SaveRecipeRevision(
              recipes,
              const SystemClock(),
            ),
            saveIngredient: SaveIngredient(ingredients),
          ),
          production: ProductionSetupLauncher(
            StartProductionRun(
              recipes,
              ingredients,
              RandomRunIdSource(),
              const SystemClock(),
            ),
            result: ProductionResultLauncher(
              acknowledgeWarning: const AcknowledgeWarning(),
              applyOverride: const ApplyOverride(),
              saveProductionRun: SaveProductionRun(runs),
              productionSheet: const ProductionSheetLauncher(
                platform: PrintingProductionSheetPlatform(),
              ),
            ),
          ),
          libraryBackup: LibraryBackupLauncher(
            createBackup: createLibraryBackup,
            restoreBackup: restoreLibraryBackup,
            platform: const FilePickerLibraryBackupPlatform(),
          ),
          restored: restored,
          restoreFailure: restoreFailure,
        ),
  );
}
