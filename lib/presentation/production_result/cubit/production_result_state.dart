part of 'production_result_cubit.dart';

/// What the production result screen is currently doing.
enum ProductionResultStatus {
  /// The operator is reviewing the run. Nothing has been stored.
  reviewing,

  /// A save is in flight.
  saving,

  /// The snapshot is stored. This screen never writes to it again.
  saved,

  /// The last save threw; [ProductionResultState.error] is what it threw.
  failure,
}

/// A half-entered operator value for one component.
///
/// Text rather than a [Quantity], for the reason the recipe editor's
/// component drafts give: half-typed input has no domain value, and `1.`
/// throws. The unit is held beside it because an override is a quantity —
/// a number the operator types means nothing until it is measured in
/// something.
@immutable
final class OverrideDraft {
  /// Creates a draft measured in [unit], empty unless [amount] is given.
  const OverrideDraft({required this.unit, this.amount = ''});

  /// The typed amount.
  final String amount;

  /// The unit the amount is measured in.
  final Unit unit;

  /// [amount] as a positive decimal, or `null` when it is neither.
  Decimal? get _positive {
    final value = Decimal.tryParse(amount.trim());
    return value != null && value > Decimal.zero ? value : null;
  }

  /// Whether what is typed is something other than a positive number.
  ///
  /// An empty field is not invalid, the rule the production setup screen
  /// states: nothing has been typed, so there is nothing to report. It is
  /// still not a value — [quantity] is `null` for it.
  bool get amountIsInvalid => amount.trim().isNotEmpty && _positive == null;

  /// The quantity this draft describes, or `null` when it describes none.
  Quantity? get quantity {
    final amount = _positive;
    return amount == null ? null : Quantity.fromDecimal(amount, unit);
  }

  /// This draft with the named fields replaced.
  OverrideDraft copyWith({String? amount, Unit? unit}) =>
      OverrideDraft(unit: unit ?? this.unit, amount: amount ?? this.amount);
}

/// A run of consecutive batches that all take the same amount.
///
/// A run's per-batch amounts repeat by construction — a proportional
/// component is the same in every full batch and differs only in the
/// remainder, a `perBatch` one is the same in all of them, and a
/// `fixedOnce` one is the whole amount in the first and nothing after — so
/// grouping is what keeps a thousand-batch run from rendering a thousand
/// identical lines. It is a display grouping and nothing more: the
/// underlying list is the domain's, untouched.
@immutable
final class BatchGroup {
  /// Creates a group covering batches [firstBatch] to [lastBatch], both
  /// counted from one, each taking [amount].
  const BatchGroup({
    required this.firstBatch,
    required this.lastBatch,
    required this.amount,
  });

  /// The first batch in the group, counted from one.
  final int firstBatch;

  /// The last batch in the group, counted from one.
  final int lastBatch;

  /// What each batch in the group takes, absent for a manual component.
  final ScaledQuantity? amount;

  /// Whether the group covers more than one batch.
  bool get isRange => lastBatch > firstBatch;
}

/// One rendered line of the result tree.
///
/// [path] is the line's position in that tree — the index of each component
/// from the root down, joined — and it is what expansion is keyed on. Not
/// the component id, and not [key]: a sub-recipe referenced twice is two
/// lines carrying one component id, and collapsing one of them must not
/// collapse the other. Index digits and the separator are disjoint, so no
/// two paths can spell alike, and the tree is a frozen snapshot, so an
/// index cannot move under a path already recorded.
@immutable
final class ResultRow {
  /// Creates a row.
  const ResultRow({
    required this.path,
    required this.depth,
    required this.recipeId,
    required this.component,
  });

  /// The line's position in the tree.
  final String path;

  /// How many sub-recipes deep the line sits, zero at the root.
  final int depth;

  /// The recipe the component belongs to.
  final String recipeId;

  /// The calculated line itself.
  final ScaledComponent component;

  /// What an override on this line is recorded under.
  ///
  /// A pair, never a component id alone, because a component id is only
  /// unique within its own recipe — `ProductionRun.overrides` says so, and
  /// this is the same key. Two lines that are the same component of the
  /// same recipe therefore share one override, which is the domain's
  /// ruling: an override reads as "the flour in the dough", not "the flour
  /// in the second dough".
  OverrideKey get key => (recipeId, component.source.id);

  /// The run's total for this line, absent for an unresolved manual one.
  ScaledQuantity? get total => component.total;

  /// Whether this line carries no calculated amount at all.
  bool get isManual => component.total == null;

  /// The line's per-batch amounts, consecutive equal ones grouped.
  List<BatchGroup> get batches {
    final groups = <BatchGroup>[];
    for (var index = 0; index < component.perBatch.length; index++) {
      final amount = component.perBatch[index];
      final open = groups.isEmpty ? null : groups.last;
      if (open != null && _sameAmount(open.amount, amount)) {
        groups[groups.length - 1] = BatchGroup(
          firstBatch: open.firstBatch,
          lastBatch: index + 1,
          amount: amount,
        );
      } else {
        groups.add(
          BatchGroup(
            firstBatch: index + 1,
            lastBatch: index + 1,
            amount: amount,
          ),
        );
      }
    }
    return groups;
  }

  /// Whether two batch amounts read alike.
  ///
  /// Both halves are compared, not just the displayed one: two batches
  /// showing `1 g` where one was rounded from `0.6 g` and the other from
  /// `0.9 g` are not the same line, and merging them would hide the exact
  /// values the spec keeps visible.
  static bool _sameAmount(ScaledQuantity? left, ScaledQuantity? right) {
    if (left == null || right == null) return left == null && right == null;
    return left.exact == right.exact && left.displayed == right.displayed;
  }
}

/// View state for the production result screen.
///
/// Equality is left at identity, matching the three screens before it and
/// the domain layer's rule that only the types something compares by value
/// define `==`.
@immutable
final class ProductionResultState {
  /// Creates a state over the calculated [run].
  ///
  /// Not a `const` constructor: [allRows] holds its walk in a `late final`
  /// field, and a class carrying one cannot have a const constructor.
  /// Nothing lost a `const` in the trade — every construction of this
  /// state in `lib/` and `test/` was already a plain call.
  ProductionResultState({
    required this.run,
    this.status = ProductionResultStatus.reviewing,
    this.expandedPaths = const {},
    this.overrideDrafts = const {},
    this.error,
  });

  /// The run under review.
  ///
  /// Replaced whenever a use case returns a new one — acknowledging a
  /// warning and recording an override both do — never mutated. The
  /// calculated result inside it is never recalculated: overriding a value
  /// records what the operator will actually use and leaves the
  /// calculation as it was, which is the domain's ruling and what keeps
  /// the original available for comparison.
  final ProductionRun run;

  /// What the screen is doing.
  final ProductionResultStatus status;

  /// The tree positions the operator has opened.
  ///
  /// Empty to begin with: the design document keeps sub-recipes collapsed
  /// until the operator expands them.
  final Set<String> expandedPaths;

  /// What has been typed into each line's override control, keyed the way
  /// the run keys an override.
  final Map<OverrideKey, OverrideDraft> overrideDrafts;

  /// What the last save threw, read only while [status] is
  /// [ProductionResultStatus.failure].
  final Object? error;

  /// Every line of the run, parent before child, in display order.
  ///
  /// Collapsed lines included: a warning names a component wherever it
  /// sits, and the screen has to be able to name that component whether or
  /// not the operator has opened the sub-recipe it lives in.
  ///
  /// Walked once per state instead of once per read. [visibleRows],
  /// [_componentLabels] and [_runUnits] each read it, and [unitChoicesFor]
  /// reaches [_runUnits] from every override control on screen, so one
  /// build of a large expanded run re-ran the whole recursion once per
  /// control. Caching on the instance rather than anywhere longer-lived is
  /// what makes that safe: a new state is emitted whenever the run or the
  /// expansion set moves, which is the only way these rows could differ.
  ///
  /// Unmodifiable because the walk now has one owner. A caller that sorted
  /// or filtered the returned list in place used to spoil only its own
  /// copy and would now spoil the row order every later reader sees.
  late final List<ResultRow> allRows = () {
    final rows = <ResultRow>[];
    _collect(run.result, run.recipe.id, '', 0, rows);
    return List<ResultRow>.unmodifiable(rows);
  }();

  /// The lines the operator can currently see.
  List<ResultRow> get visibleRows => [
    for (final row in allRows)
      if (_isVisible(row.path)) row,
  ];

  /// Whether the line at [path] is open.
  bool isExpanded(String path) => expandedPaths.contains(path);

  /// Whether every one of [path]'s ancestors is open.
  ///
  /// Derived rather than tracked, so collapsing a line hides everything
  /// under it without the collapse having to walk the tree — and so
  /// reopening it brings back exactly what was open before.
  bool _isVisible(String path) =>
      ancestorsOf(path).every(expandedPaths.contains);

  /// Every path that has to be open for the line at [path] to be seen,
  /// outermost first.
  ///
  /// The line's own path is not among them: opening a line shows what sits
  /// under it, not the line itself. So a root line has no ancestors and is
  /// visible unconditionally.
  static Iterable<String> ancestorsOf(String path) sync* {
    final segments = path.split('/');
    for (var depth = 1; depth < segments.length; depth++) {
      yield segments.take(depth).join('/');
    }
  }

  /// Where the component [key] names sits in the tree, or `null` when no
  /// line carries it.
  ///
  /// The first occurrence in display order when there are several. A
  /// component id is unique inside its own recipe, so two lines share a key
  /// only when one recipe is reached by two routes — a sub-recipe
  /// referenced twice — and a warning is raised against the component
  /// rather than against either route. Which of them to show is therefore a
  /// choice with no better answer available, and it is the same one the
  /// override control makes: a value recorded on either row reaches both.
  String? pathOf(OverrideKey key) {
    for (final row in allRows) {
      if (row.key == key) return row.path;
    }
    return null;
  }

  /// Appends every component of [result] to [into], recursing into the
  /// sub-recipes the domain already expanded.
  static void _collect(
    ProductionResult result,
    String recipeId,
    String prefix,
    int depth,
    List<ResultRow> into,
  ) {
    for (var index = 0; index < result.components.length; index++) {
      final component = result.components[index];
      final path = prefix.isEmpty ? '$index' : '$prefix/$index';
      into.add(
        ResultRow(
          path: path,
          depth: depth,
          recipeId: recipeId,
          component: component,
        ),
      );
      final nested = component.subRecipe;
      if (nested == null) continue;
      // A nested result only ever hangs off a sub-recipe reference — the
      // calculator builds one nowhere else — and the pattern is how the
      // referenced recipe's own id is read, since a `ProductionResult`
      // does not carry one.
      if (component.source.target case SubRecipeRef(recipeId: final child)) {
        _collect(nested, child, path, depth + 1, into);
      }
    }
  }

  /// What the component on [row] is called.
  ///
  /// Both kinds of target are named from the run's own snapshots, so each
  /// reads as it was named when the run was calculated rather than as it is
  /// named now. Nothing here reads today's library: that would put a name
  /// on a stored run that was never part of it, and a run is a record of
  /// what happened.
  String labelOf(ResultRow row) => switch (row.component.source.target) {
    SubRecipeRef(:final recipeId) => recipeNameOf(recipeId),
    IngredientRef(:final ingredientId) => ingredientNameOf(ingredientId),
  };

  /// What the recipe [recipeId] is called, taken from the run's snapshot.
  String recipeNameOf(String recipeId) => recipeId == run.recipe.id
      ? run.recipe.name
      : run.dependencySnapshot[recipeId]?.name ?? recipeId;

  /// What the ingredient [ingredientId] is called, taken from the run's
  /// snapshot.
  ///
  /// Falls back to the identifier, which is what a run stored before the
  /// snapshot carried ingredients holds for every one of its lines, and
  /// what any run holds for an ingredient that was already out of the
  /// library when it was calculated. Rendering the identifier is worse than
  /// rendering a name and better than rendering nothing, and it is what
  /// this screen did for every ingredient before the snapshot existed.
  String ingredientNameOf(String ingredientId) =>
      run.ingredientSnapshot[ingredientId]?.name ?? ingredientId;

  /// What the component a component-level warning names is called.
  String componentLabelOf(OverrideKey key) => _componentLabels[key] ?? key.$2;

  /// Every line's label, keyed the way a warning addresses it. Two lines
  /// that share a key are the same component of the same recipe, so they
  /// carry the same label and collapsing them loses nothing.
  Map<OverrideKey, String> get _componentLabels => {
    for (final row in allRows) row.key: labelOf(row),
  };

  /// Everything the operator must see, in the order the calculation raised
  /// it.
  List<ProductionWarning> get warnings => run.result.warnings;

  /// The component-level warnings raised against [row], in calculation order.
  ///
  /// Recipe-level warnings have no component key, so they remain outside the
  /// component list.
  List<ProductionWarning> warningsFor(ResultRow row) => [
    for (final warning in warnings)
      if (switch (warning) {
        ManualComponentWarning(:final recipeId, :final componentId) =>
          (recipeId, componentId) == row.key,
        RoundingAdjustedWarning(:final recipeId, :final componentId) =>
          (recipeId, componentId) == row.key,
        ArchivedDependencyWarning() => false,
      })
        warning,
  ];

  /// Whether [warning] has been marked as seen.
  bool isAcknowledged(ProductionWarning warning) =>
      run.acknowledgedWarnings.contains(warning);

  /// How many blocking warnings are still unacknowledged.
  ///
  /// What the save notice counts. Whether the run is finalizable at all is
  /// [savesAsDraft]'s question, and that one is the run's own to answer.
  int get blockingWarningsOutstanding => warnings
      .where((warning) => warning.isBlocking && !isAcknowledged(warning))
      .length;

  /// Whether saving now stores a run that is not yet finalizable.
  ///
  /// Read off the run rather than recounted here, so which warnings block
  /// is decided in one place. Saving is permitted either way — the
  /// application layer rules that storing a draft is not finalizing it —
  /// and this is what the screen says so with.
  bool get savesAsDraft => !run.isFinalizable;

  /// Whether the operator may still change the run.
  ///
  /// One predicate for three jobs: the save action reads it, every inline
  /// control reads it, and so does every mutator behind those controls.
  /// The last of the three is not a duplicate of the second — a control is
  /// rebuilt a frame after the state moves, so a control still enabled on
  /// screen is not evidence that the run may still be changed. Once a save
  /// is in flight the run must not move under it, and once the snapshot is
  /// stored this screen has no way to amend it — recording state against a
  /// stored run is a different use case, on a screen this slice does not
  /// build — so a change accepted after either point would be a lie.
  bool get isEditable =>
      status == ProductionResultStatus.reviewing ||
      status == ProductionResultStatus.failure;

  /// The lines whose override control holds something that is not an
  /// amount, in the order the operator typed into them.
  List<OverrideKey> get _invalidOverrides => [
    for (final entry in overrideDrafts.entries)
      if (entry.value.amountIsInvalid) entry.key,
  ];

  /// Whether any override control is holding a value the run did not take.
  bool get hasInvalidOverride => _invalidOverrides.isNotEmpty;

  /// What those lines are called, for the notice that names them.
  ///
  /// Named rather than merely counted because a draft outlives the control
  /// that shows it: collapsing a line removes its field and its error
  /// message while leaving the draft recorded, so a notice that only said
  /// "an amount is wrong" would leave the operator with nothing on screen
  /// to act on.
  String get invalidOverrideLabels =>
      _invalidOverrides.map(componentLabelOf).join(', ');

  /// Whether the operator may commit the run as it stands.
  ///
  /// Narrower than [isEditable], and deliberately a second predicate rather
  /// than a tightening of that one: every inline control reads
  /// [isEditable], so folding this in would disable the very field the
  /// operator has to use to correct the value. A half-typed override is
  /// only a draft — the run still carries whatever was last valid — so
  /// saving over it would freeze a value the operator was in the middle of
  /// replacing, and the snapshot is immutable, so no screen could amend it
  /// afterwards.
  bool get canSave => isEditable && !hasInvalidOverride;

  /// What has been typed into [row]'s override control.
  ///
  /// An untouched control starts empty rather than pre-filled with the
  /// calculated amount: a field carrying a number the operator never typed
  /// cannot be told apart from an override they meant. Its unit starts at
  /// the calculated line's own, or at grams for a manual line, which has
  /// no calculated unit to start from and is the fallback the recipe
  /// editor's drafts already use.
  OverrideDraft draftFor(ResultRow row) =>
      overrideDrafts[row.key] ??
      OverrideDraft(unit: row.total?.displayed.unit ?? Unit.gram);

  /// The value the operator has recorded for [row], or `null` for none.
  Quantity? overrideFor(ResultRow row) => run.overrides[row.key];

  /// Every unit the run itself is measured in: the yield asked for, the
  /// yield of each recipe it depends on, and the calculated amount of
  /// every line in the tree, however deep.
  ///
  /// Discovered from the run rather than listed, which is the rule
  /// `built_in_units.dart` states for every picker in this app: `Unit.count`
  /// and `Unit.namedYield` build a unit from any symbol, so no fixed table
  /// can name an ingredient counted in sheets or a recipe measured in
  /// trays. The lines are read off [allRows], which has already walked the
  /// sub-recipes the domain expanded, so a nested line's unit arrives
  /// without a second recursion.
  ///
  /// The dependency snapshot is read for the one recipe [allRows] cannot
  /// speak for: a free-form line consuming a sub-recipe. It carries no
  /// quantity, so the calculator never expands it and no row names its
  /// unit, and the snapshot is where the word for it survives.
  ///
  /// The ingredient snapshot answers the same question for the other kind
  /// of free-form line. An ingredient measured in a count unit the run
  /// mentions nowhere else — gelatin in sheets, on a line the operator has
  /// to write themselves — has no calculated total to contribute one, and
  /// its default unit is the word the run recorded for it. Read off the
  /// run, not off the library: the run is what this screen shows, and a
  /// unit an ingredient acquired after the run was calculated was never
  /// part of it.
  ///
  /// The root recipe's own base yield is not read. A target yield must
  /// convert to it, and outside mass and volume converting means the same
  /// symbol, so it is either [ProductionRun.targetYield]'s unit or one of
  /// the seven fixed mass and volume units — covered twice over either way.
  Set<Unit> get _runUnits => {
    run.targetYield.unit,
    for (final recipe in run.dependencySnapshot.values) recipe.baseYield.unit,
    for (final ingredient in run.ingredientSnapshot.values)
      ingredient.defaultUnit,
    for (final row in allRows) ?row.total?.displayed.unit,
  };

  /// The units [row]'s override may be measured in: the fixed table, every
  /// unit [_runUnits] found, and whatever the draft currently holds.
  ///
  /// Not narrowed to what the calculated amount converts to. An override
  /// replaces the amount outright rather than converting it, so a baker
  /// weighing out a line the recipe wrote in millilitres is entitled to
  /// say so — the domain infers no density either way, and refusing the
  /// unit here would only push the operator into a conversion they would
  /// do in their head.
  ///
  /// The whole run rather than this line's own calculated unit alone,
  /// because a free-form line has no calculated unit and the fixed table
  /// holds no count unit at all: an operator recording two sheets of
  /// gelatin against such a line could otherwise only measure them in
  /// grams. What the run is written in is the vocabulary this screen has
  /// for that, and the run's ingredient snapshot is the third source of it:
  /// a free-form line's own ingredient contributes its default unit even
  /// when nothing in the run is measured in one. A unit named neither by a
  /// recipe, a calculated line, nor a referenced ingredient is still out of
  /// reach — naming one inline is a capability no screen has.
  ///
  /// The draft's own unit is added on top, whether or not either list
  /// holds it, because a dropdown whose value is missing from its items
  /// throws.
  ///
  /// Two units that print one symbol in different dimensions — a counted
  /// `portion` beside the built-in yield-only one — render as two
  /// identical rows. That is not new here, and the recipe editor's
  /// custom-unit dialog refuses the second one where it would be declared.
  List<Unit> unitChoicesFor(ResultRow row) =>
      <Unit>{...builtInUnits, ..._runUnits, draftFor(row).unit}.toList();

  /// This state with the named fields replaced.
  ///
  /// [error] is only ever read while [status] is
  /// [ProductionResultStatus.failure], so a stale one left behind by an
  /// earlier failure is unreachable and needs no clearing — the shape the
  /// production setup screen's `clearOutcome` exists for does not arise
  /// here, because nothing but a failure ever displays it.
  ProductionResultState copyWith({
    ProductionRun? run,
    ProductionResultStatus? status,
    Set<String>? expandedPaths,
    Map<OverrideKey, OverrideDraft>? overrideDrafts,
    Object? error,
  }) => ProductionResultState(
    run: run ?? this.run,
    status: status ?? this.status,
    expandedPaths: expandedPaths ?? this.expandedPaths,
    overrideDrafts: overrideDrafts ?? this.overrideDrafts,
    error: error ?? this.error,
  );
}
