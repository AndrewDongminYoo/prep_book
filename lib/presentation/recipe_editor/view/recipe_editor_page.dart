import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/recipe_editor/recipe_editor.dart';
import 'package:prep_book/presentation/responsive/window_width_class.dart';
import 'package:prep_book/presentation/units/readable_quantity.dart';

part 'recipe_editor_pickers.dart';

/// The recipe editor: metadata, an ordered component list, and the save.
///
/// Creating a recipe and editing one are the same screen, because they are
/// the same call: `SaveRecipeRevision` decides the revision number from what
/// is stored. [recipe] is the revision being edited, or `null` to create one.
///
/// Takes the four use cases rather than storage, so nothing on this screen
/// can reach a database directly.
class RecipeEditorPage extends StatelessWidget {
  /// Creates the page over the use cases its cubit reads and writes through.
  const RecipeEditorPage({
    required this.listLibrary,
    required this.listIngredients,
    required this.saveRecipeRevision,
    required this.saveIngredient,
    this.recipe,
    super.key,
  });

  /// Reads the recipes the sub-recipe picker offers.
  final ListLibrary listLibrary;

  /// Reads the ingredients the ingredient picker offers.
  final ListIngredients listIngredients;

  /// Stores the edit as the recipe's next revision.
  final SaveRecipeRevision saveRecipeRevision;

  /// Stores an ingredient the operator names while editing.
  final SaveIngredient saveIngredient;

  /// The revision being edited, or `null` when creating a recipe.
  final Recipe? recipe;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) {
        final cubit = RecipeEditorCubit(
          listLibrary,
          listIngredients,
          saveRecipeRevision,
          saveIngredient,
          recipe: recipe,
        );
        // The pickers cannot be offered before the read lands, and the
        // state it emits is what the view rebuilds from, so nothing awaits
        // it here.
        unawaited(cubit.load());
        return cubit;
      },
      child: const RecipeEditorView(),
    );
  }
}

/// The editor's rendering, split from [RecipeEditorPage] so the widget that
/// provides the cubit is not also the widget that reads it.
class RecipeEditorView extends StatefulWidget {
  /// Creates the view.
  const RecipeEditorView({super.key});

  @override
  State<RecipeEditorView> createState() => _RecipeEditorViewState();
}

class _RecipeEditorViewState extends State<RecipeEditorView> {
  final _formScrollController = ScrollController();

  @override
  void dispose() {
    _formScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocConsumer<RecipeEditorCubit, RecipeEditorState>(
      listenWhen: (previous, current) =>
          current.status == RecipeEditorStatus.saved ||
          (current.saveError != null &&
              current.saveError != previous.saveError),
      listener: (context, state) {
        // A failure is reported where the operator is looking rather than
        // inline: Save sits in the app bar, so the form can be scrolled
        // anywhere when the answer arrives, and a message pinned above a
        // scroll view would be the one thing on this screen that can push
        // the form out of a short landscape viewport.
        final error = state.saveError;
        if (error != null) _report(context, _saveErrorMessage(l10n, error));
        // Popped with what was stored, so the library can list it without
        // guessing whether anything changed.
        if (state.status == RecipeEditorStatus.saved) {
          Navigator.of(context).pop(state.savedRecipe);
        }
      },
      builder: (context, state) => PopScope<Recipe>(
        // Leaving is refused while a write runs, because leaving does not
        // stop it: the pop disposes the cubit, the use case it started
        // carries no cancellation, and the revision lands anyway — in a
        // database the screen underneath will not read again, because it
        // reads again only when this route hands back what was stored.
        // Blocking the exit is what keeps the two in step; the
        // alternatives are cancelling a write that is already committed or
        // refreshing a screen that never asked.
        //
        // `isWriting` rather than `isEditable`: the form is also not
        // editable while the two libraries are being read, and nothing is
        // in flight then for leaving to strand — back must still work on a
        // spinner.
        //
        // The app bar's back button and the platform's back gesture both
        // go through `Navigator.maybePop`, which is what consults this.
        // `Navigator.pop` does not, so the pop the listener above performs
        // still runs while this is false.
        canPop: !state.isWriting,
        onPopInvokedWithResult: (didPop, _) {
          // Only a refusal needs saying. A pop that happened explains
          // itself, and the successful save's own pop arrives here too.
          if (!didPop) _report(context, l10n.recipeEditorSaveInProgress);
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(
              state.isNewRecipe
                  ? l10n.recipeEditorNewTitle
                  : l10n.recipeEditorEditTitle,
            ),
            actions: [
              // Disabled unless the form is up and idle: a second tap while
              // a save is in flight would write a second revision, and one
              // during the ingredient write would store the recipe without
              // the line that write is adding.
              TextButton(
                onPressed: state.isEditable
                    ? context.read<RecipeEditorCubit>().save
                    : null,
                child: Text(l10n.recipeEditorSave),
              ),
            ],
          ),
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final body = _EditorBody(
                  state: state,
                  scrollController: _formScrollController,
                );
                final widthClass = windowWidthClassOf(constraints.maxWidth);
                if (!widthClass.usesMultiplePanes) return body;

                return Center(
                  child: SizedBox(
                    key: const ValueKey('recipe-editor-width-boundary'),
                    width: constraints.maxWidth > 960
                        ? 960
                        : constraints.maxWidth,
                    height: constraints.maxHeight,
                    child: body,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Shows [message] over whatever the operator is currently looking at.
  static void _report(BuildContext context, String message) =>
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
}

/// Whichever of the three bodies the current [state] calls for.
class _EditorBody extends StatelessWidget {
  const _EditorBody({required this.state, required this.scrollController});

  final RecipeEditorState state;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) => switch (state.status) {
    RecipeEditorStatus.loading => const Center(
      child: CircularProgressIndicator(),
    ),
    RecipeEditorStatus.loadFailure => const _LoadErrorBody(),
    // The form stays on screen while a write runs — replacing it with a
    // spinner would throw away the scroll position and every field's caret
    // for a wait that is usually a frame — but it stops accepting input.
    // Both writes read the whole form when they start and rewrite the state
    // when they finish, so anything typed in between is silently discarded;
    // the two wrappers below are what makes that impossible rather than
    // unlikely. Pointer events are absorbed, and focus is excluded as well,
    // because a field the operator was already typing into keeps its
    // keyboard connection no matter what sits above it.
    RecipeEditorStatus.ready ||
    RecipeEditorStatus.saving ||
    RecipeEditorStatus.saved => AbsorbPointer(
      absorbing: !state.isEditable,
      child: ExcludeFocus(
        excluding: !state.isEditable,
        child: _EditorForm(state: state, scrollController: scrollController),
      ),
    ),
  };
}

/// The failed-read state. The form is not offered at all, because its
/// pickers would be empty and an operator cannot tell an empty library from
/// one that could not be read.
class _LoadErrorBody extends StatelessWidget {
  const _LoadErrorBody();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(l10n.recipeEditorLoadError, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: context.read<RecipeEditorCubit>().load,
              child: Text(l10n.recipeEditorRetry),
            ),
          ],
        ),
      ),
    );
  }
}

/// The form itself: metadata above, the component list, the actions below.
///
/// One reorderable list rather than a column of sections, so the whole
/// screen scrolls as a unit — the same reason the library screen is one
/// scroll view — and so dragging a component is the list's own behaviour
/// rather than something this screen implements.
class _EditorForm extends StatelessWidget {
  const _EditorForm({required this.state, required this.scrollController});

  final RecipeEditorState state;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<RecipeEditorCubit>();
    return ReorderableListView(
      key: const PageStorageKey<String>('recipe-editor-form-scroll'),
      scrollController: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      // Off, and replaced by the handle each card carries. The default on a
      // touch platform is a long press anywhere on the child, and every
      // child here is a card full of text fields — long-pressing one of
      // those has to place the caret and open the selection controls, not
      // pick the row up.
      buildDefaultDragHandles: false,
      header: _MetadataSection(state: state),
      footer: _ComponentActions(state: state),
      // The row being dragged is rebuilt inside the overlay, which is not
      // under this screen's `BlocProvider` — so a card that looked its cubit
      // up from the context threw the moment a drag started. Handing the
      // proxy the same cubit is what keeps the dragged row identical to the
      // one it left behind.
      proxyDecorator: (child, index, animation) => BlocProvider.value(
        value: cubit,
        child: Material(elevation: 6, color: Colors.transparent, child: child),
      ),
      // `onReorderItem`, not the deprecated `onReorder`: it hands over the
      // destination index already adjusted for the row leaving its old
      // place, which is the off-by-one every caller of the older callback
      // had to correct itself.
      onReorderItem: (oldIndex, newIndex) =>
          cubit.reorderComponent(oldIndex: oldIndex, newIndex: newIndex),
      children: [
        for (final (index, draft) in state.components.indexed)
          _ComponentCard(
            // The list requires a key per child; keying it by the draft
            // rather than the position is what lets the reorder animate the
            // row that moved. What keeps the *typed text* with its line is
            // the key on each field inside the card, not this one — an
            // index here survives the reorder test, an index there does
            // not.
            key: ValueKey(draft.id),
            state: state,
            draft: draft,
            index: index,
          ),
      ],
    );
  }
}

/// Name, category, the two yields, and the preparation notes.
class _MetadataSection extends StatelessWidget {
  const _MetadataSection({required this.state});

  final RecipeEditorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RecipeEditorCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          key: const ValueKey('recipe-name'),
          initialValue: state.name,
          decoration: InputDecoration(
            labelText: l10n.recipeEditorNameLabel,
            border: const OutlineInputBorder(),
            // Errors stay off until a save has been attempted; a form that
            // reports what is missing before anything is typed reports
            // everything at once.
            errorText: state.submitted && state.nameIsMissing
                ? l10n.recipeEditorNameRequired
                : null,
          ),
          onChanged: cubit.nameChanged,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('recipe-category'),
          initialValue: state.category,
          decoration: InputDecoration(
            labelText: l10n.recipeEditorCategoryLabel,
            border: const OutlineInputBorder(),
          ),
          onChanged: cubit.categoryChanged,
        ),
        const SizedBox(height: 12),
        _AmountRow(
          fieldKey: const ValueKey('base-yield'),
          label: l10n.recipeEditorBaseYieldLabel,
          amount: state.baseYieldAmount,
          unit: state.baseYieldUnit,
          choices: state.unitChoices,
          errorText: _baseYieldError(l10n, state),
          onAmountChanged: cubit.baseYieldAmountChanged,
          onUnitChanged: cubit.baseYieldUnitChanged,
        ),
        const SizedBox(height: 12),
        _AmountRow(
          fieldKey: const ValueKey('max-batch-yield'),
          label: l10n.recipeEditorMaxBatchLabel,
          amount: state.maxBatchAmount,
          unit: state.maxBatchUnit,
          choices: state.unitChoices,
          errorText: _maxBatchError(l10n, state),
          onAmountChanged: cubit.maxBatchAmountChanged,
          onUnitChanged: cubit.maxBatchUnitChanged,
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: const ValueKey('preparation-notes'),
          initialValue: state.preparationNotes,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: l10n.recipeEditorNotesLabel,
            border: const OutlineInputBorder(),
          ),
          onChanged: cubit.preparationNotesChanged,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.straighten),
            label: Text(l10n.recipeEditorAddCustomUnit),
            onPressed: () => _declareUnit(context),
          ),
        ),
        const Divider(),
        Text(
          l10n.recipeEditorComponentsTitle,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// Which of the two base-yield messages applies, if either.
  ///
  /// The second is about the unit rather than the amount, and it names the
  /// recipes that already consume this one — what the operator has to look
  /// at is elsewhere in the library, so a message that only said "wrong
  /// unit" would leave them nothing to act on.
  static String? _baseYieldError(
    AppLocalizations l10n,
    RecipeEditorState state,
  ) {
    if (!state.submitted) return null;
    if (state.baseYieldIsInvalid) return l10n.recipeEditorAmountRequired;
    final blocked = state.dependentsBlockedByBaseYieldUnit;
    return blocked.isEmpty
        ? null
        : l10n.recipeEditorDependentsBlocked(
            blocked.map((recipe) => recipe.name).join(', '),
          );
  }

  /// Which of the two maximum-batch messages applies, if either.
  static String? _maxBatchError(
    AppLocalizations l10n,
    RecipeEditorState state,
  ) {
    if (!state.submitted) return null;
    if (state.maxBatchIsInvalid) return l10n.recipeEditorAmountRequired;
    return state.maxBatchUnitIsIncompatible
        ? l10n.recipeEditorUnitIncompatible
        : null;
  }
}

/// An amount and the unit it is measured in, side by side.
class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.fieldKey,
    required this.label,
    required this.amount,
    required this.unit,
    required this.choices,
    required this.errorText,
    required this.onAmountChanged,
    required this.onUnitChanged,
  });

  final Key fieldKey;
  final String label;
  final String amount;
  final Unit unit;
  final List<Unit> choices;
  final String? errorText;
  final ValueChanged<String> onAmountChanged;
  final ValueChanged<Unit> onUnitChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: TextFormField(
            key: fieldKey,
            initialValue: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              errorText: errorText,
            ),
            onChanged: onAmountChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<Unit>(
            initialValue: unit,
            // Without this the dropdown lays its own row out at the widest
            // menu item's intrinsic width instead of the width the
            // `Expanded` handed it, and overflows the column at
            // split-window widths. Every dropdown on this screen is
            // width-constrained by its parent, so every one of them sets it.
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.recipeEditorUnitLabel,
              border: const OutlineInputBorder(),
            ),
            items: [
              for (final choice in choices)
                DropdownMenuItem(value: choice, child: Text(choice.symbol)),
            ],
            // A dropdown reports `null` only when its value is cleared,
            // which none of these ever do; ignoring it beats inventing a
            // fallback that would silently re-select the current unit.
            onChanged: (chosen) {
              if (chosen != null) onUnitChanged(chosen);
            },
          ),
        ),
      ],
    );
  }
}

/// One component: what it consumes, how it scales, and how it reads.
class _ComponentCard extends StatelessWidget {
  const _ComponentCard({
    required this.state,
    required this.draft,
    required this.index,
    super.key,
  });

  final RecipeEditorState state;
  final ComponentDraft draft;
  final int index;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<RecipeEditorCubit>();
    final isManual = draft.behavior == ScalingBehavior.manual;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 8),
                    child: Icon(Icons.drag_handle),
                  ),
                ),
                // The target is a control, not a caption: without one, the
                // only way to change what a line consumes is to delete it
                // and add it again, losing the amount, unit, behavior,
                // rounding and note along with it. It reopens the picker
                // the line's own kind of target came from — an ingredient
                // line offers ingredients, a sub-recipe line offers
                // recipes — because the two are not interchangeable and
                // swapping kinds really is a different line.
                Expanded(
                  child: Tooltip(
                    message: l10n.recipeEditorChangeTarget,
                    child: InkWell(
                      onTap: () => _changeTarget(context, draft),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _targetName(state, draft.target),
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Labelled alternatives to the drag gesture, which the
                // design document requires of every action, and which are
                // also the only way to reorder with a screen reader.
                IconButton(
                  tooltip: l10n.recipeEditorMoveUp,
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: index == 0
                      ? null
                      : () => cubit.reorderComponent(
                          oldIndex: index,
                          newIndex: index - 1,
                        ),
                ),
                IconButton(
                  tooltip: l10n.recipeEditorMoveDown,
                  icon: const Icon(Icons.arrow_downward),
                  onPressed: index == state.components.length - 1
                      ? null
                      : () => cubit.reorderComponent(
                          oldIndex: index,
                          newIndex: index + 1,
                        ),
                ),
                IconButton(
                  tooltip: l10n.recipeEditorRemoveComponent,
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => cubit.removeComponent(draft.id),
                ),
              ],
            ),
            DropdownButtonFormField<ScalingBehavior>(
              initialValue: draft.behavior,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.recipeEditorBehaviorLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final behavior in ScalingBehavior.values)
                  DropdownMenuItem(
                    value: behavior,
                    child: Text(_behaviorLabel(l10n, behavior)),
                  ),
              ],
              onChanged: (chosen) {
                if (chosen != null) {
                  cubit.componentBehaviorChanged(draft.id, chosen);
                }
              },
            ),
            // A manual line has no amount, no unit and nothing to round: the
            // design document makes a free-form quantity a manual component
            // rather than a numeric zero, so the controls are absent rather
            // than showing a zero the operator has to ignore.
            if (!isManual) ...[
              const SizedBox(height: 12),
              _AmountRow(
                fieldKey: ValueKey('${draft.id}-amount'),
                label: l10n.recipeEditorAmountLabel,
                amount: draft.amount,
                unit: draft.unit,
                // Narrowed for a sub-recipe line, whose quantity is the
                // target yield the referenced recipe is run against.
                choices: state.unitChoicesFor(draft),
                errorText: _componentAmountError(l10n, state, draft),
                onAmountChanged: (value) =>
                    cubit.componentAmountChanged(draft.id, value),
                onUnitChanged: (unit) =>
                    cubit.componentUnitChanged(draft.id, unit),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: ValueKey('${draft.id}-rounding'),
                initialValue: draft.roundingIncrement,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: l10n.recipeEditorRoundingLabel,
                  border: const OutlineInputBorder(),
                  errorText: state.submitted && state.roundingIsInvalid(draft)
                      ? l10n.recipeEditorAmountRequired
                      : null,
                ),
                onChanged: (value) =>
                    cubit.componentRoundingChanged(draft.id, value),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              key: ValueKey('${draft.id}-note'),
              initialValue: draft.note,
              decoration: InputDecoration(
                labelText: l10n.recipeEditorNoteLabel,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => cubit.componentNoteChanged(draft.id, value),
            ),
          ],
        ),
      ),
    );
  }

  /// Which of the two amount-row messages applies to [draft], if either.
  ///
  /// The unit's message shares the amount field's error slot, the same way
  /// the maximum batch yield's does: [_AmountRow] renders one message for
  /// the pair, and the two cannot both be reported at once.
  static String? _componentAmountError(
    AppLocalizations l10n,
    RecipeEditorState state,
    ComponentDraft draft,
  ) {
    if (!state.submitted) return null;
    if (state.amountIsInvalid(draft)) return l10n.recipeEditorAmountRequired;
    return state.subRecipeUnitIsIncompatible(draft)
        ? l10n.recipeEditorSubRecipeUnitIncompatible
        : null;
  }
}

/// The two ways to add a line, and what to say when there are none.
class _ComponentActions extends StatelessWidget {
  const _ComponentActions({required this.state});

  final RecipeEditorState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (state.components.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              l10n.recipeEditorNoComponents,
              textAlign: TextAlign.center,
            ),
          ),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.add),
              label: Text(l10n.recipeEditorAddIngredient),
              onPressed: () => _addIngredient(context),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.account_tree_outlined),
              label: Text(l10n.recipeEditorAddSubRecipe),
              onPressed: () => _addSubRecipe(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// The name to show for [target], falling back to its identifier.
///
/// An identifier is what the seed's components carry for ingredients that
/// have no stored record, so this is what the operator sees until one
/// exists — a readable line rather than a blank one.
String _targetName(RecipeEditorState state, ComponentTarget target) =>
    switch (target) {
      IngredientRef(:final ingredientId) => _firstOr([
        for (final ingredient in state.ingredients)
          if (ingredient.id == ingredientId) ingredient.name,
      ], ingredientId),
      SubRecipeRef(:final recipeId) => _firstOr([
        for (final recipe in state.libraryRecipes)
          if (recipe.id == recipeId) recipe.name,
      ], recipeId),
    };

/// The first of [names], or [fallback] when there are none.
String _firstOr(List<String> names, String fallback) =>
    names.isEmpty ? fallback : names.first;

/// What each scaling behavior is called on screen.
String _behaviorLabel(AppLocalizations l10n, ScalingBehavior behavior) =>
    switch (behavior) {
      ScalingBehavior.proportional => l10n.recipeEditorBehaviorProportional,
      ScalingBehavior.perBatch => l10n.recipeEditorBehaviorPerBatch,
      ScalingBehavior.fixedOnce => l10n.recipeEditorBehaviorFixedOnce,
      ScalingBehavior.manual => l10n.recipeEditorBehaviorManual,
    };

/// What a failed save says, carrying what the error itself names.
///
/// A cycle and a missing dependency are the two the operator can act on, so
/// they are rendered with the path and the identifier the domain found
/// rather than as a generic failure.
String _saveErrorMessage(AppLocalizations l10n, Object error) =>
    switch (error) {
      RecipeCycleError(:final path) => l10n.recipeEditorCycleError(
        path.join(' → '),
      ),
      MissingDependencyError(:final missingId) =>
        l10n.recipeEditorMissingDependency(missingId),
      _ => l10n.recipeEditorSaveFailed,
    };
