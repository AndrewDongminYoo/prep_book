import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/production_result/view/production_result_launcher.dart';
import 'package:prep_book/presentation/production_setup/cubit/production_setup_cubit.dart';
import 'package:prep_book/presentation/units/readable_quantity.dart';

/// The production setup screen: today's target yield, and what it becomes.
///
/// Takes the use case rather than storage, so nothing here can read a
/// recipe on its own.
class ProductionSetupPage extends StatelessWidget {
  /// Creates the page over the use case its cubit calculates through, for
  /// [recipe] — the revision the library screen listed.
  const ProductionSetupPage({
    required this.startProductionRun,
    required this.recipe,
    required this.result,
    super.key,
  });

  /// Calculates a run without storing it.
  final StartProductionRun startProductionRun;

  /// The recipe the operator chose.
  final Recipe recipe;

  /// Where Continue goes: the production result screen, over the run this
  /// one calculated.
  final ProductionResultLauncher result;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Nothing is read when the screen opens, unlike the library and the
      // editor: this screen has nothing to calculate until a target is
      // typed, and the recipe it lays the form out from arrived with the
      // route.
      create: (_) => ProductionSetupCubit(startProductionRun, recipe: recipe),
      child: ProductionSetupView(result: result),
    );
  }
}

/// The screen's rendering, split from [ProductionSetupPage] so the widget
/// that provides the cubit is not also the widget that reads it.
class ProductionSetupView extends StatelessWidget {
  /// Creates the view over the launcher its Continue action opens.
  const ProductionSetupView({required this.result, super.key});

  /// Opens the production result screen over the calculated run.
  final ProductionResultLauncher result;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.productionSetupTitle)),
      // Everything sits inside one builder, the target field included. The
      // library screen keeps its search field outside its builders because
      // nothing about that field depends on the state; this one's error
      // text does, so it has to rebuild.
      //
      // A scroll view rather than a column, for the reason the library
      // screen states: with the software keyboard up on a landscape phone
      // what is left of the body is shorter than this form, and a column
      // there overflows where a scroll view scrolls.
      body: SafeArea(
        child: BlocBuilder<ProductionSetupCubit, ProductionSetupState>(
          builder: (context, state) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                state.recipe.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              _TargetRow(state: state),
              const SizedBox(height: 24),
              _Outcome(state: state),
              const SizedBox(height: 24),
              // What decides whether it may be pressed was already
              // written down when this screen was built:
              // `ProductionSetupState.canContinue`, which
              // `production_setup_cubit_test.dart` pins. This slice wires
              // the route it gates rather than deriving the rule again.
              _Continue(state: state, result: result),
            ],
          ),
        ),
      ),
    );
  }
}

/// The action that carries the calculated run through to the production
/// result screen.
class _Continue extends StatelessWidget {
  const _Continue({required this.state, required this.result});

  final ProductionSetupState state;
  final ProductionResultLauncher result;

  @override
  Widget build(BuildContext context) {
    // `canContinue` already requires a calculated run; reading it into a
    // local is what lets the analyzer see that, so the run reaches the
    // launcher without a null assertion.
    final run = state.preview;
    return FilledButton(
      onPressed: run != null && state.canContinue
          ? () => unawaited(_continue(context, run))
          : null,
      child: Text(context.l10n.productionSetupContinue),
    );
  }

  /// Opens the result screen over [run], then calculates the target again.
  ///
  /// The second half is not a refresh for its own sake. A run carries the
  /// identifier it was given when it was calculated, and a stored run may
  /// not be stored a second time under it — the repository's write is a
  /// bare insert against a primary key. So an operator who saves a run,
  /// comes back and presses Continue again would otherwise be handed the
  /// same run, and their next save would fail on a collision nothing on
  /// screen explains. Recalculating mints a new identifier, and it also
  /// picks up a recipe edited while the result screen was up.
  ///
  /// Through the cubit's own target entry point rather than a method added
  /// for this: pressing Continue a second time is the same request as
  /// typing the target was, and it goes through the same debounce and the
  /// same intent counter. The cubit is read before the await, so no
  /// context outlives an asynchronous gap.
  Future<void> _continue(BuildContext context, ProductionRun run) async {
    final cubit = context.read<ProductionSetupCubit>();
    await result.open(context, run: run);
    await cubit.targetAmountChanged(state.targetAmount);
  }
}

/// The target amount and the unit it is measured in.
///
/// Deliberately not the editor's own amount-and-unit row: this screen's
/// unit control carries an error of its own, which that one cannot express,
/// and a dimensionally impossible target is the error this screen exists to
/// report before it is submitted.
class _TargetRow extends StatelessWidget {
  const _TargetRow({required this.state});

  final ProductionSetupState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ProductionSetupCubit>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          // Seeded from the state on every build, the shape the editor's
          // fields use, because the cubit's `targetAmount` is the only
          // durable copy of what was typed: the field is inside a
          // `ListView`, and a `ListView` destroys a child's element once it
          // scrolls past the cache extent — which this form does on a
          // window it outgrows, once the field is unfocused, since
          // `EditableText` keeps itself alive only while focused. A field
          // holding the text in its own element state alone came back empty
          // over the batch plan it had been calculated from.
          //
          // Seeding cannot disturb a field that is still mounted:
          // `TextFormField` reads `initialValue` in `initState` and its
          // `didUpdateWidget` reacts only to a change of controller, so a
          // rebuild while the operator is typing leaves the text and the
          // caret alone.
          child: TextFormField(
            key: const ValueKey('target-amount'),
            initialValue: state.targetAmount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: l10n.productionSetupTargetLabel,
              border: const OutlineInputBorder(),
              errorText: state.amountIsInvalid
                  ? l10n.productionSetupAmountInvalid
                  : null,
            ),
            onChanged: cubit.targetAmountChanged,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<Unit>(
            initialValue: state.targetUnit,
            // Same reason every dropdown in the editor sets it: without it
            // the control lays out at its widest menu item's intrinsic
            // width rather than the width the `Expanded` handed it, and
            // overflows the row at split-window widths.
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.productionSetupUnitLabel,
              border: const OutlineInputBorder(),
              errorText: state.targetUnitIsIncompatible
                  ? l10n.productionSetupUnitIncompatible(
                      state.recipe.baseYield.unit.symbol,
                    )
                  : null,
            ),
            items: [
              for (final choice in state.unitChoices)
                DropdownMenuItem(value: choice, child: Text(choice.symbol)),
            ],
            // A dropdown reports `null` only when its value is cleared,
            // which this one never does; the editor's pickers ignore it on
            // the same grounds. Nothing awaits the change for the reason
            // the library screen's first read is not awaited either: what
            // the screen rebuilds from is the state it emits.
            onChanged: (chosen) {
              if (chosen != null) unawaited(cubit.targetUnitChanged(chosen));
            },
          ),
        ),
      ],
    );
  }
}

/// Whichever outcome the current [state] calls for.
class _Outcome extends StatelessWidget {
  const _Outcome({required this.state});

  final ProductionSetupState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    // Read first, so the arms below never have to assert that a ready
    // state carries a run.
    final run = state.preview;
    if (run != null) return _Calculated(state: state, run: run);
    // Above the switch, because a target over the screen's own half of the
    // batch limit leaves the status at idle and would otherwise fall
    // through to the prompt below — which asks for a target from an
    // operator who has just entered one. The other half of that limit, the
    // one a sub-recipe's plan crosses, arrives as a thrown
    // `BatchLimitExceededError` instead and is named by `_errorMessage`
    // below in the same words. The reason belongs here rather than under
    // the amount field: what the limit refuses is the size of the batch
    // plan, and this is where that plan would have been.
    if (state.targetExceedsBatchLimit) {
      return _ErrorText(
        message: l10n.productionSetupTargetTooLarge(
          '${ProductionSetupState.maxPlannedBatches}',
        ),
      );
    }
    return switch (state.status) {
      ProductionSetupStatus.calculating => const Center(
        child: CircularProgressIndicator(),
      ),
      ProductionSetupStatus.failure => _ErrorText(
        message: _errorMessage(l10n, state.error),
      ),
      _ => Text(l10n.productionSetupPrompt),
    };
  }
}

/// What the calculated run says: what blocks it, how it splits into
/// batches, and how it compares against the recipe as written.
class _Calculated extends StatelessWidget {
  const _Calculated({required this.state, required this.run});

  final ProductionSetupState state;
  final ProductionRun run;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final plan = run.result.batchPlan;
    final remainder = plan.remainderYield;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // First, and above the numbers: the numbers are right, and the run
        // still may not be started.
        for (final name in state.archivedDependencies)
          _ErrorText(message: l10n.productionSetupArchived(name)),
        if (state.archivedDependencies.isNotEmpty) const SizedBox(height: 12),
        _Fact(label: l10n.productionSetupBatches, value: '${plan.batchCount}'),
        // Guarded the way the remainder below it is, and for the same
        // reason: a run scaled below one maximum batch has no full batch,
        // and `BatchPlan` keeps `fullBatchYield` at the maximum whatever
        // the count is — so an unguarded row reads "0 × 400 g" over the
        // single partial batch it contradicts.
        if (plan.fullBatchCount > 0)
          _Fact(
            label: l10n.productionSetupFullBatches,
            value: l10n.productionSetupFullBatchesValue(
              '${plan.fullBatchCount}',
              readableQuantity(plan.fullBatchYield),
            ),
          ),
        if (remainder != null)
          _Fact(
            label: l10n.productionSetupRemainder,
            value: readableQuantity(remainder),
          ),
        const Divider(height: 32),
        // The comparison against the base recipe. Both yields are read off
        // the calculated run rather than off the form or the row the
        // library listed, so a recipe edited since it was listed compares
        // against the revision the calculation actually used.
        _Fact(
          label: l10n.productionSetupBaseYield,
          value: readableQuantity(run.recipe.baseYield),
        ),
        _Fact(
          label: l10n.productionSetupTargetYield,
          // Written in the recipe's own unit rather than the operator's,
          // because this row exists to be compared with the one above it:
          // "1000 g" beside "2 kg" is the same run, and the arithmetic
          // between them is left to the reader. What was typed is still on
          // screen, in the field, in the unit it was typed in. The
          // conversion is the one the calculation already made — it
          // refuses a target its base yield cannot convert to, so a run
          // exists only when this direction is defined too.
          value: readableQuantity(
            run.targetYield.convertTo(run.recipe.baseYield.unit),
          ),
        ),
        _Fact(
          label: l10n.productionSetupScale,
          value: l10n.productionSetupScaleValue(_ratio(run.result.scaleRatio)),
        ),
      ],
    );
  }
}

/// One labelled value.
///
/// Both halves are given room to wrap rather than laid out at their
/// intrinsic widths: a long recipe-defined unit symbol at a large text
/// scale is what would otherwise run off the row.
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
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ],
    ),
  );
}

/// Something the operator has to read before this run can start.
class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Text(
      message,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}

/// The scale ratio as this screen writes it.
///
/// Four places rather than the six a quantity gets: nothing is computed
/// from this number — the two yields above it are the exact comparison,
/// and the domain keeps the ratio itself exact — so it is here to be read
/// at a glance rather than to be measured against. What happens when four
/// places cannot hold the ratio is `readableAmount`'s decision, and it is
/// the same decision a quantity gets.
String _ratio(Rational scaleRatio) => readableAmount(scaleRatio, scale: 4);

/// What a failed calculation says, carrying what the error itself names.
///
/// The three the operator can act on are named as the domain named them: a
/// recipe that is no longer stored, a sub-recipe that is not, and a cycle,
/// with the identifier or the path the domain found. The fourth is the
/// stored recipe having moved to a yield unit this target cannot convert
/// to — possible because the calculation reads the latest revision while
/// the form was laid out from the row the library listed.
String _errorMessage(AppLocalizations l10n, Object? error) => switch (error) {
  // The domain writes "recipe X is not in the index" when the run's own
  // root is absent rather than a reference dangling, and the two are
  // different things to the operator: one is the recipe they chose.
  MissingDependencyError(:final recipeId, :final missingId)
      when recipeId == missingId =>
    l10n.productionSetupMissingRecipe,
  MissingDependencyError(:final missingId) =>
    l10n.productionSetupMissingDependency(missingId),
  RecipeCycleError(:final path) => l10n.productionSetupCycleError(
    path.join(' → '),
  ),
  IncompatibleYieldUnitError(:final expected, :final actual) =>
    l10n.productionSetupIncompatibleStoredYield(expected.symbol, actual.symbol),
  // The same sentence `_Outcome` writes for a root over the limit, and
  // deliberately so: which recipe in the run planned too many batches is a
  // fact about the calculation, and what the operator does about it —
  // enter a smaller amount — is the same either way. The recipe id the
  // error carries would name a sub-recipe the screen never showed them.
  BatchLimitExceededError(:final maxPlannedBatches) =>
    l10n.productionSetupTargetTooLarge('$maxPlannedBatches'),
  _ => l10n.productionSetupFailed,
};
