import 'dart:async';

import 'package:flutter/material.dart';
// `ScrollCacheExtent` is a rendering type that `material.dart` does not
// re-export, and it is what `ListView.scrollCacheExtent` takes.
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/production_result/cubit/production_result_cubit.dart';
import 'package:prep_book/presentation/responsive/window_width_class.dart';
import 'package:prep_book/presentation/units/readable_quantity.dart';

/// The production result screen: what today's run takes, component by
/// component, and the snapshot it is committed as.
///
/// Takes the use cases rather than storage, so nothing here can write on
/// its own.
class ProductionResultPage extends StatelessWidget {
  /// Creates the page over the use cases its cubit reviews [run] through.
  const ProductionResultPage({
    required this.acknowledgeWarning,
    required this.applyOverride,
    required this.saveProductionRun,
    required this.run,
    super.key,
  });

  /// Marks one warning as seen.
  final AcknowledgeWarning acknowledgeWarning;

  /// Records an operator-entered quantity for one component.
  final ApplyOverride applyOverride;

  /// Commits the run as an immutable snapshot.
  final SaveProductionRun saveProductionRun;

  /// The run the production setup screen calculated. Never stored yet.
  final ProductionRun run;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Nothing is read when the screen opens: the run arrived with the
      // route, calculated, and everything on screen is read off it.
      create: (_) => ProductionResultCubit(
        acknowledgeWarning,
        applyOverride,
        saveProductionRun,
        run: run,
      ),
      child: const ProductionResultView(),
    );
  }
}

/// The screen's rendering, split from [ProductionResultPage] so the widget
/// that provides the cubit is not also the widget that reads it.
class ProductionResultView extends StatefulWidget {
  /// Creates the view.
  const ProductionResultView({super.key});

  @override
  State<ProductionResultView> createState() => _ProductionResultViewState();
}

class _ProductionResultViewState extends State<ProductionResultView> {
  final _componentController = ScrollController();

  /// One key per line the screen has rendered, so a reveal has something to
  /// scroll to. Keyed on the path, which is what expansion is keyed on and
  /// is unique across the tree.
  final _rowKeys = <String, GlobalKey>{};

  /// The line a reveal is on its way to, held from the tap until the scroll
  /// runs one frame later.
  String? _revealing;

  @override
  void dispose() {
    _componentController.dispose();
    super.dispose();
  }

  /// Opens the sub-recipes hiding the component [key] names, then brings
  /// its line on screen.
  ///
  /// The scroll waits a frame because the line it is aimed at may not exist
  /// yet: expanding is a state change, and the row for a component two
  /// sub-recipes down is built by the rebuild that change causes.
  void _reveal(OverrideKey key) {
    final cubit = context.read<ProductionResultCubit>();
    final path = cubit.state.pathOf(key);
    if (path == null) return;
    setState(() => _revealing = path);
    cubit.componentRevealed(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_scrollTo(path));
    });
  }

  /// Scrolls the line at [path] into view, then puts the list's cache
  /// extent back.
  ///
  /// The key holds no context when the line is not on screen to be scrolled
  /// to, which is what the first test skips on — a reveal cannot outlive
  /// the route it was tapped in, but the callback it scheduled can.
  ///
  /// The reset waits for the animation rather than firing beside it, so the
  /// lines it travels past stay built for the length of it, and it is a
  /// `setState`: without one the widened extent stays on the list for as
  /// long as nothing else rebuilds the screen. Measured before that was
  /// corrected — after a settled reveal the viewport still reported
  /// `cacheExtent=100000.0`, and a warning that needs no edit afterwards
  /// leaves nothing behind to rebuild it.
  Future<void> _scrollTo(String path) async {
    final target = _rowKeys[path]?.currentContext;
    if (target != null) {
      await Scrollable.ensureVisible(
        target,
        // A little below the top edge rather than flush against it, so the
        // line reads as one of a list rather than as the first of one.
        alignment: 0.1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
    if (mounted) setState(() => _revealing = null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.productionResultTitle)),
      // A scroll view rather than a column, for the reason the two screens
      // before it state, and here it is not a matter of narrow windows: a
      // run's components, its expanded sub-recipes and its warnings are
      // longer than any window.
      body: SafeArea(
        child: BlocBuilder<ProductionResultCubit, ProductionResultState>(
          builder: (context, state) => LayoutBuilder(
            builder: (context, constraints) {
              final usesMultiplePanes = usesMultiplePanesAt(
                constraints.maxWidth,
                MediaQuery.textScalerOf(context),
              );
              return usesMultiplePanes
                  ? _wideBody(context, state)
                  : _compactBody(context, state);
            },
          ),
        ),
      ),
    );
  }

  Widget _compactBody(BuildContext context, ProductionResultState state) {
    final l10n = context.l10n;
    return ListView(
      key: const PageStorageKey<String>('production-result-component-scroll'),
      controller: _componentController,
      padding: const EdgeInsets.all(16),
      scrollCacheExtent: _scrollCacheExtent,
      children: [
        ..._runFacts(context, state),
        if (state.warnings.isNotEmpty) ...[
          const Divider(height: 32),
          _Heading(text: l10n.productionResultWarnings),
          for (final warning in state.warnings)
            _WarningTile(state: state, warning: warning, onReveal: _reveal),
        ],
        const Divider(height: 32),
        _Heading(text: l10n.productionResultComponents),
        ..._componentRows(state, showWarnings: false),
        const Divider(height: 32),
        _SaveSection(state: state),
      ],
    );
  }

  Widget _wideBody(BuildContext context, ProductionResultState state) {
    final l10n = context.l10n;
    final visibleComponentKeys = {for (final row in state.visibleRows) row.key};
    final summaryWarnings = state.warnings
        .where((warning) {
          final component = _componentOf(warning);
          return component == null || !visibleComponentKeys.contains(component);
        })
        .toList(growable: false);
    return Row(
      children: [
        Expanded(
          child: ListView(
            key: const PageStorageKey<String>('production-result-summary-pane'),
            padding: const EdgeInsets.all(16),
            children: [
              ..._runFacts(context, state),
              if (summaryWarnings.isNotEmpty) ...[
                const Divider(height: 32),
                _Heading(text: l10n.productionResultWarnings),
                for (final warning in summaryWarnings)
                  _WarningTile(
                    state: state,
                    warning: warning,
                    onReveal: _reveal,
                  ),
              ],
              const Divider(height: 32),
              _SaveSection(state: state),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: KeyedSubtree(
            key: const ValueKey('production-result-components-pane'),
            child: ListView(
              key: const PageStorageKey<String>(
                'production-result-component-scroll',
              ),
              controller: _componentController,
              padding: const EdgeInsets.all(16),
              scrollCacheExtent: _scrollCacheExtent,
              children: [
                _Heading(text: l10n.productionResultComponents),
                ..._componentRows(state, showWarnings: true),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _runFacts(BuildContext context, ProductionResultState state) {
    final l10n = context.l10n;
    return [
      Text(
        state.run.recipe.name,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 16),
      _Fact(
        label: l10n.productionResultTarget,
        value: readableQuantity(state.run.targetYield),
      ),
      _Fact(
        label: l10n.productionResultBatches,
        value: '${state.run.result.batchPlan.batchCount}',
      ),
    ];
  }

  Iterable<Widget> _componentRows(
    ProductionResultState state, {
    required bool showWarnings,
  }) => state.visibleRows.map(
    (row) => _ComponentRow(
      key: _rowKeys.putIfAbsent(row.path, GlobalKey.new),
      state: state,
      row: row,
      showWarnings: showWarnings,
    ),
  );

  /// Every line is built only while a warning reveal is scrolling to it.
  ///
  /// A finite extent avoids the semantics failure produced by infinity and
  /// keeps roughly one thousand rows reachable during the reveal.
  ScrollCacheExtent? get _scrollCacheExtent =>
      _revealing == null ? null : const ScrollCacheExtent.pixels(100000);
}

/// The deepest nesting level the indent still steps for.
///
/// Past it every line sits at the same offset. The step below is 16 logical
/// pixels a level and the domain caps nesting nowhere, so without a bound
/// the indent eventually takes the whole row. What is left of the row will
/// not absorb that: the two `Expanded` halves collapse to nothing, and what
/// sits between and after them does not shrink at all — a 12-pixel gap and
/// an `IconButton` at its 48-pixel minimum. On the narrowest supported
/// window, 320 pixels less the list's own 16 on each side, that irreducible
/// 60 stops fitting at depth 15: the `Row` overflows by 12 pixels and clips
/// the button the operator opens the rest of the tree with, on the lines
/// where opening it is the only way to see any of them. Which makes the
/// bound this screen's to draw, not the domain's.
///
/// Six levels is 96 pixels, leaving 192 of that window for the row itself,
/// more than three times that 60. Deeper than that the indent has stopped
/// being readable as a depth anyway, and the line still names what it is.
const _maxIndentedDepth = 6;

/// One line of the run: what it is, what it takes, and — once opened — its
/// batches and the amount the operator will actually use.
class _ComponentRow extends StatelessWidget {
  const _ComponentRow({
    required this.state,
    required this.row,
    required this.showWarnings,
    super.key,
  });

  final ProductionResultState state;
  final ResultRow row;
  final bool showWarnings;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ProductionResultCubit>();
    final expanded = state.isExpanded(row.path);
    final applied = state.overrideFor(row);
    return Padding(
      // Indented by depth, which is the only thing on screen that says a
      // line belongs to the sub-recipe above it rather than to the run —
      // and capped, for the reason `_maxIndentedDepth` gives.
      padding: EdgeInsets.only(
        left: 16.0 * row.depth.clamp(0, _maxIndentedDepth),
        top: 4,
        bottom: 4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(state.labelOf(row))),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _amountText(l10n, row.total),
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              IconButton(
                key: ValueKey('expand-${row.path}'),
                tooltip: expanded
                    ? l10n.productionResultCollapse
                    : l10n.productionResultExpand,
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
                onPressed: () => cubit.expansionToggled(row.path),
              ),
            ],
          ),
          // The component's note, on every line that carries one rather
          // than only on an opened one. For a free-form line it is the
          // only thing that says what the line is for, and a label alone
          // does not always distinguish two lines: a recipe may reference
          // one ingredient twice — once scaled, once as an as-needed
          // amount — and both lines then read the same name over the same
          // ingredient identifier.
          if (row.component.source.note case final note?)
            Text(note, style: Theme.of(context).textTheme.bodySmall),
          if (showWarnings)
            for (final warning in state.warningsFor(row))
              _WarningTile(state: state, warning: warning, onReveal: null),
          // The operator's own value, on the line it replaces rather than
          // over it: the calculated amount above stays exactly as it was
          // calculated, which is what keeps the two comparable.
          //
          // It reaches this line and no further. Overriding a sub-recipe's
          // total does not rescale what is underneath it — the domain
          // records an override and never recalculates a result, so the
          // nested lines still read what the calculation produced. That is
          // the domain's ruling rather than this screen's, and rescaling
          // here would be domain arithmetic written into a widget.
          if (applied != null)
            Text(
              l10n.productionResultOverrideApplied(readableQuantity(applied)),
              textAlign: TextAlign.end,
            ),
          // How many batches this line spans, not how many groups it
          // renders in: a line whose batches all take the same amount is
          // one group covering every one of them, and gating on the group
          // count would suppress the batch amounts of exactly the lines
          // that have the same amount in every batch — every `perBatch`
          // line, and every proportional one on a target that divides into
          // full batches. Counted per line rather than off
          // `run.result.batchPlan`, because a sub-recipe has a batch plan
          // of its own: `water` is one batch of the Dough sub-recipe on a
          // run the root splits into three. With one batch the line is
          // skipped, since the batch and the total are the same number
          // twice; a free-form line is skipped because its batches are
          // as absent as its total.
          if (expanded && !row.isManual && row.component.perBatch.length > 1)
            for (final group in row.batches)
              _Fact(
                label: group.isRange
                    ? l10n.productionResultBatchRange(
                        '${group.firstBatch}',
                        '${group.lastBatch}',
                      )
                    : l10n.productionResultBatch('${group.firstBatch}'),
                value: _amountText(l10n, group.amount),
              ),
          // A free-form line carries its control whether or not the line is
          // open: it is the one line that has no amount at all, and an
          // operator who has to open a row to find that out has been told
          // nothing. Every other line hides the control until asked.
          if (expanded || row.isManual)
            _OverrideControl(state: state, row: row),
        ],
      ),
    );
  }
}

/// The amount the operator will actually use for one line.
///
/// A manual line's control and an override control are the same control:
/// both record an operator value against the same key, and the domain has
/// one word for it. What differs is only what the line reads above them —
/// a calculated amount, or that there is none.
class _OverrideControl extends StatelessWidget {
  const _OverrideControl({required this.state, required this.row});

  final ProductionResultState state;
  final ResultRow row;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ProductionResultCubit>();
    final draft = state.draftFor(row);
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: _OverrideAmountField(
              key: ValueKey('override-amount-${row.path}'),
              draft: draft,
              enabled: state.isEditable,
              onChanged: (value) => cubit.overrideAmountChanged(row, value),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonFormField<Unit>(
              key: ValueKey('override-unit-${row.path}'),
              // Still seeded rather than driven, unlike the field beside
              // it, and the asymmetry is the framework's:
              // `DropdownButtonFormField.didUpdateWidget` sets the value
              // again whenever `initialValue` changes, so the second row
              // sharing this draft follows the first on its own.
              initialValue: draft.unit,
              // Same reason every dropdown in this app sets it: without it
              // the control lays out at its widest menu item's intrinsic
              // width rather than the width the `Expanded` handed it.
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.productionResultOverrideUnit,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final choice in state.unitChoicesFor(row))
                  DropdownMenuItem(value: choice, child: Text(choice.symbol)),
              ],
              // A dropdown reports `null` only when its value is cleared,
              // which this one never does; every other picker in the app
              // ignores it on the same grounds.
              onChanged: state.isEditable
                  ? (chosen) {
                      if (chosen != null) {
                        cubit.overrideUnitChanged(row, chosen);
                      }
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// The typed half of an override control.
///
/// The one field in this app that holds a controller rather than seeding
/// `initialValue` from the state on every build, and the production setup
/// screen's target field says why the rest do not need one: there, one
/// draft is shown by exactly one field, so a field that is still mounted
/// already carries what the state holds. Here it is not — an override is
/// keyed on a recipe and a component, so a sub-recipe reached by two routes
/// is two rows sharing one draft, and two fields. `TextFormField` reads
/// `initialValue` in `initState` alone, so typing into one of them left the
/// other reading empty while the line above it reported the value.
///
/// The controller is still not the durable copy: it is rebuilt from the
/// draft whenever this element is, which is what keeps the text through a
/// `ListView` recycling the row past its cache extent.
class _OverrideAmountField extends StatefulWidget {
  const _OverrideAmountField({
    required this.draft,
    required this.enabled,
    required this.onChanged,
    super.key,
  });

  /// What the state holds for this line.
  final OverrideDraft draft;

  /// Whether the operator may still change the run.
  final bool enabled;

  /// Reports every keystroke to the cubit.
  final ValueChanged<String> onChanged;

  @override
  State<_OverrideAmountField> createState() => _OverrideAmountFieldState();
}

class _OverrideAmountFieldState extends State<_OverrideAmountField> {
  late final TextEditingController _amount = TextEditingController(
    text: widget.draft.amount,
  );

  @override
  void didUpdateWidget(_OverrideAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    final amount = widget.draft.amount;
    // Only when the two have actually diverged, which is the case where
    // the draft moved without this field: the operator typed into the
    // other row that shares this override. Assigning unconditionally would
    // reset the caret on every keystroke the operator makes here, since
    // their own keystroke arrives back through the state.
    if (amount != _amount.text) {
      _amount.value = TextEditingValue(
        text: amount,
        selection: TextSelection.collapsed(offset: amount.length),
      );
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      controller: _amount,
      enabled: widget.enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: l10n.productionResultOverrideLabel,
        border: const OutlineInputBorder(),
        errorText: widget.draft.amountIsInvalid
            ? l10n.productionResultOverrideInvalid
            : null,
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// One warning, the action that finds the line it names, and the action
/// that marks it seen.
class _WarningTile extends StatelessWidget {
  const _WarningTile({
    required this.state,
    required this.warning,
    required this.onReveal,
  });

  final ProductionResultState state;
  final ProductionWarning warning;

  /// Asks the screen to open and scroll to the line a warning names.
  final ValueChanged<OverrideKey>? onReveal;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ProductionResultCubit>();
    final acknowledged = state.isAcknowledged(warning);
    final reveal = onReveal;
    final revealComponent = reveal == null ? null : _componentOf(warning);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      // A `Wrap` rather than a `Row`, which is the one layout on this
      // screen that cannot be solved by giving both halves an `Expanded`:
      // a `TextButton` sizes to its label and will not shrink, so on a
      // 320-pixel window at the largest supported text scale the action
      // ran 195 pixels past the edge — an action the operator cannot reach
      // on a warning the run cannot be finalized without. Here the message
      // takes the width it needs and the action drops below it.
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text(
            _warningMessage(l10n, state, warning),
            // Coloured while it is still outstanding, plain once it has
            // been seen. The line stays either way: a warning that
            // vanished on acknowledgement would leave the operator no way
            // to check what they accepted.
            style: acknowledged
                ? null
                : TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          // Offered whether or not the warning has been seen, and whether
          // or not the run is still editable: this opens the tree and
          // scrolls, and a stored run stays reviewable. A warning naming a
          // recipe rather than a component gets no such action, because
          // the line it would scroll to is the whole sub-recipe the
          // operator can already see.
          if (revealComponent case final component?)
            TextButton(
              key: ValueKey('reveal-${warning.hashCode}'),
              onPressed: () => reveal?.call(component),
              child: Text(l10n.productionResultShowLine),
            ),
          if (acknowledged)
            Text(l10n.productionResultAcknowledged)
          else
            TextButton(
              key: ValueKey('acknowledge-${warning.hashCode}'),
              onPressed: state.isEditable
                  ? () => cubit.warningAcknowledged(warning)
                  : null,
              child: Text(l10n.productionResultAcknowledge),
            ),
        ],
      ),
    );
  }
}

/// What the run is saved as, and the action that saves it.
class _SaveSection extends StatelessWidget {
  const _SaveSection({required this.state});

  final ProductionResultState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ProductionResultCubit>();
    // Both notices report something the operator has to act on before the
    // run can be committed, so both read as errors.
    final alarming =
        state.status == ProductionResultStatus.failure ||
        state.hasInvalidOverride;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _saveNotice(l10n, state),
          style: alarming
              ? TextStyle(color: Theme.of(context).colorScheme.error)
              : null,
        ),
        const SizedBox(height: 12),
        // The label is the distinction the brief asks to be visible: the
        // same action stores a finalizable run and a draft, and which of
        // the two this is comes off the run itself. Whether it may be
        // pressed at all is a narrower question than whether the run may
        // still be edited, which is why it is not `isEditable`.
        FilledButton(
          onPressed: state.canSave ? () => unawaited(cubit.save()) : null,
          child: Text(
            state.savesAsDraft
                ? l10n.productionResultSaveDraft
                : l10n.productionResultSave,
          ),
        ),
      ],
    );
  }
}

/// One labelled value.
///
/// The twin of the production setup screen's row of the same name, and
/// deliberately a second private copy rather than a shared widget: both
/// halves wrap for the same reason there — a long recipe-defined unit
/// symbol at a large text scale — and nothing else about the two screens'
/// layout is shared, so a common widget would be one caller's layout with
/// a second caller attached to it.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: Text(label)),
        const SizedBox(width: 12),
        Expanded(child: Text(value, textAlign: TextAlign.end)),
      ],
    ),
  );
}

/// A section heading.
class _Heading extends StatelessWidget {
  const _Heading({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: Theme.of(context).textTheme.titleMedium),
  );
}

/// What one calculated amount reads as: the displayed value, followed by
/// the exact one wherever rounding moved it.
///
/// The single place that decision is made, because the total and every
/// batch line ask it of the same type — and a `null` here is a free-form
/// line, which has no number in either form.
String _amountText(AppLocalizations l10n, ScaledQuantity? amount) {
  if (amount == null) return l10n.productionResultManualAmount;
  final displayed = readableQuantity(amount.displayed);
  if (!amount.wasRounded) return displayed;
  return '$displayed · '
      '${l10n.productionResultExact(readableQuantity(amount.exact))}';
}

/// The component a warning is raised against, or `null` when it is raised
/// against a whole recipe instead.
///
/// The pair, never the component id alone, for the reason
/// `ProductionRun.overrides` gives: a component id is unique inside its own
/// recipe and nowhere wider.
OverrideKey? _componentOf(ProductionWarning warning) => switch (warning) {
  ManualComponentWarning(:final recipeId, :final componentId) => (
    recipeId,
    componentId,
  ),
  RoundingAdjustedWarning(:final recipeId, :final componentId) => (
    recipeId,
    componentId,
  ),
  ArchivedDependencyWarning() => null,
};

/// What one warning says, naming the component and the recipe it belongs
/// to out of the run's own snapshot.
String _warningMessage(
  AppLocalizations l10n,
  ProductionResultState state,
  ProductionWarning warning,
) => switch (warning) {
  ManualComponentWarning(:final recipeId, :final componentId) =>
    l10n.productionResultManualWarning(
      state.componentLabelOf((recipeId, componentId)),
      state.recipeNameOf(recipeId),
    ),
  RoundingAdjustedWarning(:final recipeId, :final componentId) =>
    l10n.productionResultRoundingWarning(
      state.componentLabelOf((recipeId, componentId)),
      state.recipeNameOf(recipeId),
    ),
  ArchivedDependencyWarning(:final recipeId) =>
    l10n.productionResultArchivedWarning(state.recipeNameOf(recipeId)),
};

/// What the screen says about saving, given where it has got to.
///
/// A half-typed override outranks everything else here, because it is the
/// only state in which the action below is refused with no other line on
/// screen explaining why — an unacknowledged warning still saves, and a
/// failed write is a state the operator can retry from.
///
/// The notice for a finalizable run may not claim that every warning has
/// been seen: `isFinalizable` asks only about the blocking ones, so a
/// rounding warning sits outstanding — in error colour, its action still
/// live — above the very line that would be saying it had been dealt with.
/// It reports what saving does instead, which is true of a run carrying no
/// warnings at all as well.
String _saveNotice(AppLocalizations l10n, ProductionResultState state) {
  if (state.hasInvalidOverride) {
    return l10n.productionResultOverrideBlocksSave(state.invalidOverrideLabels);
  }
  return switch (state.status) {
    ProductionResultStatus.saved => l10n.productionResultSaved,
    ProductionResultStatus.failure => l10n.productionResultSaveFailed,
    _ =>
      state.savesAsDraft
          ? l10n.productionResultDraftNotice(state.blockingWarningsOutstanding)
          : l10n.productionResultReady,
  };
}
