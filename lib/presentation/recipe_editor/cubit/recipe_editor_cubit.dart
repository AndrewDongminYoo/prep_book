import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/units/built_in_units.dart';

part 'recipe_editor_state.dart';

/// Matches an identifier this cubit generated for a component, so a new one
/// can be numbered past every generated id already in the recipe.
final _generatedComponentId = RegExp(r'^component-(\d+)$');

/// A run of everything a slug drops: anything that is not a letter or a
/// digit, in any script, so a Korean recipe name slugs to its own words
/// rather than to nothing.
final _slugSeparators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// Drives the recipe editor screen.
///
/// Holds the four use cases the screen reads and writes through, never a
/// repository, for the reason the recipe library screen's cubit gives.
///
/// Creating a recipe and editing one are the same cubit with the same save
/// call, because `SaveRecipeRevision` computes the next revision number
/// itself: a new recipe simply has no stored revision to count from.
final class RecipeEditorCubit extends Cubit<RecipeEditorState> {
  /// Creates the cubit over the use cases it reads and writes through: the
  /// two reads the pickers need first, then the two writes. [recipe] is the
  /// revision being edited, or `null` to create one.
  RecipeEditorCubit(
    this._listLibrary,
    this._listIngredients,
    this._saveRecipeRevision,
    this._saveIngredient, {
    Recipe? recipe,
  }) : _componentSequence = _highestGeneratedIndex(recipe),
       super(_initialState(recipe));

  final ListLibrary _listLibrary;
  final ListIngredients _listIngredients;
  final SaveRecipeRevision _saveRecipeRevision;
  final SaveIngredient _saveIngredient;

  /// The highest number a generated component id has used so far.
  ///
  /// Seeded past every `component-N` the edited recipe already carries, so
  /// the next generated id cannot collide with a stored one — which `Recipe`
  /// would reject as a repeated component id, at save time, with nothing on
  /// screen to explain it.
  int _componentSequence;

  /// Reads the ingredient library and the recipe library the pickers offer.
  Future<void> load() async {
    emit(state.copyWith(status: RecipeEditorStatus.loading));
    final next = await _loadOutcome();
    if (isClosed) return;
    emit(next);
  }

  /// Records the typed recipe name.
  void nameChanged(String value) => emit(state.copyWith(name: value));

  /// Records the typed category.
  void categoryChanged(String value) => emit(state.copyWith(category: value));

  /// Records the typed base yield amount.
  void baseYieldAmountChanged(String value) =>
      emit(state.copyWith(baseYieldAmount: value));

  /// Records the chosen base yield unit.
  void baseYieldUnitChanged(Unit unit) =>
      emit(state.copyWith(baseYieldUnit: unit));

  /// Records the typed maximum batch yield.
  void maxBatchAmountChanged(String value) =>
      emit(state.copyWith(maxBatchAmount: value));

  /// Records the chosen maximum batch yield unit.
  void maxBatchUnitChanged(Unit unit) =>
      emit(state.copyWith(maxBatchUnit: unit));

  /// Records the typed preparation notes, one per line.
  void preparationNotesChanged(String value) =>
      emit(state.copyWith(preparationNotes: value));

  /// Offers [unit] in every unit picker on this screen.
  ///
  /// The domain builds count and yield-only units from arbitrary symbols, so
  /// this is how an operator names one the data does not already contain.
  void addCustomUnit(Unit unit) =>
      emit(state.copyWith(customUnits: [...state.customUnits, unit]));

  /// Appends a component consuming [ingredient].
  void addIngredientComponent(Ingredient ingredient) =>
      emit(_withComponent(state, _draftFor(ingredient)));

  /// Stores a new ingredient named [name] and puts it on a component.
  ///
  /// The editor is where ingredients come from: they are reusable library
  /// entries and the design document gives them no screen of their own.
  ///
  /// [forComponentId] decides which component ends up consuming it: `null`
  /// appends a new line, and an existing component's id retargets that line
  /// instead. Both paths are one call because the ingredient has to be
  /// written either way and only the last step differs.
  ///
  /// The form is closed to input for the duration, the same as during a
  /// save: the state this write ends by rewriting is the one it read when it
  /// started, so an edit made in between would be dropped without a trace —
  /// and a save pressed in that window would store a recipe missing the line
  /// this call is about to add.
  Future<void> createIngredient({
    required String name,
    required Unit defaultUnit,
    String? forComponentId,
  }) async {
    emit(state.copyWith(isWriting: true));
    final ingredient = Ingredient(
      id: _uniqueSlug(name, {
        for (final stored in state.ingredients) stored.id,
      }, fallback: 'ingredient'),
      name: name.trim(),
      defaultUnit: defaultUnit,
    );
    final next = await _ingredientOutcome(ingredient, forComponentId);
    if (isClosed) return;
    emit(next);
  }

  /// Appends a component consuming the output of [recipe].
  void addSubRecipeComponent(Recipe recipe) => emit(
    _withComponent(
      state,
      ComponentDraft(
        id: _nextComponentId(),
        target: SubRecipeRef(recipe.id),
        behavior: ScalingBehavior.proportional,
        // A line with nothing typed on it yet has no unit to prefer, and the
        // referenced recipe's own yield unit is the one choice that always
        // converts — see [subRecipeTargetChanged] for what the line's unit
        // actually has to satisfy.
        unit: recipe.baseYield.unit,
      ),
    ),
  );

  /// Records what the component [id] consumes.
  ///
  /// The amount, unit, behavior and note are deliberately kept: retargeting
  /// a line answers "this is the wrong ingredient", not "start this line
  /// again", and the operator can still edit every one of those fields.
  void componentTargetChanged(String id, ComponentTarget target) =>
      emit(_withTarget(state, id, target));

  /// Points the component [id] at the output of [recipe].
  ///
  /// A sub-recipe line's quantity is the target yield handed to the
  /// referenced recipe, so the unit has to be one that recipe's base yield
  /// converts to — a whole dimension, not the one unit.
  /// `ProductionCalculator.calculate` admits any convertible target yield
  /// and converts it into the recipe's own unit before scaling, so a line
  /// reading `500 g` under a recipe yielding kilograms runs exactly as
  /// written.
  ///
  /// The unit is therefore kept whenever the new target converts to it, and
  /// replaced only when it does not. Adopting the new yield unit
  /// unconditionally would leave the typed amount alone while changing what
  /// it measures, storing `500 g` as `500 kg` — a factor of a thousand, on
  /// an operator action that says nothing about the amount. Nothing
  /// downstream would catch it: `Unit.canConvertTo` accepts the pair, so
  /// [RecipeEditorState.subRecipeUnitIsIncompatible] stays false and the
  /// save goes through.
  void subRecipeTargetChanged(String id, Recipe recipe) {
    final yieldUnit = recipe.baseYield.unit;
    _updateComponent(
      id,
      (draft) => draft.copyWith(
        target: SubRecipeRef(recipe.id),
        unit: yieldUnit.canConvertTo(draft.unit) ? draft.unit : yieldUnit,
      ),
    );
  }

  /// Records the typed amount of the component [id].
  void componentAmountChanged(String id, String value) =>
      _updateComponent(id, (draft) => draft.copyWith(amount: value));

  /// Records the chosen unit of the component [id].
  void componentUnitChanged(String id, Unit unit) =>
      _updateComponent(id, (draft) => draft.copyWith(unit: unit));

  /// Records the chosen scaling behavior of the component [id].
  ///
  /// The typed amount is kept rather than cleared when the behavior becomes
  /// manual: a manual line ignores it, `_recipeFrom` drops it on save, and
  /// keeping it means changing the behavior back does not cost the operator
  /// what they had already written.
  void componentBehaviorChanged(String id, ScalingBehavior behavior) =>
      _updateComponent(id, (draft) => draft.copyWith(behavior: behavior));

  /// Records the typed rounding increment of the component [id].
  void componentRoundingChanged(String id, String value) =>
      _updateComponent(id, (draft) => draft.copyWith(roundingIncrement: value));

  /// Records the typed note of the component [id].
  void componentNoteChanged(String id, String value) =>
      _updateComponent(id, (draft) => draft.copyWith(note: value));

  /// Removes the component [id].
  void removeComponent(String id) => emit(
    state.copyWith(
      components: [
        for (final draft in state.components)
          if (draft.id != id) draft,
      ],
    ),
  );

  /// Moves the component at [oldIndex] to [newIndex].
  ///
  /// The draft list *is* the display order: `displayOrder` is assigned from
  /// each draft's position when the recipe is built, so moving a row here is
  /// the only thing that has to happen for the stored order to change.
  void reorderComponent({required int oldIndex, required int newIndex}) {
    final moved = [...state.components];
    final draft = moved.removeAt(oldIndex);
    moved.insert(newIndex, draft);
    emit(state.copyWith(components: moved));
  }

  /// Validates the form, then stores the recipe as its next revision.
  ///
  /// Field errors stop the save without reaching storage and turn on the
  /// messages the form shows. Everything past that point is the domain's
  /// judgement — a dependency cycle, a missing sub-recipe, a failed write —
  /// and arrives as `state.saveError` for the screen to render.
  Future<void> save() async {
    if (state.hasFieldErrors) {
      emit(state.copyWith(submitted: true));
      return;
    }
    emit(
      state.copyWith(
        status: RecipeEditorStatus.saving,
        isWriting: true,
        submitted: true,
        clearSaveError: true,
      ),
    );
    final next = await _saveOutcome();
    if (isClosed) return;
    emit(next);
  }

  /// The state the two library reads produce, whether they succeed or throw.
  Future<RecipeEditorState> _loadOutcome() async {
    try {
      final ingredients = await _listIngredients();
      final recipes = await _listLibrary();
      return state.copyWith(
        status: RecipeEditorStatus.ready,
        ingredients: ingredients,
        libraryRecipes: recipes,
      );
    } on Object catch (error, stackTrace) {
      // Reported as well as rendered, for the reason the library cubit
      // gives: the screen says the read failed, the observer logs why.
      addError(error, stackTrace);
      return state.copyWith(status: RecipeEditorStatus.loadFailure);
    }
  }

  /// The state writing [ingredient] produces, whether it succeeds or throws.
  Future<RecipeEditorState> _ingredientOutcome(
    Ingredient ingredient,
    String? forComponentId,
  ) async {
    try {
      await _saveIngredient(ingredient);
      final added = state.copyWith(
        isWriting: false,
        ingredients: [...state.ingredients, ingredient]
          ..sort((a, b) => a.name.compareTo(b.name)),
      );
      return forComponentId == null
          ? _withComponent(added, _draftFor(ingredient))
          : _withTarget(added, forComponentId, IngredientRef(ingredient.id));
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      return state.copyWith(isWriting: false, saveError: error);
    }
  }

  /// The state the save produces, whether it succeeds or throws.
  Future<RecipeEditorState> _saveOutcome() async {
    try {
      final saved = await _saveRecipeRevision(_recipeFrom(state));
      return state.copyWith(
        status: RecipeEditorStatus.saved,
        isWriting: false,
        savedRecipe: saved,
      );
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      return state.copyWith(
        status: RecipeEditorStatus.ready,
        isWriting: false,
        saveError: error,
      );
    }
  }

  /// Replaces the component [id] with what [change] returns.
  void _updateComponent(
    String id,
    ComponentDraft Function(ComponentDraft draft) change,
  ) => emit(
    state.copyWith(
      components: [
        for (final draft in state.components)
          if (draft.id == id) change(draft) else draft,
      ],
    ),
  );

  /// A new line consuming [ingredient], written in its default unit.
  ComponentDraft _draftFor(Ingredient ingredient) => ComponentDraft(
    id: _nextComponentId(),
    target: IngredientRef(ingredient.id),
    behavior: ScalingBehavior.proportional,
    unit: ingredient.defaultUnit,
  );

  /// [from] with [draft] appended to its component list.
  static RecipeEditorState _withComponent(
    RecipeEditorState from,
    ComponentDraft draft,
  ) => from.copyWith(components: [...from.components, draft]);

  /// [from] with the component [id] pointed at [target].
  ///
  /// Static and taking the state, rather than reusing [_updateComponent],
  /// because the ingredient-creation path has to apply it to the state its
  /// own write just produced rather than to `state`.
  static RecipeEditorState _withTarget(
    RecipeEditorState from,
    String id,
    ComponentTarget target,
  ) => from.copyWith(
    components: [
      for (final draft in from.components)
        if (draft.id == id) draft.copyWith(target: target) else draft,
    ],
  );

  /// An identifier no component of this recipe can already be using.
  String _nextComponentId() => 'component-${++_componentSequence}';

  /// The recipe the current form describes.
  ///
  /// Reachable only once `hasFieldErrors` is false, which is what makes the
  /// parses here safe. Both `revision` and `modifiedAt` are ignored by
  /// `SaveRecipeRevision`, which assigns the real values, so the constants
  /// below are placeholders rather than claims.
  static Recipe _recipeFrom(RecipeEditorState state) => Recipe(
    id: state.isNewRecipe
        ? _uniqueSlug(state.name, {
            for (final recipe in state.libraryRecipes) recipe.id,
          }, fallback: 'recipe')
        : state.recipeId,
    revision: 1,
    name: state.name.trim(),
    category: state.category.trim().isEmpty ? null : state.category.trim(),
    baseYield: _quantity(
      state.storedBaseYield,
      state.baseYieldAmount,
      state.baseYieldUnit,
    ),
    maxBatchYield: state.maxBatchIsBlank
        ? null
        : _quantity(
            state.storedMaxBatchYield,
            state.maxBatchAmount,
            state.maxBatchUnit,
          ),
    modifiedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    isArchived: state.isArchived,
    preparationNotes: [
      for (final line in state.preparationNotes.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ],
    components: [
      for (final (index, draft) in state.components.indexed)
        RecipeComponent(
          id: draft.id,
          target: draft.target,
          baseQuantity: draft.behavior == ScalingBehavior.manual
              ? null
              : _quantity(draft.storedQuantity, draft.amount, draft.unit),
          behavior: draft.behavior,
          displayOrder: index,
          rounding: _roundingOf(draft),
          note: draft.note.trim().isEmpty ? null : draft.note.trim(),
        ),
    ],
  );

  /// The rounding rule [draft] declares, or `null` when it declares none.
  ///
  /// A manual line never rounds: it produces no numeric result to round.
  static RoundingRule? _roundingOf(ComponentDraft draft) =>
      draft.behavior == ScalingBehavior.manual ||
          draft.roundingIncrement.trim().isEmpty
      ? null
      : RoundingRule.upToIncrement(_decimal(draft.roundingIncrement));

  /// [text] as a decimal. Only ever called on text field validation has
  /// already accepted.
  static Decimal _decimal(String text) => Decimal.parse(text.trim());

  /// The amount [text] in [unit], keeping [stored] when the form is still
  /// showing it unchanged.
  ///
  /// A quantity holds an exact rational, and not every rational has a
  /// finite decimal form — a third of a batch is the ordinary case. The
  /// form can only show a decimal, and the conversion approximates rather
  /// than refusing, so rebuilding every amount from what is on screen would
  /// silently rewrite a stored value to six decimal places on a save the
  /// operator made for some other field. A line whose text still reads
  /// exactly as the stored value renders, in the same unit, is therefore
  /// written back as that value.
  ///
  /// Nothing in the app writes such an amount today — every quantity that
  /// reaches storage is parsed from a decimal — so this guards the store
  /// against a future writer rather than fixing a value being lost now.
  static Quantity _quantity(Quantity? stored, String text, Unit unit) =>
      stored != null &&
          stored.unit == unit &&
          _amountText(stored) == text.trim()
      ? stored
      : Quantity.fromDecimal(_decimal(text), unit);

  /// A lowercase, dash-joined form of [source] that no id in [taken] uses.
  ///
  /// Identifiers are never displayed, so this only has to be stable and
  /// unique. Uniqueness is the part that matters: a second recipe named like
  /// an existing one would otherwise slug to the same id and be stored as
  /// that recipe's *next revision*, silently replacing it in the library
  /// under its own name.
  static String _uniqueSlug(
    String source,
    Set<String> taken, {
    required String fallback,
  }) {
    final parts = source.toLowerCase().split(_slugSeparators);
    final slug = parts.where((part) => part.isNotEmpty).join('-');
    final stem = slug.isEmpty ? fallback : slug;
    if (!taken.contains(stem)) return stem;
    var suffix = 2;
    while (taken.contains('$stem-$suffix')) {
      suffix++;
    }
    return '$stem-$suffix';
  }

  /// The form as [recipe] leaves it, or an empty one when it is `null`.
  static RecipeEditorState _initialState(Recipe? recipe) {
    if (recipe == null) {
      return RecipeEditorState(
        recipeId: '',
        isNewRecipe: true,
        baseYieldUnit: Unit.gram,
        maxBatchUnit: Unit.gram,
      );
    }
    final maxBatchYield = recipe.maxBatchYield;
    return RecipeEditorState(
      recipeId: recipe.id,
      isNewRecipe: false,
      name: recipe.name,
      category: recipe.category ?? '',
      baseYieldAmount: _amountText(recipe.baseYield),
      baseYieldUnit: recipe.baseYield.unit,
      storedBaseYield: recipe.baseYield,
      maxBatchAmount: maxBatchYield == null ? '' : _amountText(maxBatchYield),
      maxBatchUnit: maxBatchYield?.unit ?? recipe.baseYield.unit,
      storedMaxBatchYield: maxBatchYield,
      preparationNotes: recipe.preparationNotes.join('\n'),
      isArchived: recipe.isArchived,
      components: [
        for (final component in _byDisplayOrder(recipe.components))
          _draftOf(component),
      ],
    );
  }

  /// [component] as the operator sees it in the form.
  ///
  /// A manual component carries no quantity, so it contributes neither an
  /// amount nor a unit; the unit it starts at is the documented fallback on
  /// [ComponentDraft].
  static ComponentDraft _draftOf(RecipeComponent component) {
    final quantity = component.baseQuantity;
    return ComponentDraft(
      id: component.id,
      target: component.target,
      behavior: component.behavior,
      amount: quantity == null ? '' : _amountText(quantity),
      unit: quantity?.unit ?? Unit.gram,
      storedQuantity: quantity,
      roundingIncrement: component.rounding?.increment.toString() ?? '',
      note: component.note ?? '',
    );
  }

  /// [components] in display order, whatever order they arrived in.
  static List<RecipeComponent> _byDisplayOrder(
    List<RecipeComponent> components,
  ) =>
      [...components]..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

  /// [quantity]'s amount as the operator would type it.
  static String _amountText(Quantity quantity) =>
      quantity.toDecimal().toString();

  /// The largest number [recipe] already uses in a generated component id.
  static int _highestGeneratedIndex(Recipe? recipe) =>
      (recipe?.components ?? const <RecipeComponent>[]).fold(0, (highest, c) {
        final digits = _generatedComponentId.firstMatch(c.id)?.group(1) ?? '';
        final index = int.tryParse(digits) ?? 0;
        return index > highest ? index : highest;
      });
}
