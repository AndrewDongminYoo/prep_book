import 'package:flutter/material.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/presentation.dart';

class App extends StatelessWidget {
  const App({
    required this.listLibrary,
    required this.searchLibrary,
    super.key,
  });

  /// Reads every recipe's latest revision.
  final ListLibrary listLibrary;

  /// Filters that list by name.
  final SearchLibrary searchLibrary;

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
      ),
    );
  }
}
