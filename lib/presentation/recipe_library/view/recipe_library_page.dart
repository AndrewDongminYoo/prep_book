import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/production_setup/production_setup.dart';
import 'package:prep_book/presentation/recipe_editor/recipe_editor.dart';
import 'package:prep_book/presentation/recipe_library/recipe_library.dart';
import 'package:prep_book/presentation/units/readable_quantity.dart';

/// The recipe library: the screen the app opens on.
///
/// Takes the two use cases rather than a repository, so nothing on this
/// screen can reach storage directly.
class RecipeLibraryPage extends StatelessWidget {
  /// Creates the page over the use cases its cubit reads through.
  const RecipeLibraryPage({
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

  /// Opens the editor, which both the create action and each row's edit
  /// action go through.
  final RecipeEditorLauncher editor;

  /// Opens production setup, which each row's Production Run action goes
  /// through.
  final ProductionSetupLauncher production;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = RecipeLibraryCubit(listLibrary, searchLibrary);
        // The first read starts with the screen; nothing awaits it,
        // because the state it emits is what the view rebuilds from.
        unawaited(cubit.load());
        return cubit;
      },
      child: RecipeLibraryView(editor: editor, production: production),
    );
  }
}

/// The library's rendering, split from [RecipeLibraryPage] so the widget
/// that provides the cubit is not also the widget that reads it.
class RecipeLibraryView extends StatelessWidget {
  /// Creates the view.
  const RecipeLibraryView({
    required this.editor,
    required this.production,
    super.key,
  });

  /// Opens the editor for the create action and for each row.
  final RecipeEditorLauncher editor;

  /// Opens production setup for a row's Production Run action.
  final ProductionSetupLauncher production;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.recipeLibraryTitle),
        // In the app bar rather than a floating action button, which is
        // Material's position for the *dominant* action — and the design
        // document gives that to Production Run and calls create
        // secondary. It also keeps the button off the last row: the
        // scaffold reserves no room under a floating one, and the space
        // that would have to be reserved is most of a landscape phone's
        // body with the keyboard up.
        actions: [
          IconButton(
            tooltip: l10n.recipeLibraryCreate,
            icon: const Icon(Icons.add),
            onPressed: () => _openEditor(context, editor),
          ),
        ],
      ),
      // One scroll view, filter row included, rather than a column holding
      // the list in an `Expanded`. The keyboard takes its inset off the
      // body's height, and on a short viewport — a phone in landscape, a
      // narrow split window — what is left is less than the search field,
      // the switch and the divider stacked. A column there gives the list
      // nothing and overflows; here the same squeeze just makes the filter
      // row scroll, and the rows stay reachable.
      //
      // The scaffold keeps the left, right and bottom insets in the body's
      // `MediaQuery` and applies none of them — only the top is consumed,
      // by the app bar — and a scroll view consumes none either. So in
      // landscape on a phone with a cutout the field and the rows would lay
      // out under it, and the last row under the home indicator. This is
      // the widget that applies them.
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Outside the builders on purpose. A keystroke emits the query
            // at once, and the search it starts emits again when it lands,
            // so a search field rebuilt under the caret while the operator
            // is still typing is the failure this arrangement avoids.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  decoration: InputDecoration(
                    labelText: l10n.recipeLibrarySearchLabel,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: context.read<RecipeLibraryCubit>().search,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: BlocBuilder<RecipeLibraryCubit, RecipeLibraryState>(
                builder: (context, state) => SwitchListTile(
                  value: state.showArchived,
                  title: Text(l10n.recipeLibraryShowArchived),
                  onChanged: (show) => context
                      .read<RecipeLibraryCubit>()
                      .showArchived(show: show),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: Divider(height: 1)),
            BlocBuilder<RecipeLibraryCubit, RecipeLibraryState>(
              builder: (context, state) => _LibraryBody(
                state: state,
                editor: editor,
                production: production,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Whichever of the four bodies the current [state] calls for, as the
/// sliver the enclosing scroll view expects.
///
/// The three that render one message fill what is left of the viewport, so
/// a message still centres on a tall screen, and shrink to their own height
/// when the filter row above has already used the space up.
class _LibraryBody extends StatelessWidget {
  const _LibraryBody({
    required this.state,
    required this.editor,
    required this.production,
  });

  final RecipeLibraryState state;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;

  @override
  Widget build(BuildContext context) => switch (state.status) {
    RecipeLibraryStatus.loading => const SliverFillRemaining(
      hasScrollBody: false,
      child: Center(child: CircularProgressIndicator()),
    ),
    RecipeLibraryStatus.failure => const SliverFillRemaining(
      hasScrollBody: false,
      child: _ErrorBody(),
    ),
    RecipeLibraryStatus.loaded => _LoadedBody(
      state: state,
      editor: editor,
      production: production,
    ),
  };
}

/// The list of rows, or the empty state when nothing is visible. A sliver
/// either way, because the whole screen is one scroll view.
class _LoadedBody extends StatelessWidget {
  const _LoadedBody({
    required this.state,
    required this.editor,
    required this.production,
  });

  final RecipeLibraryState state;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;

  @override
  Widget build(BuildContext context) {
    final recipes = state.visibleRecipes;
    if (recipes.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _CenteredMessage(message: _emptyMessage(context.l10n)),
      );
    }
    return SliverList.builder(
      itemCount: recipes.length,
      itemBuilder: (context, index) => _RecipeRow(
        recipe: recipes[index],
        editor: editor,
        production: production,
      ),
    );
  }

  /// Why the list is empty, in the operator's words.
  ///
  /// The archived case is decided first, and deliberately so. After a
  /// search the hidden rows are that search's own matches, so answering
  /// "no matches" there would deny a result the switch is holding back.
  String _emptyMessage(AppLocalizations l10n) {
    if (state.hasHiddenArchived) return l10n.recipeLibraryOnlyArchived;
    return state.query.isEmpty
        ? l10n.recipeLibraryEmpty
        : l10n.recipeLibraryNoMatches;
  }
}

/// One recipe: its name, its base yield, and the run action.
class _RecipeRow extends StatelessWidget {
  const _RecipeRow({
    required this.recipe,
    required this.editor,
    required this.production,
  });

  final Recipe recipe;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final baseYield = readableQuantity(recipe.baseYield);
    return ListTile(
      // Edit sits in `leading` rather than beside Production Run in
      // `trailing`, which is where it reads more naturally. `ListTile` lays
      // the trailing slot out against the whole tile width and asserts when
      // it fills it, and a `Row` that overflows clamps to exactly that
      // width — so a second control in `trailing` cannot be made to shrink
      // its way out, and the 48 logical pixels it costs come straight off
      // the row's width and text-scale headroom. `leading` is measured
      // separately and the design document calls edit a secondary action,
      // so this is the slot that fits it.
      leading: IconButton(
        tooltip: l10n.recipeLibraryEdit,
        icon: const Icon(Icons.edit_outlined),
        onPressed: () => _openEditor(context, editor, recipe: recipe),
      ),
      title: Text(recipe.name),
      subtitle: Text(
        recipe.isArchived
            ? '$baseYield · ${l10n.recipeLibraryArchived}'
            : baseYield,
      ),
      // Live on every row, archived ones included. An archived recipe
      // cannot be run, but the reason is the production screen's to give:
      // the row would have to say it in the space a button occupies, and
      // the screen says which recipe is archived — this one, or something
      // it depends on, which no row could have known.
      trailing: FilledButton(
        onPressed: () => production.open(context, recipe: recipe),
        child: Text(l10n.recipeLibraryProductionRun),
      ),
    );
  }
}

/// The failed-read state, with the retry that makes it recoverable.
class _ErrorBody extends StatelessWidget {
  const _ErrorBody();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(l10n.recipeLibraryError, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          // `retry`, not `load`: the search field is uncontrolled and keeps
          // what was typed, so a retry that read the whole library would
          // leave the list and the field disagreeing.
          FilledButton(
            onPressed: context.read<RecipeLibraryCubit>().retry,
            child: Text(l10n.recipeLibraryRetry),
          ),
        ],
      ),
    );
  }
}

/// A single centred line of text, padded so it never touches the edges.
class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(message, textAlign: TextAlign.center),
    ),
  );
}

/// Opens the editor over [recipe], and reads the library again when it comes
/// back having stored something.
///
/// The cubit is read before the push, not after: awaiting a route leaves
/// this widget's context free to have been disposed, and looking the cubit
/// up afterwards is what would fail there.
///
/// `retry`, not `load`: it re-runs the current search, so a list filtered by
/// what the field still shows stays filtered. The name is the library
/// cubit's, and reading again after an edit is the same operation.
Future<void> _openEditor(
  BuildContext context,
  RecipeEditorLauncher editor, {
  Recipe? recipe,
}) async {
  final cubit = context.read<RecipeLibraryCubit>();
  final saved = await editor.open(context, recipe: recipe);
  if (saved != null) unawaited(cubit.retry());
}
