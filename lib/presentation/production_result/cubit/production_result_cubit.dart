import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/units/built_in_units.dart';

part 'production_result_state.dart';

/// Drives the production result screen.
///
/// Holds the three use cases the screen reviews and commits through, never
/// storage itself, for the reason the recipe library screen's cubit gives.
///
/// The run arrives calculated. Nothing here recalculates it: acknowledging
/// a warning and recording an override each return a new snapshot with the
/// same result inside, and the screen renders whichever one it last
/// received.
final class ProductionResultCubit extends Cubit<ProductionResultState> {
  /// Creates the cubit over the use cases it reviews [run] through.
  ProductionResultCubit(
    this._acknowledgeWarning,
    this._applyOverride,
    this._saveProductionRun, {
    required ProductionRun run,
  }) : super(ProductionResultState(run: run));

  final AcknowledgeWarning _acknowledgeWarning;
  final ApplyOverride _applyOverride;
  final SaveProductionRun _saveProductionRun;

  /// Opens the line at [path], or closes it when it is already open.
  ///
  /// Closing leaves the lines underneath recorded as open, so reopening a
  /// sub-recipe brings back exactly the tree the operator had.
  void expansionToggled(String path) => emit(
    state.copyWith(
      expandedPaths: state.isExpanded(path)
          ? ({...state.expandedPaths}..remove(path))
          : {...state.expandedPaths, path},
    ),
  );

  /// Records that the operator has seen [warning].
  ///
  /// Refused once the run has stopped being editable, for the reason
  /// [save] gives about its own guard: the controls go dead a frame after
  /// the state does, so a tap landing inside that frame would record an
  /// acknowledgement the snapshot being written never carries.
  void warningAcknowledged(ProductionWarning warning) {
    if (!state.isEditable) return;
    emit(state.copyWith(run: _acknowledgeWarning(state.run, warning)));
  }

  /// Records what has been typed into [row]'s override amount.
  void overrideAmountChanged(ResultRow row, String amount) =>
      _drafted(row, state.draftFor(row).copyWith(amount: amount));

  /// Records the unit [row]'s override is measured in.
  void overrideUnitChanged(ResultRow row, Unit unit) =>
      _drafted(row, state.draftFor(row).copyWith(unit: unit));

  /// Holds [draft] against [row] and, when it describes a quantity,
  /// records that quantity on the run.
  ///
  /// The draft is what the field shows and the override is what the run
  /// carries, and they are deliberately not the same thing: a draft the
  /// operator is halfway through typing — `1.`, or an emptied field — is
  /// not a value, so it updates the field and leaves the run alone. What
  /// that means in practice is that an override, once recorded, stays
  /// recorded: clearing the field reports itself as an invalid amount
  /// rather than silently withdrawing the value. The domain has no
  /// vocabulary for withdrawing one, and inventing a removal here would be
  /// a domain change made in a screen.
  ///
  /// Both entry points are refused once the run has stopped being
  /// editable, and the guard sits here rather than on each of them
  /// because this is where they meet. Neither the draft nor the run
  /// moves: a draft recorded against a run nothing can still change is a
  /// field the operator cannot act on.
  void _drafted(ResultRow row, OverrideDraft draft) {
    if (!state.isEditable) return;
    final value = draft.quantity;
    emit(
      state.copyWith(
        overrideDrafts: {...state.overrideDrafts, row.key: draft},
        run: value == null
            ? state.run
            : _applyOverride(
                state.run,
                recipeId: row.key.$1,
                componentId: row.key.$2,
                value: value,
              ),
      ),
    );
  }

  /// Commits the run as an immutable snapshot.
  ///
  /// Refuses outright once a save is in flight or has succeeded, rather
  /// than relying on the button being disabled: the repository's write is
  /// a bare insert against a primary key, so a second save of the same run
  /// throws, and two taps landing inside one frame is exactly how that
  /// happens. The status moves before the first suspension, so the second
  /// call sees it — and so do [warningAcknowledged] and the override
  /// mutators, which refuse for the same reason on the same frame.
  ///
  /// A run that is not finalizable is saved all the same. The application
  /// layer rules that storing a draft is not finalizing it; what the
  /// screen owes the operator is to say which of the two they are doing,
  /// not to refuse one of them.
  ///
  /// A half-typed override is the one thing that does refuse it, and for a
  /// different reason: the run carries the last value that parsed, so a
  /// save while a control reads an error stores a number the operator was
  /// part-way through replacing — into a snapshot nothing can amend.
  /// Refused here as well as on the button, since the button being
  /// disabled says nothing about what may call this.
  Future<void> save() async {
    if (!state.canSave) return;
    emit(state.copyWith(status: ProductionResultStatus.saving));
    try {
      await _saveProductionRun(state.run);
      if (isClosed) return;
      emit(state.copyWith(status: ProductionResultStatus.saved));
    } on Object catch (error, stackTrace) {
      // Reported as well as rendered, for the reason the library screen's
      // cubit gives: the screen names what the error names, and
      // `AppBlocObserver` is where the whole thing is logged.
      addError(error, stackTrace);
      if (isClosed) return;
      emit(
        state.copyWith(status: ProductionResultStatus.failure, error: error),
      );
    }
  }
}
