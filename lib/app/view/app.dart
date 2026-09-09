import 'package:flutter/material.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/presentation.dart';

class App extends StatelessWidget {
  const App({
    required this.listLibrary,
    required this.searchLibrary,
    required this.editor,
    required this.production,
    super.key,
  });

  /// Reads every recipe's latest revision.
  final ListLibrary listLibrary;

  /// Filters that list by name.
  final SearchLibrary searchLibrary;

  /// Opens the recipe editor, from the library's create action and from
  /// each row.
  final RecipeEditorLauncher editor;

  /// Opens production setup, from each library row's Production Run
  /// action.
  final ProductionSetupLauncher production;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        appBarTheme: AppBarTheme(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        useMaterial3: true,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RecipeLibraryPage(
        listLibrary: listLibrary,
        searchLibrary: searchLibrary,
        editor: editor,
        production: production,
      ),
    );
  }
}
