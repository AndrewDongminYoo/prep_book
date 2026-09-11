import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/production_setup/production_setup.dart';
import 'package:prep_book/presentation/recipe_editor/recipe_editor.dart';
import 'package:prep_book/presentation/recipe_library/recipe_library.dart';
import 'package:prep_book/presentation/responsive/window_width_class.dart';
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
class RecipeLibraryView extends StatefulWidget {
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
  State<RecipeLibraryView> createState() => _RecipeLibraryViewState();
}

class _RecipeLibraryViewState extends State<RecipeLibraryView> {
  final _listController = ScrollController();
  String? _selectedRecipeId;

  @override
  void dispose() {
    _listController.dispose();
    super.dispose();
  }

  void _select(Recipe recipe) {
    if (_selectedRecipeId == recipe.id) return;
    setState(() => _selectedRecipeId = recipe.id);
  }

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
            onPressed: () => _openEditor(context, widget.editor),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final usesMultiplePanes = usesMultiplePanesAt(
              constraints.maxWidth,
              MediaQuery.textScalerOf(context),
            );
            final list = _LibraryList(
              controller: _listController,
              editor: widget.editor,
              production: widget.production,
              selectedRecipeId: _selectedRecipeId,
              onSelected: usesMultiplePanes ? _select : null,
            );
            if (!usesMultiplePanes) return list;
            return Row(
              children: [
                SizedBox(
                  width: (constraints.maxWidth * 0.5).clamp(300, 420),
                  child: list,
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: BlocBuilder<RecipeLibraryCubit, RecipeLibraryState>(
                    builder: (context, state) => _RecipeDetailPane(
                      key: const ValueKey('recipe-detail-pane'),
                      state: state,
                      selectedRecipeId: _selectedRecipeId,
                      editor: widget.editor,
                      production: widget.production,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const _LibraryList({
    required this.controller,
    required this.editor,
    required this.production,
    required this.selectedRecipeId,
    required this.onSelected,
  });

  final ScrollController controller;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;
  final String? selectedRecipeId;
  final ValueChanged<Recipe>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CustomScrollView(
      key: const ValueKey('recipe-list-pane'),
      controller: controller,
      slivers: [
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
              onChanged: (show) =>
                  context.read<RecipeLibraryCubit>().showArchived(show: show),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: Divider(height: 1)),
        BlocBuilder<RecipeLibraryCubit, RecipeLibraryState>(
          builder: (context, state) => _LibraryBody(
            state: state,
            editor: editor,
            production: production,
            selectedRecipeId: selectedRecipeId,
            onSelected: onSelected,
          ),
        ),
      ],
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
    required this.selectedRecipeId,
    required this.onSelected,
  });

  final RecipeLibraryState state;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;
  final String? selectedRecipeId;
  final ValueChanged<Recipe>? onSelected;

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
      selectedRecipeId: selectedRecipeId,
      onSelected: onSelected,
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
    required this.selectedRecipeId,
    required this.onSelected,
  });

  final RecipeLibraryState state;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;
  final String? selectedRecipeId;
  final ValueChanged<Recipe>? onSelected;

  @override
  Widget build(BuildContext context) {
    final recipes = state.visibleRecipes;
    if (recipes.isEmpty) {
      return SliverFillRemaining(
        hasScrollBody: false,
        child: _CenteredMessage(message: _emptyMessage(context.l10n)),
      );
    }
    final selectedId = onSelected == null
        ? null
        : recipes.any((recipe) => recipe.id == selectedRecipeId)
        ? selectedRecipeId
        : recipes.first.id;
    return SliverList.builder(
      itemCount: recipes.length,
      itemBuilder: (context, index) => _RecipeRow(
        recipe: recipes[index],
        editor: editor,
        production: production,
        selected: recipes[index].id == selectedId,
        onSelected: onSelected,
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
    required this.selected,
    required this.onSelected,
  });

  final Recipe recipe;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;
  final bool selected;
  final ValueChanged<Recipe>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final baseYield = readableQuantity(recipe.baseYield);
    final select = onSelected;
    final editButton = IconButton(
      tooltip: l10n.recipeLibraryEdit,
      icon: const Icon(Icons.edit_outlined),
      onPressed: () => _openEditor(context, editor, recipe: recipe),
    );
    final productionButton = FilledButton(
      onPressed: () => production.open(context, recipe: recipe),
      child: Text(l10n.recipeLibraryProductionRun),
    );
    ListTile tile({Widget? trailing}) => ListTile(
      selected: selected,
      onTap: select == null ? null : () => select(recipe),
      leading: editButton,
      title: Text(recipe.name),
      subtitle: Text(
        recipe.isArchived
            ? '$baseYield · ${l10n.recipeLibraryArchived}'
            : baseYield,
      ),
      trailing: trailing,
    );

    final textScaleFactor = MediaQuery.textScalerOf(context).scale(16) / 16;
    if (textScaleFactor <= 2) return tile(trailing: productionButton);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        tile(),
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: 72,
            end: 16,
            bottom: 12,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: productionButton,
          ),
        ),
      ],
    );
  }
}

class _RecipeDetailPane extends StatefulWidget {
  const _RecipeDetailPane({
    required this.state,
    required this.selectedRecipeId,
    required this.editor,
    required this.production,
    super.key,
  });

  final RecipeLibraryState state;
  final String? selectedRecipeId;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;

  @override
  State<_RecipeDetailPane> createState() => _RecipeDetailPaneState();
}

class _RecipeDetailPaneState extends State<_RecipeDetailPane> {
  final _scrollController = ScrollController(keepScrollOffset: false);

  @override
  void didUpdateWidget(_RecipeDetailPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldRecipeId = _selectedRecipe(
      oldWidget.state.visibleRecipes,
      oldWidget.selectedRecipeId,
    )?.id;
    final recipeId = _selectedRecipe(
      widget.state.visibleRecipes,
      widget.selectedRecipeId,
    )?.id;
    if (recipeId != oldRecipeId && _scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) _scrollController.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recipe = _selectedRecipe(
      widget.state.visibleRecipes,
      widget.selectedRecipeId,
    );
    if (recipe == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.all(24),
      children: [
        Text(recipe.name, style: Theme.of(context).textTheme.headlineSmall),
        if (recipe.category case final category?) ...[
          const SizedBox(height: 8),
          Text(category, style: Theme.of(context).textTheme.titleMedium),
        ],
        const SizedBox(height: 24),
        Text(
          l10n.recipeEditorBaseYieldLabel,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        Text(readableQuantity(recipe.baseYield)),
        if (recipe.maxBatchYield case final maximum?) ...[
          const SizedBox(height: 16),
          Text(
            l10n.recipeEditorMaxBatchLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Text(readableQuantity(maximum)),
        ],
        if (recipe.preparationNotes.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            l10n.recipeEditorNotesLabel,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          for (final note in recipe.preparationNotes) Text(note),
        ],
        const SizedBox(height: 24),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => widget.production.open(context, recipe: recipe),
              icon: const Icon(Icons.play_arrow),
              label: Text(l10n.recipeLibraryProductionRun),
            ),
            OutlinedButton.icon(
              onPressed: () =>
                  _openEditor(context, widget.editor, recipe: recipe),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.recipeLibraryEdit),
            ),
          ],
        ),
      ],
    );
  }

  Recipe? _selectedRecipe(List<Recipe> recipes, String? selectedRecipeId) {
    for (final recipe in recipes) {
      if (recipe.id == selectedRecipeId) return recipe;
    }
    return recipes.isEmpty ? null : recipes.first;
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
