part of 'recipe_editor_cubit.dart';

/// What the editor is currently doing.
enum RecipeEditorStatus {
  /// The ingredient library and the recipe library are being read.
  loading,

  /// The form is on screen and editable.
  ready,

  /// A save is in flight.
  saving,

  /// The save succeeded; [RecipeEditorState.savedRecipe] is what was
  /// stored, and the screen closes over it.
  saved,

  /// Reading the two libraries failed, so the pickers would be empty.
  loadFailure,
}

/// Every unit the domain declares as a fixed instance.
///
/// `lib/domain/units/unit.dart` owns this set; the domain exposes no list of
/// its own static fields, so the picker restates them and
/// `recipe_editor_cubit_test.dart` reads that file to fail if the two ever
/// diverge. Nothing else here is a copy: every other unit an operator can
/// pick is discovered from the data — see [RecipeEditorState.unitChoices].
final _builtInUnits = <Unit>[
  Unit.milligram,
  Unit.gram,
  Unit.kilogram,
  Unit.milliliter,
  Unit.liter,
  Unit.teaspoon,
  Unit.tablespoon,
  Unit.portion,
];

/// One component as the operator is typing it.
///
/// Amounts stay text rather than becoming a [Quantity], because half-typed
/// input has no domain value: `Quantity.parse('1.')` throws, and a form that
/// could only hold valid values could not hold what the operator is in the
/// middle of writing.
///
/// [unit] is never null, including on a `manual` draft, which has no amount
/// for it to measure. A manual line still carries one so that switching it
/// to a numeric behavior has a unit to start from; the control for it is
/// hidden while the behavior is manual. A manual component read back from a
/// stored recipe has no unit to recover — the domain stores none — so it
/// starts at [Unit.gram].
@immutable
final class ComponentDraft {
  /// Creates a draft.
  const ComponentDraft({
    required this.id,
    required this.target,
    required this.behavior,
    required this.unit,
    this.amount = '',
    this.roundingIncrement = '',
    this.note = '',
    this.storedQuantity,
  });

  /// Identifier, unique within the recipe being edited.
  final String id;

  /// The ingredient or recipe this line consumes.
  final ComponentTarget target;

  /// How the amount responds to a production run.
  final ScalingBehavior behavior;

  /// The typed amount. Ignored while [behavior] is manual.
  final String amount;

  /// The unit the amount is measured in.
  final Unit unit;

  /// The typed rounding increment. Empty means no rounding.
  final String roundingIncrement;

  /// The typed operator note. Empty means no note.
  final String note;

  /// The quantity this line was read from, or `null` on a line the operator
  /// added during this edit.
  ///
  /// Carried so the save can write back the exact stored value rather than
  /// what [amount] renders it as — see `RecipeEditorCubit`'s `_quantity`,
  /// which owns that rule. Never replaced by [copyWith]: the draft it
  /// belongs to is the same line however many fields around it change, and
  /// whether the stored value is still the one on screen is decided by
  /// comparing [amount] against it, not by tracking edits.
  final Quantity? storedQuantity;

  /// This draft with the named fields replaced.
  ComponentDraft copyWith({
    ComponentTarget? target,
    ScalingBehavior? behavior,
    String? amount,
    Unit? unit,
    String? roundingIncrement,
    String? note,
  }) => ComponentDraft(
    id: id,
    target: target ?? this.target,
    behavior: behavior ?? this.behavior,
    amount: amount ?? this.amount,
    unit: unit ?? this.unit,
    roundingIncrement: roundingIncrement ?? this.roundingIncrement,
    note: note ?? this.note,
    storedQuantity: storedQuantity,
  );
}

/// View state for the recipe editor.
///
/// Equality is left at identity, matching the recipe library screen's state
/// and the domain layer's rule that only the types something compares by
/// value define `==`.
@immutable
final class RecipeEditorState {
  /// Creates a state.
  const RecipeEditorState({
    required this.recipeId,
    required this.isNewRecipe,
    required this.baseYieldUnit,
    required this.maxBatchUnit,
    this.status = RecipeEditorStatus.loading,
    this.name = '',
    this.category = '',
    this.baseYieldAmount = '',
    this.maxBatchAmount = '',
    this.preparationNotes = '',
    this.isArchived = false,
    this.components = const [],
    this.ingredients = const [],
    this.libraryRecipes = const [],
    this.customUnits = const [],
    this.submitted = false,
    this.isWriting = false,
    this.saveError,
    this.savedRecipe,
    this.storedBaseYield,
    this.storedMaxBatchYield,
  });

  /// What the editor is doing.
  final RecipeEditorStatus status;

  /// The identifier the edit will be stored under, empty while the recipe
  /// is new: a new recipe's id is derived from its name when it is saved,
  /// so that renaming a draft before the first save still names its id.
  final String recipeId;

  /// Whether this editor is creating a recipe rather than editing one.
  final bool isNewRecipe;

  /// The typed name.
  final String name;

  /// The typed category. Empty means none.
  final String category;

  /// The typed base yield amount.
  final String baseYieldAmount;

  /// The unit the base yield is measured in.
  final Unit baseYieldUnit;

  /// The typed maximum batch yield. Empty means the recipe has no maximum.
  final String maxBatchAmount;

  /// The unit the maximum batch yield is measured in.
  final Unit maxBatchUnit;

  /// The typed preparation notes, one per line.
  final String preparationNotes;

  /// Whether the recipe being edited is archived.
  ///
  /// The editor shows no control for this and carries it through unchanged;
  /// archiving is the library screen's job, and a save that dropped the flag
  /// would silently restore an archived recipe.
  final bool isArchived;

  /// The component rows, in display order.
  final List<ComponentDraft> components;

  /// The ingredient library, ordered by name.
  final List<Ingredient> ingredients;

  /// Every recipe's latest revision, for the sub-recipe picker.
  final List<Recipe> libraryRecipes;

  /// Units the operator declared during this edit.
  final List<Unit> customUnits;

  /// Whether a save has been attempted, which is when field errors start
  /// being shown. A form that reports what is missing before anything has
  /// been typed reports everything at once.
  final bool submitted;

  /// Whether a write this screen started is still in flight.
  ///
  /// Covers both of them — storing the recipe and storing an ingredient the
  /// operator named — because both read the whole form at the moment they
  /// start, so an edit made after that is an edit the write cannot carry.
  /// The recipe save also moves [status]; creating an ingredient does not,
  /// because it changes neither what is on screen nor what the screen would
  /// do next.
  final bool isWriting;

  /// What the last save attempt threw, or `null` when none did.
  final Object? saveError;

  /// The stored recipe, once [status] is [RecipeEditorStatus.saved].
  final Recipe? savedRecipe;

  /// The base yield this form was read from, `null` on a new recipe.
  ///
  /// The same reason [ComponentDraft.storedQuantity] exists, for the two
  /// yields: an amount the operator never retyped is written back as the
  /// value that was stored, not as the text it is displayed as.
  final Quantity? storedBaseYield;

  /// The maximum batch yield this form was read from, `null` when the
  /// recipe is new or declared none.
  final Quantity? storedMaxBatchYield;

  /// Whether the operator may change anything on the form right now.
  ///
  /// False while either write runs, and false once the save succeeded, when
  /// the screen is on its way out. Everything the operator can touch is
  /// gated on this — the Save action and the form itself — so an edit is
  /// never accepted into a state no write will read.
  bool get isEditable => status == RecipeEditorStatus.ready && !isWriting;

  /// Whether the recipe name is missing.
  bool get nameIsMissing => name.trim().isEmpty;

  /// Whether the base yield is absent or not a positive number.
  bool get baseYieldIsInvalid => _positive(baseYieldAmount) == null;

  /// Whether the recipe declares no maximum batch yield.
  bool get maxBatchIsBlank => maxBatchAmount.trim().isEmpty;

  /// Whether a declared maximum batch yield is not a positive number.
  bool get maxBatchIsInvalid =>
      !maxBatchIsBlank && _positive(maxBatchAmount) == null;

  /// Whether a declared maximum batch yield is measured in a unit the base
  /// yield cannot convert to, which `Recipe` rejects.
  ///
  /// Checked here as well as there because it is a field error the operator
  /// fixes by changing a dropdown, not a failure that needs the library
  /// read.
  bool get maxBatchUnitIsIncompatible =>
      !maxBatchIsBlank &&
      !maxBatchIsInvalid &&
      !baseYieldUnit.canConvertTo(maxBatchUnit);

  /// Whether [draft] needs an amount and does not have a usable one.
  bool amountIsInvalid(ComponentDraft draft) =>
      draft.behavior != ScalingBehavior.manual &&
      _positive(draft.amount) == null;

  /// Whether [draft] consumes a sub-recipe in a unit that recipe's own base
  /// yield cannot convert to.
  ///
  /// A sub-recipe line's quantity is the target yield handed to the
  /// referenced recipe, so an incompatible unit is not a formatting problem:
  /// every production run of the saved recipe throws
  /// `IncompatibleYieldUnitError` on it, and nothing between here and there
  /// rejects it — `SaveRecipeRevision` checks the dependency graph, not the
  /// units. [unitChoicesFor] keeps the picker from producing one; this is
  /// what catches a line that reached the state some other way, such as a
  /// stored manual line switched to a scaling behavior.
  ///
  /// A reference the library does not hold is left alone: it is a missing
  /// dependency, which `SaveRecipeRevision` reports by name.
  bool subRecipeUnitIsIncompatible(ComponentDraft draft) {
    if (draft.behavior == ScalingBehavior.manual) return false;
    final yieldUnit = _subRecipeYieldUnit(draft);
    return yieldUnit != null && !yieldUnit.canConvertTo(draft.unit);
  }

  /// The stored recipes that consume this one in a unit the base yield on
  /// screen cannot convert to.
  ///
  /// The mirror image of [subRecipeUnitIsIncompatible], which only guards
  /// the lines this recipe owns. A parent's line hands its total to this
  /// recipe as a target yield, so `ProductionCalculator.calculate` throws
  /// `IncompatibleYieldUnitError` — the same error, out of the same check —
  /// whenever this recipe's base yield unit stops converting to the unit a
  /// parent measures it in. Nothing between here and there catches it:
  /// `SaveRecipeRevision` checks the dependency graph and not the units, and
  /// the closure a run resolves reads every dependency at its latest
  /// revision, so the edit reaches each parent the moment it is stored.
  /// Converting the parent's amount instead is not on offer — CLAUDE.md's
  /// "No inferred conversions" ruling — so the save is what has to stop.
  ///
  /// A parent's manual line is left out: it carries no quantity, so it is
  /// never expanded and never throws.
  ///
  /// This fires on a breakage that was already stored, not only on one this
  /// edit introduces, the same way the outbound guard does; the operator
  /// clears it by opening the parent, where that guard refuses the offending
  /// line until its unit is fixed. A stored revision that consumes itself is
  /// left in scope rather than filtered out, because the domain rejects that
  /// as a cycle before it can be written — no test pins that choice.
  List<Recipe> get dependentsBlockedByBaseYieldUnit => [
    for (final recipe in libraryRecipes)
      if (recipe.components.any(_blockedByBaseYieldUnit)) recipe,
  ];

  /// Whether [component] consumes this recipe in a unit the base yield on
  /// screen cannot convert to.
  ///
  /// Written in the argument order `ProductionCalculator.calculate` uses, so
  /// the two cannot drift apart into agreeing on the wrong direction.
  bool _blockedByBaseYieldUnit(RecipeComponent component) {
    final quantity = component.baseQuantity;
    return quantity != null &&
        component.target == SubRecipeRef(recipeId) &&
        !baseYieldUnit.canConvertTo(quantity.unit);
  }

  /// Whether [draft] declares a rounding increment that is not positive.
  ///
  /// A manual line's increment is never read, so it is never rejected.
  bool roundingIsInvalid(ComponentDraft draft) =>
      draft.behavior != ScalingBehavior.manual &&
      draft.roundingIncrement.trim().isNotEmpty &&
      _positive(draft.roundingIncrement) == null;

  /// Whether any field the operator can fix in place is wrong.
  ///
  /// The errors this covers are the ones a form can decide on its own. The
  /// ones it cannot — a dependency cycle, a missing sub-recipe — belong to
  /// `SaveRecipeRevision` and arrive as [saveError].
  bool get hasFieldErrors =>
      nameIsMissing ||
      baseYieldIsInvalid ||
      maxBatchIsInvalid ||
      maxBatchUnitIsIncompatible ||
      dependentsBlockedByBaseYieldUnit.isNotEmpty ||
      components.any(
        (draft) =>
            amountIsInvalid(draft) ||
            roundingIsInvalid(draft) ||
            subRecipeUnitIsIncompatible(draft),
      );

  /// Every unit a picker on this screen offers.
  ///
  /// `Unit.count` and `Unit.namedYield` build a unit from any string, so a
  /// fixed list cannot express what the library already holds — a recipe
  /// yielding trays, an ingredient counted in pieces. The choices are
  /// therefore the fixed units plus every unit reachable from the data on
  /// screen, plus whatever the operator declared through
  /// `RecipeEditorCubit.addCustomUnit`. Insertion order is preserved and
  /// `Unit` compares by symbol and dimension, so a set literal deduplicates
  /// without reordering.
  List<Unit> get unitChoices => <Unit>{
    ..._builtInUnits,
    baseYieldUnit,
    maxBatchUnit,
    for (final draft in components) draft.unit,
    for (final ingredient in ingredients) ingredient.defaultUnit,
    for (final recipe in libraryRecipes) recipe.baseYield.unit,
    ...customUnits,
  }.toList();

  /// The units the component [draft] may be measured in.
  ///
  /// An ingredient line may use any of them. A sub-recipe line may not: its
  /// quantity is the target yield handed to the referenced recipe, so the
  /// choices narrow to what that recipe's base yield converts to — which,
  /// outside mass and volume, is the yield unit itself and nothing else.
  ///
  /// [draft]'s own unit is always among the choices, whether or not it
  /// belongs there. A dropdown whose value is missing from its items throws,
  /// and the value can be wrong: a stored line saved before this narrowing
  /// existed, or a manual line adopting the fallback unit. It is offered so
  /// the operator can see and replace it, and
  /// [subRecipeUnitIsIncompatible] is what refuses the save until they do.
  List<Unit> unitChoicesFor(ComponentDraft draft) {
    final yieldUnit = _subRecipeYieldUnit(draft);
    if (yieldUnit == null) return unitChoices;
    return <Unit>{
      for (final choice in unitChoices)
        if (yieldUnit.canConvertTo(choice)) choice,
      draft.unit,
    }.toList();
  }

  /// The base yield unit of the recipe [draft] consumes, or `null` when it
  /// consumes an ingredient or names a recipe the library does not hold.
  Unit? _subRecipeYieldUnit(ComponentDraft draft) {
    if (draft.target case SubRecipeRef(:final recipeId)) {
      for (final recipe in libraryRecipes) {
        if (recipe.id == recipeId) return recipe.baseYield.unit;
      }
    }
    return null;
  }

  /// The recipes the sub-recipe picker offers.
  ///
  /// Archived recipes are left out: an archived dependency blocks a
  /// production run, so offering one here builds a recipe that cannot be
  /// run. The recipe being edited is deliberately *not* filtered out — that
  /// would be a partial cycle check in the screen, and the domain rejects
  /// the whole class, naming the path it found.
  List<Recipe> get subRecipeChoices => [
    for (final recipe in libraryRecipes)
      if (!recipe.isArchived) recipe,
  ];

  /// [text] as a positive decimal, or `null` when it is neither.
  static Decimal? _positive(String text) {
    final value = Decimal.tryParse(text.trim());
    return value != null && value > Decimal.zero ? value : null;
  }

  /// This state with the named fields replaced.
  ///
  /// [saveError] is the one field that has to be cleared as well as set — a
  /// new attempt must not run underneath the last one's message — so it has
  /// [clearSaveError] rather than being cleared by passing `null`, which
  /// `??` cannot tell from "leave it alone".
  RecipeEditorState copyWith({
    RecipeEditorStatus? status,
    String? recipeId,
    String? name,
    String? category,
    String? baseYieldAmount,
    Unit? baseYieldUnit,
    String? maxBatchAmount,
    Unit? maxBatchUnit,
    String? preparationNotes,
    List<ComponentDraft>? components,
    List<Ingredient>? ingredients,
    List<Recipe>? libraryRecipes,
    List<Unit>? customUnits,
    bool? submitted,
    bool? isWriting,
    Object? saveError,
    Recipe? savedRecipe,
    bool clearSaveError = false,
  }) => RecipeEditorState(
    status: status ?? this.status,
    recipeId: recipeId ?? this.recipeId,
    isNewRecipe: isNewRecipe,
    name: name ?? this.name,
    category: category ?? this.category,
    baseYieldAmount: baseYieldAmount ?? this.baseYieldAmount,
    baseYieldUnit: baseYieldUnit ?? this.baseYieldUnit,
    maxBatchAmount: maxBatchAmount ?? this.maxBatchAmount,
    maxBatchUnit: maxBatchUnit ?? this.maxBatchUnit,
    preparationNotes: preparationNotes ?? this.preparationNotes,
    isArchived: isArchived,
    components: components ?? this.components,
    ingredients: ingredients ?? this.ingredients,
    libraryRecipes: libraryRecipes ?? this.libraryRecipes,
    customUnits: customUnits ?? this.customUnits,
    submitted: submitted ?? this.submitted,
    isWriting: isWriting ?? this.isWriting,
    saveError: clearSaveError ? null : (saveError ?? this.saveError),
    savedRecipe: savedRecipe ?? this.savedRecipe,
    // Read once, when the form is filled from a stored revision, and never
    // replaced afterwards — the same as [isNewRecipe] and [isArchived].
    storedBaseYield: storedBaseYield,
    storedMaxBatchYield: storedMaxBatchYield,
  );
}
