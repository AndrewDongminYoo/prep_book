import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/app/app.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../../presentation/fakes.dart';

void main() {
  group('App', () {
    testWidgets('opens on the recipe library', (tester) async {
      final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'r-a'));

      await tester.pumpWidget(
        App(
          listLibrary: ListLibrary(recipes),
          searchLibrary: SearchLibrary(recipes),
          archiveRecipe: ArchiveRecipe(recipes),
          duplicateRecipe: DuplicateRecipe(recipes, const FixedClock()),
          editor: buildEditorLauncher(recipes, FakeIngredientRepository()),
          production: buildProductionLauncher(recipes),
          history: _historyLauncher(),
          libraryBackup: LibraryBackupLauncher(
            createBackup: CreateLibraryBackup(_BackupGateway()),
            restoreBackup: RestoreLibraryBackup(_BackupGateway()),
            platform: _BackupPlatform(),
          ),
          restored: false,
          restoreFailure: null,
        ),
      );
      await tester.pump();

      expect(find.byType(RecipeLibraryPage), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const PageStorageKey<String>('recipe-list-pane')),
          matching: find.text('Test recipe'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('wires the row actions through to the library', (tester) async {
      final recipes = FakeRecipeRepository()..seed(buildRecipe(id: 'r-a'));

      await tester.pumpWidget(
        App(
          listLibrary: ListLibrary(recipes),
          searchLibrary: SearchLibrary(recipes),
          archiveRecipe: ArchiveRecipe(recipes),
          duplicateRecipe: DuplicateRecipe(recipes, const FixedClock()),
          editor: buildEditorLauncher(recipes, FakeIngredientRepository()),
          production: buildProductionLauncher(recipes),
          history: _historyLauncher(),
          libraryBackup: LibraryBackupLauncher(
            createBackup: CreateLibraryBackup(_BackupGateway()),
            restoreBackup: RestoreLibraryBackup(_BackupGateway()),
            platform: _BackupPlatform(),
          ),
          restored: false,
          restoreFailure: null,
        ),
      );
      await tester.pump();

      // The use cases the root receives are the ones the row acts through:
      // an archive from the menu reaches this repository.
      await tester.tap(find.byTooltip('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
          matching: find.text('Archive'),
        ),
      );
      await tester.pumpAndSettle();

      expect((await recipes.findLatest('r-a'))!.isArchived, isTrue);
      expect(find.text('Recipe archived.'), findsOneWidget);
    });
  });
}

ProductionHistoryLauncher _historyLauncher() {
  final runs = FakeProductionRunRepository();
  return ProductionHistoryLauncher(
    listHistory: ListProductionHistory(runs),
    openProductionRun: OpenProductionRun(runs),
    productionSheet: ProductionSheetLauncher(platform: _SheetPlatform()),
  );
}

final class _BackupGateway implements LibraryBackupGateway {
  @override
  Future<LibraryBackupFile> create() async => LibraryBackupFile(
    bytes: Uint8List.fromList([1]),
    suggestedName: 'backup.prepbook',
  );

  @override
  Future<void> restore(Uint8List archiveBytes) async {}
}

final class _BackupPlatform implements LibraryBackupPlatform {
  @override
  Future<Uint8List?> pickBackup() async => null;

  @override
  Future<bool> saveBackup(LibraryBackupFile backup) async => false;
}

final class _SheetPlatform implements ProductionSheetPlatform {
  @override
  Future<Uint8List> loadFontBytes() async => Uint8List(0);

  @override
  Widget preview({
    required Uint8List bytes,
    required Widget loading,
    required Widget Function(Object error) onError,
  }) => const SizedBox.shrink();

  @override
  Future<bool> print({required Uint8List bytes, required String name}) async =>
      true;

  @override
  Future<bool> share({
    required Uint8List bytes,
    required String filename,
  }) async => true;
}
