import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/units/built_in_units.dart';

part 'production_setup_state.dart';

/// Drives the production setup screen.
///
/// Holds the use case, never storage itself, for the reason the recipe
/// library screen's cubit gives.
///
/// The run it calculates is never stored: `StartProductionRun` returns an
/// unsaved snapshot by contract, and this screen exists to show the
/// operator what today's target becomes before they commit to it.
final class ProductionSetupCubit extends Cubit<ProductionSetupState> {
  /// Creates the cubit over the use case it calculates through, for
  /// [recipe] — the revision the library screen listed.
  ///
  /// [previewDebounce] is how long the target must stay still before a
  /// calculation runs. Not zero, for the reason the library screen's search
  /// gives: a calculation is a read per recipe the run depends on, and
  /// without the wait every keystroke paid all of them.
  ProductionSetupCubit(
    this._startProductionRun, {
    required Recipe recipe,
    Duration previewDebounce = const Duration(milliseconds: 250),
  }) : _debounce = previewDebounce,
       super(
         ProductionSetupState(
           recipe: recipe,
           // The recipe's own yield unit, which is the one unit every
           // recipe can always take: outside mass and volume it is the only
           // one, and a screen that opened on a unit the recipe cannot
           // convert to would open reporting an error nobody caused.
           targetUnit: recipe.baseYield.unit,
         ),
       );

  final StartProductionRun _startProductionRun;
  final Duration _debounce;

  /// Counts target changes, so a slow calculation cannot overwrite a newer
  /// one and a debounced calculation that a newer target superseded never
  /// runs at all. The same device the library screen's cubit uses, and for
  /// the same two jobs.
  int _intents = 0;

  /// Records the typed target amount and calculates what it becomes.
  Future<void> targetAmountChanged(String value) =>
      _retarget(_blank(targetAmount: value));

  /// Records the chosen target unit and calculates what it becomes.
  ///
  /// Accepts any unit, including one the recipe's yield cannot convert to:
  /// the screen's picker offers only compatible ones, but this is the entry
  /// point, and [ProductionSetupState.targetUnitIsIncompatible] is what
  /// reports an incompatible unit rather than letting it reach a
  /// calculation that would throw on it.
  Future<void> targetUnitChanged(Unit unit) =>
      _retarget(_blank(targetUnit: unit));

  /// [state] with the named field replaced and the last calculation
  /// dropped.
  ///
  /// Dropping it is deliberate: a batch plan is only true of the target it
  /// was calculated from, and "three batches of five kilograms" left
  /// standing under a target the operator has since edited is the one thing
  /// on this screen a kitchen could act on and be wrong about. The library
  /// screen keeps its rows on screen through a search for the opposite
  /// reason — a stale list is still a list of real recipes.
  ProductionSetupState _blank({String? targetAmount, Unit? targetUnit}) =>
      state.copyWith(
        targetAmount: targetAmount,
        targetUnit: targetUnit,
        status: ProductionSetupStatus.idle,
        clearOutcome: true,
      );

  /// Emits [next], then calculates the run it describes once the target has
  /// stayed still for the debounce window.
  Future<void> _retarget(ProductionSetupState next) async {
    emit(next);
    // Counted before the early return below, not after it. Clearing the
    // field has to abandon a calculation that is already waiting or already
    // in flight: an amount the operator deleted must never come back as a
    // result, and returning without taking a number would leave the older
    // intent as the newest one and let it emit.
    final intent = ++_intents;
    final target = next.targetYield;
    if (target == null) return;

    await Future<void>.delayed(_debounce);
    if (isClosed || intent != _intents) return;
    emit(state.copyWith(status: ProductionSetupStatus.calculating));

    final outcome = await _outcomeOf(target);
    if (isClosed || intent != _intents) return;
    emit(outcome);
  }

  /// The state calculating [target] produces, whether it returns or throws.
  ///
  /// Both branches build on the `state` as it is once the calculation has
  /// finished rather than on a snapshot taken before it suspended, for the
  /// reason the library screen's cubit states.
  Future<ProductionSetupState> _outcomeOf(Quantity target) async {
    try {
      final run = await _startProductionRun(
        recipeId: state.recipe.id,
        targetYield: target,
        // The bound the screen states, carried into the calculation
        // itself. `ProductionSetupState.targetExceedsBatchLimit` has
        // already refused what it can see, and it sees one recipe: the
        // sub-recipes a run expands are not loaded until this call, and
        // their own maximum batch yields are where a target the root
        // absorbs in a single batch becomes millions of them. Passing it
        // here is what makes the bound true of the whole run rather than
        // of its root alone.
        maxPlannedBatches: ProductionSetupState.maxPlannedBatches,
      );
      return state.copyWith(status: ProductionSetupStatus.ready, preview: run);
    } on Object catch (error, stackTrace) {
      // Reported as well as rendered, for the reason the library screen's
      // cubit gives: the screen names what the error names, and
      // `AppBlocObserver` is where the whole thing is logged.
      addError(error, stackTrace);
      return state.copyWith(
        status: ProductionSetupStatus.failure,
        error: error,
      );
    }
  }
}
