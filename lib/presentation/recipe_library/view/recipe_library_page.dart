import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/library_backup/library_backup.dart';
import 'package:prep_book/presentation/production_history/production_history.dart';
import 'package:prep_book/presentation/production_setup/production_setup.dart';
import 'package:prep_book/presentation/recipe_editor/recipe_editor.dart';
import 'package:prep_book/presentation/recipe_library/recipe_library.dart';
import 'package:prep_book/presentation/responsive/window_width_class.dart';
import 'package:prep_book/presentation/units/readable_quantity.dart';

/// The recipe library: the screen the app opens on.
///
/// Takes the four use cases rather than a repository, so nothing on this
/// screen can reach storage directly.
class RecipeLibraryPage extends StatelessWidget {
  /// Creates the page over the use cases its cubit reads and writes through.
  const new({
    required this.listLibrary,
    required this.searchLibrary,
    required this.archiveRecipe,
    required this.duplicateRecipe,
    required this.editor,
    required this.production,
    required this.history,
    required this.libraryBackup,
    required this.restored,
    required this.restoreFailure,
    super.key,
  });

  /// Reads every recipe's latest revision.
  final ListLibrary listLibrary;

  /// Filters that list by name.
  final SearchLibrary searchLibrary;

  /// Sets or clears a recipe's archived flag, from each row's menu.
  final ArchiveRecipe archiveRecipe;

  /// Stores a copy of a recipe under a new id, from each row's menu.
  final DuplicateRecipe duplicateRecipe;

  /// Opens the editor, which the create action, each row's edit action,
  /// and the copy a duplicate stores all go through.
  final RecipeEditorLauncher editor;

  /// Opens production setup, which each row's Production Run action goes
  /// through.
  final ProductionSetupLauncher production;

  /// Opens the read-only production history screen.
  final ProductionHistoryLauncher history;

  /// Opens backup and restore from the app-bar menu.
  final LibraryBackupLauncher libraryBackup;

  /// Shows the one-time completion notice for a freshly restored root.
  final bool restored;

  /// Shows one recovered restore failure in the freshly mounted root.
  final LibraryBackupFailureKind? restoreFailure;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = RecipeLibraryCubit(
          listLibrary,
          searchLibrary,
          archiveRecipe,
          duplicateRecipe,
        );
        // The first read starts with the screen; nothing awaits it,
        // because the state it emits is what the view rebuilds from.
        unawaited(cubit.load());
        return cubit;
      },
      child: RecipeLibraryView(
        editor: editor,
        production: production,
        history: history,
        libraryBackup: libraryBackup,
        restored: restored,
        restoreFailure: restoreFailure,
      ),
    );
  }
}

/// The library's rendering, split from [RecipeLibraryPage] so the widget
/// that provides the cubit is not also the widget that reads it.
class RecipeLibraryView extends StatefulWidget {
  /// Creates the view.
  const new({
    required this.editor,
    required this.production,
    required this.history,
    required this.libraryBackup,
    required this.restored,
    required this.restoreFailure,
    super.key,
  });

  /// Opens the editor for the create action and for each row.
  final RecipeEditorLauncher editor;

  /// Opens production setup for a row's Production Run action.
  final ProductionSetupLauncher production;

  final ProductionHistoryLauncher history;

  final LibraryBackupLauncher libraryBackup;

  final bool restored;

  final LibraryBackupFailureKind? restoreFailure;

  @override
  State<RecipeLibraryView> createState() => _RecipeLibraryViewState();
}

class _RecipeLibraryViewState extends State<RecipeLibraryView> {
  final _listController = ScrollController();
  final _searchController = TextEditingController();
  RecipeLibraryCubit? _libraryCubit;
  String? _selectedRecipeId;
  var _backupNoticeScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notice = widget.restored
        ? context.l10n.libraryBackupRestored
        : switch (widget.restoreFailure) {
            final failure? => libraryBackupFailureMessage(
              context.l10n,
              failure,
            ),
            null => null,
          };
    if (notice != null && !_backupNoticeScheduled) {
      _backupNoticeScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(notice)));
      });
    }
    final cubit = context.read<RecipeLibraryCubit>();
    if (identical(cubit, _libraryCubit)) return;
    _libraryCubit = cubit;
    final query = cubit.state.query;
    _searchController.value = TextEditingValue(
      text: query,
      selection: TextSelection.collapsed(offset: query.length),
    );
  }

  @override
  void dispose() {
    _listController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _select(Recipe recipe) {
    if (_selectedRecipeId == recipe.id) return;
    setState(() => _selectedRecipeId = recipe.id);
  }

  Future<void> _openLibraryBackup(LibraryBackupAction action) async {
    final offset = _listController.hasClients ? _listController.offset : null;
    FocusScope.of(context).unfocus();
    await widget.libraryBackup.open(context, action);
    if (!mounted || offset == null || !_listController.hasClients) return;
    _listController.jumpTo(
      offset.clamp(0, _listController.position.maxScrollExtent).toDouble(),
    );
  }

  /// Turns a row action's outcome into what the operator sees: a notice
  /// with Undo for an archive, the editor over a stored copy, or the
  /// failure message for whichever action threw.
  ///
  /// Here, at the level of the view, rather than in the row that asked:
  /// the re-read every successful action ends with shows the spinner for
  /// a frame, which unmounts every row, so a row's own context is gone by
  /// the time there is an outcome to react to. This widget's context stays
  /// mounted throughout.
  void _reactTo(BuildContext context, RecipeLibraryNotice notice) {
    final l10n = context.l10n;
    final cubit = context.read<RecipeLibraryCubit>();
    final messenger = ScaffoldMessenger.of(context);
    switch (notice) {
      case RecipeArchivedNotice(:final recipe, :final isArchived):
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              isArchived ? l10n.recipeLibraryArchivedNotice : l10n.recipeLibraryUnarchivedNotice,
            ),
            // The same use case with the opposite flag, through the same
            // cubit method, so an undo re-reads and reports exactly as the
            // action it reverses did.
            action: SnackBarAction(
              label: l10n.recipeLibraryUndo,
              onPressed: () => unawaited(cubit.archive(recipe, isArchived: !isArchived)),
            ),
          ),
        );
      case RecipeDuplicatedNotice(:final copy):
        // The copy is already stored, so this is the edit path over it:
        // closing without saving leaves the copy in place, and a save
        // re-reads the library exactly as any other edit does.
        //
        // Only while this screen is the one on top. The notice arrives
        // after the copy's write and the re-read that follows it, and
        // every action but Duplicate stays enabled meanwhile, so by then
        // the operator may be on a route of their own — the blank editor,
        // history, a production setup. The copy's editor must not land
        // over that one: it was never asked for there, and a blank editor
        // underneath it is still holding the library as it was before the
        // copy. The editor is a convenience, not the outcome — the copy is
        // stored and listed either way, and its row's Edit opens the same
        // editor this would have. What the operator on that other route
        // still needs is to hear that the copy exists, because the pushed
        // editor was the only confirmation the current-route path gives;
        // the messenger is the app's, so the notice lands on the screen
        // they are looking at.
        if (ModalRoute.isCurrentOf(context) ?? true) {
          unawaited(_openEditor(context, widget.editor, recipe: copy));
        } else {
          messenger.showSnackBar(
            SnackBar(content: Text(l10n.recipeLibraryDuplicatedNotice)),
          );
        }
      case RecipeActionFailedNotice(:final action):
        messenger.showSnackBar(
          SnackBar(
            content: Text(switch (action) {
              RecipeLibraryAction.archive => l10n.recipeLibraryArchiveFailed,
              RecipeLibraryAction.unarchive => l10n.recipeLibraryUnarchiveFailed,
              RecipeLibraryAction.duplicate => l10n.recipeLibraryDuplicateFailed,
            }),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocListener<RecipeLibraryCubit, RecipeLibraryState>(
      // Identity, not equality: see `RecipeLibraryNotice`. A notice that a
      // later state merely carries along must not fire again.
      listenWhen: (previous, current) => current.notice != null && !identical(current.notice, previous.notice),
      listener: (context, state) => _reactTo(context, state.notice!),
      child: Scaffold(
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
              tooltip: l10n.recipeLibraryHistory,
              icon: const Icon(Icons.history),
              onPressed: () => unawaited(widget.history.open(context)),
            ),
            IconButton(
              tooltip: l10n.recipeLibraryCreate,
              icon: const Icon(Icons.add),
              onPressed: () => _openEditor(context, widget.editor),
            ),
            PopupMenuButton<LibraryBackupAction>(
              key: const ValueKey('library-backup-menu'),
              tooltip: l10n.libraryBackupMenu,
              requestFocus: false,
              onSelected: (action) {
                unawaited(_openLibraryBackup(action));
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: LibraryBackupAction.create,
                  child: Text(l10n.libraryBackupCreate),
                ),
                PopupMenuItem(
                  value: LibraryBackupAction.restore,
                  child: Text(l10n.libraryBackupRestore),
                ),
              ],
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
              final textScaler = MediaQuery.textScalerOf(context);
              final usesMultiplePanes = usesMultiplePanesAt(
                constraints.maxWidth,
                textScaler,
              );
              final list = _LibraryList(
                controller: _listController,
                searchController: _searchController,
                editor: widget.editor,
                production: widget.production,
                selectedRecipeId: _selectedRecipeId,
                onSelected: usesMultiplePanes ? _select : null,
              );
              if (!usesMultiplePanes) return list;
              return Row(
                children: [
                  SizedBox(
                    width: _recipeListPaneWidth(
                      constraints.maxWidth,
                      textScaler,
                    ),
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
      ),
    );
  }
}

class _LibraryList extends StatelessWidget {
  const new({
    required this.controller,
    required this.searchController,
    required this.editor,
    required this.production,
    required this.selectedRecipeId,
    required this.onSelected,
  });

  final ScrollController controller;
  final TextEditingController searchController;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;
  final String? selectedRecipeId;
  final ValueChanged<Recipe>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CustomScrollView(
      key: const PageStorageKey<String>('recipe-list-pane'),
      controller: controller,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: searchController,
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
            builder: (context, state) => _CategoryChips(
              categories: state.categories,
              selectedCategory: state.selectedCategory,
              onSelected: context.read<RecipeLibraryCubit>().selectCategory,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: BlocBuilder<RecipeLibraryCubit, RecipeLibraryState>(
            builder: (context, state) => SwitchListTile(
              value: state.showArchived,
              title: Text(l10n.recipeLibraryShowArchived),
              onChanged: (show) => context.read<RecipeLibraryCubit>().showArchived(show: show),
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

/// The narrowest row that lays Production Run and the row menu out beside
/// the title; below it a row stacks them on a second line instead.
///
/// 420 was the threshold while the trailing slot held Production Run alone
/// — the width at which a `ListTile` stops asserting that its trailing
/// widget fills the tile. The menu now shares that slot and costs one
/// minimum tap target of the title's room, so the threshold moves by
/// exactly that: at 468 the title has the room it had at 420.
///
/// Also the master pane's maximum width, so a window wide enough to give
/// the pane that much gets single-line rows in it; a cap below this number
/// would leave every pane on the two-line layout whatever the window.
const double _wideRowMinimumWidth = 420 + kMinInteractiveDimension;

double _recipeListPaneWidth(double width, TextScaler textScaler) {
  final textScaleFactor = textScaler.scale(16) / 16;
  final scaledMinimumWidth = 150 * textScaleFactor;
  final maximumWidth = scaledMinimumWidth < _wideRowMinimumWidth ? _wideRowMinimumWidth : scaledMinimumWidth;
  return (width * 0.5).clamp(300, maximumWidth);
}

/// The category filter: one chip for every category, and one for all of
/// them, or nothing at all when the library has no category to offer.
///
/// A `Wrap` rather than a horizontally scrolling row, so every chip is on
/// screen at once and reachable without a gesture the rest of the screen
/// never asks for. Absent entirely — not an "All" chip alone — when there
/// is no category, because a filter with one setting is not a filter.
class _CategoryChips extends StatelessWidget {
  const new({
    required this.categories,
    required this.selectedCategory,
    required this.onSelected,
  });

  final List<String> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    if (categories.isEmpty) return const SizedBox.shrink();
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: Text(l10n.recipeLibraryAllCategories),
            selected: selectedCategory == null,
            // Stated rather than inherited, because a chip below the
            // 48-pixel minimum would be the one control on this screen
            // that is; the theme's default is platform-dependent.
            materialTapTargetSize: MaterialTapTargetSize.padded,
            onSelected: (_) => onSelected(null),
          ),
          for (final category in categories)
            ChoiceChip(
              label: Text(category),
              selected: selectedCategory == category,
              materialTapTargetSize: MaterialTapTargetSize.padded,
              // Tapping the selected chip again clears the filter, which is
              // what `ChoiceChip` reports as `selected == false`.
              onSelected: (selected) => onSelected(selected ? category : null),
            ),
        ],
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
  const new({
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
  const new({
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
        child: _emptyBody(context.l10n),
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
        isDuplicating: state.isDuplicating,
      ),
    );
  }

  /// Why the list is empty, in the operator's words — and, when the library
  /// itself holds nothing, the action that fills it.
  ///
  /// The archived case is decided first, and deliberately so. After a
  /// search the hidden rows are that search's own matches, so answering
  /// "no matches" there would deny a result the switch is holding back.
  ///
  /// Only the last case carries a button. The other two already name the
  /// next step — the switch, the search field — and a fresh install meets
  /// neither: it lands here with nothing to search and nothing to unhide,
  /// and the message alone would leave the app bar's icon as the only way
  /// forward.
  ///
  /// `resultsQuery`, not `query`: the rows are explained by the query they
  /// answer, and the field's text runs ahead of that by a debounce and a
  /// read. Judged on `query`, clearing a no-match search would offer the
  /// button over a library that holds several recipes until the read lands.
  ///
  /// A selected category counts as a filter here for the same reason a
  /// query does: the rows it leaves empty are a filtered view of a library
  /// that holds something, not an unfilled library.
  Widget _emptyBody(AppLocalizations l10n) {
    if (state.hasHiddenArchived) {
      return _CenteredMessage(message: l10n.recipeLibraryOnlyArchived);
    }
    if (state.resultsQuery.isNotEmpty || state.selectedCategory != null) {
      return _CenteredMessage(message: l10n.recipeLibraryNoMatches);
    }
    return _EmptyLibrary(editor: editor);
  }
}

/// The two actions a row's menu holds.
enum _RowMenuAction { duplicate, toggleArchived }

/// One recipe: its name, its base yield, the run action, and a menu of the
/// secondary ones.
class _RecipeRow extends StatelessWidget {
  const new({
    required this.recipe,
    required this.editor,
    required this.production,
    required this.selected,
    required this.onSelected,
    required this.isDuplicating,
  });

  final Recipe recipe;
  final RecipeEditorLauncher editor;
  final ProductionSetupLauncher production;
  final bool selected;
  final ValueChanged<Recipe>? onSelected;

  /// Whether a duplicate is in flight, which greys this row's Duplicate
  /// item out. The cubit drops a second call regardless; this is what
  /// tells the operator the first tap was taken.
  final bool isDuplicating;

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
    // Duplicate and archive behind one icon, not two more buttons on the
    // row: the design document calls them secondary, and a row that lines
    // up four controls beside Production Run makes none of them dominant.
    final menuButton = PopupMenuButton<_RowMenuAction>(
      tooltip: l10n.recipeLibraryRowMenu,
      icon: const Icon(Icons.more_vert),
      requestFocus: false,
      onSelected: (action) {
        switch (action) {
          case _RowMenuAction.duplicate:
            _duplicate(context, recipe);
          case _RowMenuAction.toggleArchived:
            _toggleArchived(context, recipe);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _RowMenuAction.duplicate,
          enabled: !isDuplicating,
          child: Text(l10n.recipeLibraryDuplicate),
        ),
        PopupMenuItem(
          value: _RowMenuAction.toggleArchived,
          child: Text(
            recipe.isArchived ? l10n.recipeLibraryUnarchive : l10n.recipeLibraryArchive,
          ),
        ),
      ],
    );
    ListTile tile({Widget? trailing}) => ListTile(
      selected: selected,
      onTap: select == null ? null : () => select(recipe),
      leading: editButton,
      title: Text(recipe.name),
      subtitle: Text(
        recipe.isArchived ? '$baseYield · ${l10n.recipeLibraryArchived}' : baseYield,
      ),
      trailing: trailing,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final textScaleFactor = MediaQuery.textScalerOf(context).scale(16) / 16;
        if (constraints.maxWidth >= _wideRowMinimumWidth && textScaleFactor < 2) {
          return tile(
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [productionButton, menuButton],
            ),
          );
        }
        // The menu shares the second line with Production Run rather than
        // taking the tile's trailing slot, so the two actions stay together
        // in both layouts. `Flexible` is what keeps the line from
        // overflowing at 200 percent text: the button's label wraps inside
        // whatever the menu's fixed 48 pixels leave it.
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Flexible(child: productionButton),
                  menuButton,
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _RecipeDetailPane extends StatefulWidget {
  const new({
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
              onPressed: () => _openEditor(context, widget.editor, recipe: recipe),
              icon: const Icon(Icons.edit_outlined),
              label: Text(l10n.recipeLibraryEdit),
            ),
            // Disabled for as long as a duplicate is in flight. This pane
            // is the entry point that stays reachable throughout: the
            // re-read shows the list a spinner and unmounts every row, but
            // this pane renders from rows the loading state carries along.
            OutlinedButton.icon(
              onPressed: widget.state.isDuplicating ? null : () => _duplicate(context, recipe),
              icon: const Icon(Icons.copy_outlined),
              label: Text(l10n.recipeLibraryDuplicate),
            ),
            OutlinedButton.icon(
              onPressed: () => _toggleArchived(context, recipe),
              icon: Icon(
                recipe.isArchived ? Icons.unarchive_outlined : Icons.archive_outlined,
              ),
              label: Text(
                recipe.isArchived ? l10n.recipeLibraryUnarchive : l10n.recipeLibraryArchive,
              ),
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
  const new();

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

/// The unfilled library, with the create action that fills it.
///
/// The same action as the app bar's icon, through the same launcher, so a
/// recipe saved from here is listed the same way when the editor closes.
class _EmptyLibrary extends StatelessWidget {
  const new({required this.editor});

  final RecipeEditorLauncher editor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l10n.recipeLibraryEmpty, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => _openEditor(context, editor),
              child: Text(l10n.recipeLibraryCreate),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single centred line of text, padded so it never touches the edges.
class _CenteredMessage extends StatelessWidget {
  const new({required this.message});

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

/// Archives [recipe] if it is live, restores it if it is archived.
///
/// No confirmation: archiving is reversible, and the notice the cubit's
/// outcome produces carries the reversal. Nothing is awaited, because the
/// outcome reaches the screen through the state, not through this call.
void _toggleArchived(BuildContext context, Recipe recipe) => unawaited(
  context.read<RecipeLibraryCubit>().archive(
    recipe,
    isArchived: !recipe.isArchived,
  ),
);

/// Stores a copy of [recipe] under the localized copy name.
///
/// The name is chosen here because it is the operator's language, which
/// the cubit does not hold; the editor the outcome opens is where the
/// operator replaces it.
void _duplicate(BuildContext context, Recipe recipe) => unawaited(
  context.read<RecipeLibraryCubit>().duplicate(
    recipe,
    name: context.l10n.recipeLibraryCopyName(recipe.name),
  ),
);
