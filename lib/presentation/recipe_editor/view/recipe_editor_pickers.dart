part of 'recipe_editor_page.dart';

/// What the ingredient picker came back with.
///
/// A sealed pair rather than a nullable ingredient, because "the operator
/// picked this stored one" and "the operator wants a new one under this
/// name" are different instructions and only one of them writes.
sealed class _IngredientChoice {
  const _IngredientChoice();
}

/// The operator picked an ingredient the library already holds.
final class _ExistingIngredient extends _IngredientChoice {
  const _ExistingIngredient(this.ingredient);

  final Ingredient ingredient;
}

/// The operator named an ingredient the library does not hold yet.
final class _NewIngredient extends _IngredientChoice {
  const _NewIngredient(this.name, this.unit);

  final String name;
  final Unit unit;
}

/// Adds an ingredient line, creating the ingredient when the typed name
/// matches nothing stored.
///
/// The editor is where ingredients come from: the design document gives
/// them no screen of their own, and a component cannot name one that does
/// not exist.
Future<void> _addIngredient(BuildContext context) async {
  final cubit = context.read<RecipeEditorCubit>();
  final state = cubit.state;
  final choice = await showDialog<_IngredientChoice>(
    context: context,
    builder: (_) => _IngredientPicker(
      ingredients: state.ingredients,
      units: state.unitChoices,
    ),
  );
  switch (choice) {
    case null:
      return;
    case _ExistingIngredient(:final ingredient):
      cubit.addIngredientComponent(ingredient);
    case _NewIngredient(:final name, :final unit):
      await cubit.createIngredient(name: name, defaultUnit: unit);
  }
}

/// Points an existing line at a different ingredient or recipe.
///
/// The picker offered is the one [draft]'s current target came from, so a
/// sub-recipe line cannot silently become an ingredient line: the two carry
/// different units and different meanings, and swapping kinds is a new line
/// rather than a correction to this one.
Future<void> _changeTarget(BuildContext context, ComponentDraft draft) async {
  switch (draft.target) {
    case IngredientRef():
      await _retargetIngredient(context, draft.id);
    case SubRecipeRef():
      await _retargetSubRecipe(context, draft.id);
  }
}

/// Points the line [componentId] at another ingredient, creating one when
/// the typed name matches nothing stored.
Future<void> _retargetIngredient(
  BuildContext context,
  String componentId,
) async {
  final cubit = context.read<RecipeEditorCubit>();
  final state = cubit.state;
  final choice = await showDialog<_IngredientChoice>(
    context: context,
    builder: (_) => _IngredientPicker(
      ingredients: state.ingredients,
      units: state.unitChoices,
    ),
  );
  switch (choice) {
    case null:
      return;
    case _ExistingIngredient(:final ingredient):
      cubit.componentTargetChanged(componentId, IngredientRef(ingredient.id));
    case _NewIngredient(:final name, :final unit):
      await cubit.createIngredient(
        name: name,
        defaultUnit: unit,
        forComponentId: componentId,
      );
  }
}

/// Points the line [componentId] at another recipe's output.
Future<void> _retargetSubRecipe(
  BuildContext context,
  String componentId,
) async {
  final cubit = context.read<RecipeEditorCubit>();
  final chosen = await showDialog<Recipe>(
    context: context,
    builder: (_) => _SubRecipePicker(recipes: cubit.state.subRecipeChoices),
  );
  // One call rather than a target change and a unit change, because what
  // the line's unit becomes depends on both: `subRecipeTargetChanged` owns
  // that rule and states why.
  if (chosen != null) cubit.subRecipeTargetChanged(componentId, chosen);
}

/// Adds a line consuming another recipe's output.
Future<void> _addSubRecipe(BuildContext context) async {
  final cubit = context.read<RecipeEditorCubit>();
  final chosen = await showDialog<Recipe>(
    context: context,
    builder: (_) => _SubRecipePicker(recipes: cubit.state.subRecipeChoices),
  );
  if (chosen != null) cubit.addSubRecipeComponent(chosen);
}

/// Declares a unit the pickers do not offer yet.
Future<void> _declareUnit(BuildContext context) async {
  final cubit = context.read<RecipeEditorCubit>();
  final unit = await showDialog<Unit>(
    context: context,
    builder: (_) => const _CustomUnitDialog(),
  );
  if (unit != null) cubit.addCustomUnit(unit);
}

/// Picks an ingredient by name, or names a new one.
///
/// The list filters as the operator types and stays visible while they do,
/// which is the near-duplicate guard: an operator about to create "Butter"
/// while "Unsalted butter" is already stored sees it before deciding, and
/// creating is refused outright while an exactly-named ingredient exists.
class _IngredientPicker extends StatefulWidget {
  const _IngredientPicker({required this.ingredients, required this.units});

  final List<Ingredient> ingredients;
  final List<Unit> units;

  @override
  State<_IngredientPicker> createState() => _IngredientPickerState();
}

class _IngredientPickerState extends State<_IngredientPicker> {
  String _typed = '';
  Unit _unit = Unit.gram;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final needle = _typed.trim().toLowerCase();
    final matches = [
      for (final ingredient in widget.ingredients)
        if (ingredient.name.toLowerCase().contains(needle)) ingredient,
    ];
    final exact = widget.ingredients.any(
      (ingredient) => ingredient.name.toLowerCase() == needle,
    );
    return AlertDialog(
      // The dialog card shrinks by the software keyboard's inset, so a
      // fixed-height content column paints its lower controls outside the
      // card without ever throwing: `Align` centres an oversized child
      // rather than clipping it. Scrolling the content is what keeps the
      // unit dropdown below reachable on a short viewport — a landscape
      // phone with the keyboard up, which this dialog always is because
      // its field takes focus on open.
      scrollable: true,
      title: Text(l10n.recipeEditorIngredientPickerTitle),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n.recipeEditorIngredientNameLabel,
                border: const OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() => _typed = value),
            ),
            if (needle.isNotEmpty && matches.isNotEmpty && !exact)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  l10n.recipeEditorIngredientSimilar,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            // Plain children rather than a nested scroll view: `scrollable`
            // hands the content unbounded height, which a `Flexible` cannot
            // take. One scroll view over the whole dialog also means the
            // matches and the unit control scroll together, instead of a
            // list that scrolls inside a card that cannot.
            for (final ingredient in matches)
              ListTile(
                title: Text(ingredient.name),
                subtitle: Text(ingredient.defaultUnit.symbol),
                onTap: () =>
                    Navigator.of(context).pop(_ExistingIngredient(ingredient)),
              ),
            // Only read when a new ingredient is created: an existing one
            // keeps the default unit it was stored with.
            DropdownButtonFormField<Unit>(
              initialValue: _unit,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.recipeEditorUnitLabel,
                border: const OutlineInputBorder(),
              ),
              items: [
                for (final choice in widget.units)
                  DropdownMenuItem(value: choice, child: Text(choice.symbol)),
              ],
              onChanged: (chosen) {
                if (chosen != null) setState(() => _unit = chosen);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.recipeEditorCancel),
        ),
        FilledButton(
          // Refused on an exact name match: a second "Flour" would be a
          // separate library entry the operator cannot tell from the first.
          onPressed: needle.isEmpty || exact
              ? null
              : () => Navigator.of(
                  context,
                ).pop(_NewIngredient(_typed.trim(), _unit)),
          child: Text(l10n.recipeEditorIngredientCreate),
        ),
      ],
    );
  }
}

/// Picks the recipe a sub-recipe line consumes.
class _SubRecipePicker extends StatelessWidget {
  const _SubRecipePicker({required this.recipes});

  final List<Recipe> recipes;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SimpleDialog(
      title: Text(l10n.recipeEditorSubRecipePickerTitle),
      children: [
        if (recipes.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Text(l10n.recipeEditorSubRecipeNone),
          ),
        for (final recipe in recipes)
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop(recipe),
            child: Text(
              '${recipe.name} · '
              '${recipe.baseYield.toDecimal()} ${recipe.baseYield.unit.symbol}',
            ),
          ),
      ],
    );
  }
}

/// Names a count or yield-only unit the fixed table does not contain.
///
/// `Unit.count` and `Unit.namedYield` build a unit from any symbol, so a
/// picker limited to the fixed table could not express a recipe measured in
/// trays or an ingredient counted in sheets. Which of the two factories to
/// call is the operator's choice, because it is not recoverable from the
/// symbol: neither kind ever converts into anything else, and the pair
/// differs only in what it measures.
class _CustomUnitDialog extends StatefulWidget {
  const _CustomUnitDialog();

  @override
  State<_CustomUnitDialog> createState() => _CustomUnitDialogState();
}

class _CustomUnitDialogState extends State<_CustomUnitDialog> {
  String _symbol = '';
  bool _isCounted = true;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final symbol = _symbol.trim();
    return AlertDialog(
      // Same reason as the ingredient picker above: this dialog also takes
      // focus on open, so the keyboard is up and the card is short, and the
      // count-versus-yield choice below the field is not recoverable from
      // the symbol afterwards.
      scrollable: true,
      title: Text(l10n.recipeEditorCustomUnitTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.recipeEditorCustomUnitSymbol,
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => setState(() => _symbol = value),
          ),
          const SizedBox(height: 12),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text(l10n.recipeEditorCustomUnitCount),
              ),
              ButtonSegment(
                value: false,
                label: Text(l10n.recipeEditorCustomUnitYield),
              ),
            ],
            selected: {_isCounted},
            onSelectionChanged: (selection) =>
                setState(() => _isCounted = selection.first),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.recipeEditorCancel),
        ),
        FilledButton(
          onPressed: symbol.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                  _isCounted ? Unit.count(symbol) : Unit.namedYield(symbol),
                ),
          child: Text(l10n.recipeEditorCustomUnitAdd),
        ),
      ],
    );
  }
}
