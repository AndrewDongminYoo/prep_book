part of 'production_setup_cubit.dart';

/// What the production setup screen is currently doing.
enum ProductionSetupStatus {
  /// Nothing has been calculated: the target on screen is blank, or not
  /// something a run can be calculated from.
  idle,

  /// A calculation is in flight.
  calculating,

  /// The last calculation returned; [ProductionSetupState.preview] is it.
  ready,

  /// The last calculation threw; [ProductionSetupState.error] is what it
  /// threw.
  failure,
}

/// View state for the production setup screen.
///
/// Equality is left at identity, matching the two screens before it and the
/// domain layer's rule that only the types something compares by value
/// define `==`.
@immutable
final class ProductionSetupState {
  /// Creates a state.
  const ProductionSetupState({
    required this.recipe,
    required this.targetUnit,
    this.status = ProductionSetupStatus.idle,
    this.targetAmount = '',
    this.preview,
    this.error,
  });

  /// What the screen is doing.
  final ProductionSetupStatus status;

  /// The recipe revision the library screen listed.
  ///
  /// What the form is laid out from — its name, its base yield, and the
  /// units the target may be expressed in. It is not what the calculation
  /// reads: the use case reads the latest stored revision itself, so
  /// [preview] can disagree with this, and where the two differ the
  /// calculated one is the one rendered.
  final Recipe recipe;

  /// The typed target amount.
  ///
  /// Text rather than a [Quantity], for the reason the editor's component
  /// drafts give: half-typed input has no domain value, and `1.` throws.
  final String targetAmount;

  /// The unit the target amount is measured in.
  final Unit targetUnit;

  /// The last calculated run, or `null` when none has been calculated for
  /// the target now on screen.
  ///
  /// Never stored, and never recalculated by this screen: everything it
  /// renders — the batch plan and the ratio against the base recipe — is
  /// read off this value as the domain calculated it.
  final ProductionRun? preview;

  /// What the last calculation threw, or `null` when it returned.
  final Object? error;

  /// [text] as a positive decimal, or `null` when it is neither.
  static Decimal? _positive(String text) {
    final value = Decimal.tryParse(text.trim());
    return value != null && value > Decimal.zero ? value : null;
  }

  /// Whether what is typed in the amount field is something other than a
  /// positive number.
  ///
  /// An empty field is not invalid. Nothing has been typed yet, so there is
  /// nothing to report, and a screen that opens by naming a missing amount
  /// blames the operator for not having had a turn. It is still not a
  /// target — [targetYield] is `null` and [canContinue] is false for it —
  /// it just says nothing about it.
  bool get amountIsInvalid =>
      targetAmount.trim().isNotEmpty && _positive(targetAmount) == null;

  /// Whether the chosen unit is one the recipe's base yield cannot convert
  /// to.
  ///
  /// Checked here rather than left to the calculation, which throws
  /// [IncompatibleYieldUnitError] for it: a screen that only reported the
  /// throw would make the operator submit a target to find out it was never
  /// possible. The check is the same one the domain makes —
  /// [Unit.canConvertTo], in the argument order `ProductionCalculator` uses
  /// — so the two cannot drift into disagreeing about a pair.
  ///
  /// The mirror of `RecipeEditorState.maxBatchUnitIsIncompatible`, which is
  /// the same shape one screen earlier: a second yield measured against the
  /// recipe's own.
  bool get targetUnitIsIncompatible =>
      !recipe.baseYield.unit.canConvertTo(targetUnit);

  /// The largest batch count this screen calculates a preview for, for any
  /// one recipe the run touches.
  ///
  /// A bound on the work one keystroke can start, not a product rule about
  /// how large a run may be. The calculation is synchronous once it begins
  /// and nothing can abandon it in flight — the cubit's intent check runs
  /// only after it has returned — so its cost has to be bounded before it
  /// starts rather than interrupted afterwards. It allocates and folds one
  /// entry per batch per component, measured at roughly four microseconds
  /// per batch on a component-light recipe, so a thousand batches stays
  /// inside one frame while a target typed with a few more digits does not.
  ///
  /// Enforced in two places, because one of them cannot see the whole run.
  /// [targetExceedsBatchLimit] answers it for the recipe on screen without
  /// reading anything, which is what keeps a target with too many digits
  /// from costing a repository read per dependency. The authoritative check
  /// is the same number handed to `StartProductionRun` by the cubit, which
  /// applies it to every batch plan the calculation builds — a run's
  /// sub-recipes are scaled against their own maximum batch yields, so a
  /// target the root absorbs in a single batch can still expand into
  /// millions below it, and that plan is not knowable until the closure
  /// has been loaded.
  ///
  /// A thousand batches of a recipe's own maximum is past anything the
  /// small restaurants and bakeries this is for produce in a day — four
  /// hundred kilograms of dough against a four-hundred-gram maximum — so
  /// no target an operator means lands above it.
  static const int maxPlannedBatches = 1000;

  /// Whether the typed target would take more than [maxPlannedBatches]
  /// batches of the recipe this form was laid out from.
  ///
  /// The cheap half of the bound [maxPlannedBatches] describes: it answers
  /// for one recipe, with no repository read and no wait, so an obviously
  /// oversized target is refused as it is typed. It is not the whole
  /// bound, and a false answer here is not a promise that the run is small
  /// — only that its root is. What the calculation expands underneath is
  /// bounded by the same number where the sub-recipes are actually known,
  /// and reaches this screen as a `BatchLimitExceededError`.
  ///
  /// The predicate is exact and needs no batch plan: a recipe takes more
  /// than `n` batches exactly when its target exceeds `n` maximum batches,
  /// since `BatchPlan` splits the target into full maximum batches plus at
  /// most one remainder. So one comparison answers it, with no division, no
  /// `floor`, and no batch count to overflow. Both sides convert into the
  /// recipe's own yield unit first — a pair `Recipe` has already accepted
  /// for the maximum, and [targetUnitIsIncompatible] for the target — so
  /// neither conversion can throw.
  ///
  /// False for a recipe with no maximum batch yield: that recipe is a
  /// single batch whatever the target, so nothing about its own plan
  /// grows.
  bool get targetExceedsBatchLimit {
    final amount = _positive(targetAmount);
    final maxBatch = recipe.maxBatchYield;
    if (amount == null || targetUnitIsIncompatible || maxBatch == null) {
      return false;
    }
    final baseUnit = recipe.baseYield.unit;
    final target = Quantity.fromDecimal(amount, targetUnit).convertTo(baseUnit);
    final bound =
        maxBatch.convertTo(baseUnit).amount *
        Rational.fromInt(maxPlannedBatches);
    return target.amount > bound;
  }

  /// The target the form describes, or `null` when it describes none the
  /// calculation may be run against.
  Quantity? get targetYield {
    final amount = _positive(targetAmount);
    if (amount == null || targetUnitIsIncompatible || targetExceedsBatchLimit) {
      return null;
    }
    return Quantity.fromDecimal(amount, targetUnit);
  }

  /// The units the target amount may be measured in.
  ///
  /// Narrowed to what the recipe's own base yield converts to, which is the
  /// design document's "compatible yield unit": outside mass and volume
  /// that is the yield unit itself and nothing else, and every unit a wider
  /// list would add is one the calculation throws on. Narrowing also keeps
  /// the choices unambiguous — everything the filter admits shares the base
  /// yield's dimension, and two units of one dimension that print the same
  /// symbol are the same unit, so no two of those rows can read alike.
  ///
  /// [targetUnit] is offered whether or not it belongs there, the rule
  /// `RecipeEditorState.unitChoicesFor` states for a component's own unit
  /// and for the same reason: a dropdown whose value is missing from its
  /// items throws. Nothing on the screen can choose an incompatible one —
  /// `ProductionSetupCubit.targetUnitChanged` can, and
  /// [targetUnitIsIncompatible] is what says so when it does.
  ///
  /// The recipe's maximum batch yield is not consulted: `Recipe` already
  /// refuses a maximum its base yield cannot convert to, so its unit is
  /// either a built-in one or the base yield's own, and both are here.
  List<Unit> get unitChoices => <Unit>{
    for (final unit in builtInUnits)
      if (recipe.baseYield.unit.canConvertTo(unit)) unit,
    recipe.baseYield.unit,
    targetUnit,
  }.toList();

  /// The names of every archived recipe this run would depend on, the root
  /// recipe included, in the order the calculation raised them.
  ///
  /// Read off the calculated run rather than off [recipe], because the row
  /// the library listed is not what the calculation read: this covers a
  /// recipe archived after that list was drawn, and an archived sub-recipe
  /// no row ever showed.
  ///
  /// Selected by type rather than by `ProductionWarning.isBlocking`, which
  /// is true of the manual-component warning too. A recipe with a free-form
  /// line is a run the operator reviews on the result screen, not one this
  /// screen refuses to start; an archived dependency is the one the design
  /// document says blocks a new production run outright.
  List<String> get archivedDependencies {
    final run = preview;
    if (run == null) return const [];
    return [
      for (final warning
          in run.result.warnings.whereType<ArchivedDependencyWarning>())
        _nameOf(run, warning.recipeId),
    ];
  }

  /// What the recipe [recipeId] is called, taken from the run's own
  /// snapshot so an archived dependency is named the way the operator knows
  /// it rather than by identifier.
  static String _nameOf(ProductionRun run, String recipeId) =>
      run.recipe.id == recipeId
      ? run.recipe.name
      : run.dependencySnapshot[recipeId]?.name ?? recipeId;

  /// Whether the operator may carry this target through to the production
  /// result.
  ///
  /// False for everything this screen or the domain rejects: an amount that
  /// is not a positive number, a unit the recipe's yield cannot convert to,
  /// a calculation that has not returned or that threw, and an archived
  /// recipe anywhere in the run.
  ///
  /// Nothing on the screen reads this yet. Continue has no destination in
  /// this slice and is rendered disabled the way the library screen's
  /// Production Run action was before this change, so the rule lives here,
  /// where `production_setup_cubit_test.dart` pins it, and the slice that
  /// builds the result screen gates its route on it.
  bool get canContinue =>
      preview != null &&
      !amountIsInvalid &&
      !targetUnitIsIncompatible &&
      archivedDependencies.isEmpty;

  /// This state with the named fields replaced.
  ///
  /// [status] is required rather than optional, unlike every other
  /// parameter here: there is no change to this state that leaves what the
  /// screen is doing alone. Typing moves it back to idle, the window
  /// elapsing moves it to calculating, and the calculation moves it to one
  /// of the last two — so a caller that had nothing to say about the
  /// status would be a caller that forgot.
  ///
  /// [preview] and [error] are one thing in two shapes — the outcome of one
  /// calculation, at most one of which is ever present — so they move
  /// together: passing either replaces both, and [clearOutcome] drops both.
  /// That is what keeps a failure's message from surviving under the next
  /// calculation's batch plan, which `??` on its own could not express: it
  /// cannot tell "clear this" from "leave it alone".
  ProductionSetupState copyWith({
    required ProductionSetupStatus status,
    String? targetAmount,
    Unit? targetUnit,
    ProductionRun? preview,
    Object? error,
    bool clearOutcome = false,
  }) {
    final outcomeReplaced = clearOutcome || preview != null || error != null;
    return ProductionSetupState(
      recipe: recipe,
      status: status,
      targetAmount: targetAmount ?? this.targetAmount,
      targetUnit: targetUnit ?? this.targetUnit,
      preview: outcomeReplaced ? preview : this.preview,
      error: outcomeReplaced ? error : this.error,
    );
  }
}
