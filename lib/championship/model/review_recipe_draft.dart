import 'package:prep_book/championship/import/unit_alias_resolver.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/domain/domain.dart';

final class ReviewField<T> {
  ReviewField({
    required this.sourceValue,
    required this.value,
    required this.evidence,
    required this.confidence,
    required List<String> sourceIssues,
    required List<String> localIssues,
    this.isConfirmed = false,
  }) : sourceIssues = List.unmodifiable(sourceIssues),
       localIssues = List.unmodifiable(localIssues);

  final T? sourceValue;
  final T? value;
  final String evidence;
  final ExtractionConfidence confidence;
  final List<String> sourceIssues;
  final List<String> localIssues;
  final bool isConfirmed;

  bool get isEdited => value != sourceValue;

  List<String> get activeIssues =>
      List.unmodifiable([if (!isEdited) ...sourceIssues, ...localIssues]);

  bool get canConfirm => value != null && activeIssues.isEmpty;

  ReviewField<T> edit(T? nextValue, {List<String> localIssues = const []}) =>
      ReviewField(
        sourceValue: sourceValue,
        value: nextValue,
        evidence: evidence,
        confidence: confidence,
        sourceIssues: sourceIssues,
        localIssues: localIssues,
      );

  ReviewField<T> confirm() {
    if (!canConfirm) {
      throw StateError('The review field is not ready for confirmation.');
    }
    return ReviewField(
      sourceValue: sourceValue,
      value: value,
      evidence: evidence,
      confidence: confidence,
      sourceIssues: sourceIssues,
      localIssues: localIssues,
      isConfirmed: true,
    );
  }

  ReviewField<T> confirmIfUnambiguous() => canConfirm ? confirm() : this;
}

final class ReviewYieldDraft {
  const ReviewYieldDraft({required this.amount, required this.unit});

  final ReviewField<String> amount;
  final ReviewField<String> unit;

  ReviewYieldDraft copyWith({
    ReviewField<String>? amount,
    ReviewField<String>? unit,
  }) =>
      ReviewYieldDraft(amount: amount ?? this.amount, unit: unit ?? this.unit);

  ReviewYieldDraft confirmAllUnambiguous() => ReviewYieldDraft(
    amount: amount.confirmIfUnambiguous(),
    unit: unit.confirmIfUnambiguous(),
  );
}

final class ReviewRecipeDetails {
  ReviewRecipeDetails({
    required this.name,
    required this.baseYield,
    required this.maxBatchYield,
    required this.maxBatchYieldProposal,
    required this.isMaxBatchYieldAbsentConfirmed,
    required List<ReviewField<String>> preparationNotes,
  }) : preparationNotes = List.unmodifiable(preparationNotes);

  final ReviewField<String> name;
  final ReviewYieldDraft baseYield;
  final ReviewYieldDraft? maxBatchYield;
  final ReviewYieldDraft? maxBatchYieldProposal;
  final bool isMaxBatchYieldAbsentConfirmed;
  final List<ReviewField<String>> preparationNotes;

  ReviewRecipeDetails copyWith({
    ReviewField<String>? name,
    ReviewYieldDraft? baseYield,
    ReviewYieldDraft? maxBatchYield,
    bool? isMaxBatchYieldAbsentConfirmed,
    List<ReviewField<String>>? preparationNotes,
  }) => ReviewRecipeDetails(
    name: name ?? this.name,
    baseYield: baseYield ?? this.baseYield,
    maxBatchYield: maxBatchYield ?? this.maxBatchYield,
    maxBatchYieldProposal: maxBatchYieldProposal,
    isMaxBatchYieldAbsentConfirmed:
        isMaxBatchYieldAbsentConfirmed ?? this.isMaxBatchYieldAbsentConfirmed,
    preparationNotes: preparationNotes ?? this.preparationNotes,
  );

  ReviewRecipeDetails removeMaxBatchYield() => ReviewRecipeDetails(
    name: name,
    baseYield: baseYield,
    maxBatchYield: null,
    maxBatchYieldProposal: maxBatchYieldProposal,
    isMaxBatchYieldAbsentConfirmed: false,
    preparationNotes: preparationNotes,
  );

  ReviewRecipeDetails confirmMaxBatchYieldAbsent() {
    if (maxBatchYield != null) {
      throw StateError('The maximum batch yield is still present.');
    }
    return ReviewRecipeDetails(
      name: name,
      baseYield: baseYield,
      maxBatchYield: null,
      maxBatchYieldProposal: maxBatchYieldProposal,
      isMaxBatchYieldAbsentConfirmed: true,
      preparationNotes: preparationNotes,
    );
  }

  ReviewRecipeDetails confirmAllUnambiguous() => ReviewRecipeDetails(
    name: name.confirmIfUnambiguous(),
    baseYield: baseYield.confirmAllUnambiguous(),
    maxBatchYield: maxBatchYield?.confirmAllUnambiguous(),
    maxBatchYieldProposal: maxBatchYieldProposal,
    isMaxBatchYieldAbsentConfirmed: isMaxBatchYieldAbsentConfirmed,
    preparationNotes: [
      for (final note in preparationNotes) note.confirmIfUnambiguous(),
    ],
  );
}

final class ReviewRecipeComponent {
  const ReviewRecipeComponent({
    required this.name,
    required this.amount,
    required this.unit,
    required this.behavior,
    required this.note,
  });

  final ReviewField<String> name;
  final ReviewField<String> amount;
  final ReviewField<String> unit;
  final ReviewField<DraftScalingBehavior> behavior;
  final ReviewField<String>? note;

  ReviewRecipeComponent copyWith({
    ReviewField<String>? name,
    ReviewField<String>? amount,
    ReviewField<String>? unit,
    ReviewField<DraftScalingBehavior>? behavior,
    ReviewField<String>? note,
  }) => ReviewRecipeComponent(
    name: name ?? this.name,
    amount: amount ?? this.amount,
    unit: unit ?? this.unit,
    behavior: behavior ?? this.behavior,
    note: note ?? this.note,
  );

  ReviewRecipeComponent confirmAllUnambiguous() => ReviewRecipeComponent(
    name: name.confirmIfUnambiguous(),
    amount: amount.confirmIfUnambiguous(),
    unit: unit.confirmIfUnambiguous(),
    behavior: behavior.value == DraftScalingBehavior.manual
        ? behavior
        : behavior.confirmIfUnambiguous(),
    note: note?.confirmIfUnambiguous(),
  );
}

final class ReviewRecipeDraft {
  ReviewRecipeDraft._({
    required this.sourceKind,
    required this.recipe,
    required List<ReviewRecipeComponent> components,
    required this.units,
  }) : components = List.unmodifiable(components);

  factory ReviewRecipeDraft.fromExtracted(
    ExtractedRecipeDraft draft, {
    UnitAliasResolver units = const UnitAliasResolver(),
  }) {
    final maxBatchYield = draft.recipe.maxBatchYield == null
        ? null
        : _reviewMaxYield(
            draft.recipe.maxBatchYield!,
            draft.recipe.baseYield,
            units,
          );
    return ReviewRecipeDraft._(
      sourceKind: draft.sourceKind,
      recipe: ReviewRecipeDetails(
        name: _reviewField(draft.recipe.name, _requiredTextIssues),
        baseYield: _reviewYield(draft.recipe.baseYield, units),
        maxBatchYield: maxBatchYield,
        maxBatchYieldProposal: maxBatchYield,
        isMaxBatchYieldAbsentConfirmed: false,
        preparationNotes: [
          for (final note in draft.recipe.preparationNotes)
            _reviewField(note, _requiredTextIssues),
        ],
      ),
      components: [
        for (final component in draft.components)
          _reviewComponent(component, units),
      ],
      units: units,
    );
  }

  final RecipeImportSourceKind sourceKind;
  final ReviewRecipeDetails recipe;
  final List<ReviewRecipeComponent> components;
  final UnitAliasResolver units;

  List<ReviewField<Object?>> get allFields => List.unmodifiable([
    _asObjectField(recipe.name),
    _asObjectField(recipe.baseYield.amount),
    _asObjectField(recipe.baseYield.unit),
    if (recipe.maxBatchYield case final maxBatchYield?) ...[
      _asObjectField(maxBatchYield.amount),
      _asObjectField(maxBatchYield.unit),
    ],
    for (final note in recipe.preparationNotes) _asObjectField(note),
    for (final component in components) ...[
      _asObjectField(component.name),
      _asObjectField(component.amount),
      _asObjectField(component.unit),
      _asObjectField(component.behavior),
      if (component.note case final note?) _asObjectField(note),
    ],
  ]);

  ReviewRecipeDraft confirmAllUnambiguous() => ReviewRecipeDraft._(
    sourceKind: sourceKind,
    recipe: recipe.confirmAllUnambiguous(),
    components: [
      for (final component in components) component.confirmAllUnambiguous(),
    ],
    units: units,
  );

  ReviewRecipeDraft editRecipeName(String? value) => _replaceRecipe(
    recipe.copyWith(
      name: recipe.name.edit(value, localIssues: _requiredTextIssues(value)),
    ),
  );

  ReviewRecipeDraft confirmRecipeName() =>
      _replaceRecipe(recipe.copyWith(name: recipe.name.confirm()));

  ReviewRecipeDraft editBaseYieldAmount(String? value) => _replaceRecipe(
    recipe.copyWith(
      baseYield: recipe.baseYield.copyWith(
        amount: recipe.baseYield.amount.edit(
          value,
          localIssues: _positiveAmountIssues(value),
        ),
      ),
    ),
  );

  ReviewRecipeDraft confirmBaseYieldAmount() => _replaceRecipe(
    recipe.copyWith(
      baseYield: recipe.baseYield.copyWith(
        amount: recipe.baseYield.amount.confirm(),
      ),
    ),
  );

  ReviewRecipeDraft editBaseYieldUnit(String? value) {
    final maxBatchYield = recipe.maxBatchYield;
    return _replaceRecipe(
      recipe.copyWith(
        baseYield: recipe.baseYield.copyWith(
          unit: recipe.baseYield.unit.edit(
            value,
            localIssues: _unitIssues(value, units),
          ),
        ),
        maxBatchYield: maxBatchYield?.copyWith(
          unit: maxBatchYield.unit.edit(
            maxBatchYield.unit.value,
            localIssues: _maximumUnitIssues(
              value,
              maxBatchYield.unit.value,
              units,
            ),
          ),
        ),
      ),
    );
  }

  ReviewRecipeDraft confirmBaseYieldUnit() => _replaceRecipe(
    recipe.copyWith(
      baseYield: recipe.baseYield.copyWith(
        unit: recipe.baseYield.unit.confirm(),
      ),
    ),
  );

  ReviewRecipeDraft editMaxBatchYieldAmount(String? value) {
    final maxBatchYield = recipe.maxBatchYield!;
    return _replaceRecipe(
      recipe.copyWith(
        maxBatchYield: maxBatchYield.copyWith(
          amount: maxBatchYield.amount.edit(
            value,
            localIssues: _positiveAmountIssues(value),
          ),
        ),
      ),
    );
  }

  ReviewRecipeDraft confirmMaxBatchYieldAmount() {
    final maxBatchYield = recipe.maxBatchYield!;
    return _replaceRecipe(
      recipe.copyWith(
        maxBatchYield: maxBatchYield.copyWith(
          amount: maxBatchYield.amount.confirm(),
        ),
      ),
    );
  }

  ReviewRecipeDraft editMaxBatchYieldUnit(String? value) {
    final maxBatchYield = recipe.maxBatchYield!;
    return _replaceRecipe(
      recipe.copyWith(
        maxBatchYield: maxBatchYield.copyWith(
          unit: maxBatchYield.unit.edit(
            value,
            localIssues: _maximumUnitIssues(
              recipe.baseYield.unit.value,
              value,
              units,
            ),
          ),
        ),
      ),
    );
  }

  ReviewRecipeDraft confirmMaxBatchYieldUnit() {
    final maxBatchYield = recipe.maxBatchYield!;
    return _replaceRecipe(
      recipe.copyWith(
        maxBatchYield: maxBatchYield.copyWith(
          unit: maxBatchYield.unit.confirm(),
        ),
      ),
    );
  }

  ReviewRecipeDraft removeMaxBatchYield() =>
      _replaceRecipe(recipe.removeMaxBatchYield());

  ReviewRecipeDraft confirmMaxBatchYieldAbsent() =>
      _replaceRecipe(recipe.confirmMaxBatchYieldAbsent());

  ReviewRecipeDraft editPreparationNote(int index, String? value) =>
      _replaceRecipe(
        recipe.copyWith(
          preparationNotes: _replaceAt(
            recipe.preparationNotes,
            index,
            recipe.preparationNotes[index].edit(
              value,
              localIssues: _requiredTextIssues(value),
            ),
          ),
        ),
      );

  ReviewRecipeDraft confirmPreparationNote(int index) => _replaceRecipe(
    recipe.copyWith(
      preparationNotes: _replaceAt(
        recipe.preparationNotes,
        index,
        recipe.preparationNotes[index].confirm(),
      ),
    ),
  );

  ReviewRecipeDraft editComponentName(int index, String? value) =>
      _replaceComponent(
        index,
        components[index].copyWith(
          name: components[index].name.edit(
            value,
            localIssues: _requiredTextIssues(value),
          ),
        ),
      );

  ReviewRecipeDraft confirmComponentName(int index) => _replaceComponent(
    index,
    components[index].copyWith(name: components[index].name.confirm()),
  );

  ReviewRecipeDraft editComponentUnit(int index, String? value) =>
      _replaceComponent(
        index,
        components[index].copyWith(
          unit: components[index].unit.edit(
            value,
            localIssues:
                components[index].behavior.value == DraftScalingBehavior.manual
                ? _manualUnitIssues(value)
                : _unitIssues(value, units),
          ),
        ),
      );

  ReviewRecipeDraft editComponentAmount(int index, String? value) =>
      _replaceComponent(
        index,
        components[index].copyWith(
          amount: components[index].amount.edit(
            value,
            localIssues:
                components[index].behavior.value == DraftScalingBehavior.manual
                ? _manualAmountIssues(value)
                : _positiveAmountIssues(value),
          ),
        ),
      );

  ReviewRecipeDraft editComponentBehavior(
    int index,
    DraftScalingBehavior? value,
  ) {
    final component = components[index];
    final isManual = value == DraftScalingBehavior.manual;
    return _replaceComponent(
      index,
      component.copyWith(
        amount: component.amount.edit(
          isManual ? null : component.amount.value,
          localIssues: isManual
              ? const []
              : _positiveAmountIssues(component.amount.value),
        ),
        unit: component.unit.edit(
          isManual ? null : component.unit.value,
          localIssues: isManual
              ? const []
              : _unitIssues(component.unit.value, units),
        ),
        behavior: component.behavior.edit(
          value,
          localIssues: _requiredBehaviorIssues(value),
        ),
      ),
    );
  }

  ReviewRecipeDraft editComponentNote(int index, String? value) {
    final note = components[index].note;
    if (note == null) throw StateError('The component has no note field.');
    return _replaceComponent(
      index,
      components[index].copyWith(
        note: note.edit(value, localIssues: _requiredTextIssues(value)),
      ),
    );
  }

  ReviewRecipeDraft confirmComponentAmount(int index) => _replaceComponent(
    index,
    components[index].copyWith(amount: components[index].amount.confirm()),
  );

  ReviewRecipeDraft confirmComponentUnit(int index) => _replaceComponent(
    index,
    components[index].copyWith(unit: components[index].unit.confirm()),
  );

  ReviewRecipeDraft confirmComponentBehavior(int index) => _replaceComponent(
    index,
    components[index].copyWith(behavior: components[index].behavior.confirm()),
  );

  ReviewRecipeDraft confirmComponentNote(int index) {
    final note = components[index].note;
    if (note == null) throw StateError('The component has no note field.');
    return _replaceComponent(
      index,
      components[index].copyWith(note: note.confirm()),
    );
  }

  ReviewRecipeDraft _replaceRecipe(ReviewRecipeDetails nextRecipe) =>
      ReviewRecipeDraft._(
        sourceKind: sourceKind,
        recipe: nextRecipe,
        components: components,
        units: units,
      );

  ReviewRecipeDraft _replaceComponent(
    int index,
    ReviewRecipeComponent component,
  ) => ReviewRecipeDraft._(
    sourceKind: sourceKind,
    recipe: recipe,
    components: _replaceAt(components, index, component),
    units: units,
  );
}

List<T> _replaceAt<T>(List<T> items, int index, T replacement) => [
  for (var itemIndex = 0; itemIndex < items.length; itemIndex += 1)
    if (itemIndex == index) replacement else items[itemIndex],
];

ReviewYieldDraft _reviewYield(
  ExtractedYieldDraft source,
  UnitAliasResolver units,
) => ReviewYieldDraft(
  amount: _reviewField(source.amount, _positiveAmountIssues),
  unit: _reviewField(source.unit, (value) => _unitIssues(value, units)),
);

ReviewRecipeComponent _reviewComponent(
  ExtractedRecipeComponent component,
  UnitAliasResolver units,
) {
  final isManual = component.behavior.value == DraftScalingBehavior.manual;
  return ReviewRecipeComponent(
    name: _reviewField(component.name, _requiredTextIssues),
    amount: _reviewField(
      component.amount,
      isManual ? _manualAmountIssues : _positiveAmountIssues,
    ),
    unit: _reviewField(
      component.unit,
      isManual ? _manualUnitIssues : (value) => _unitIssues(value, units),
    ),
    behavior: _reviewField(component.behavior, _requiredBehaviorIssues),
    note: component.note == null
        ? null
        : _reviewField(component.note!, _requiredTextIssues),
  );
}

ReviewYieldDraft _reviewMaxYield(
  ExtractedYieldDraft source,
  ExtractedYieldDraft baseYield,
  UnitAliasResolver units,
) {
  final review = _reviewYield(source, units);
  return ReviewYieldDraft(
    amount: review.amount,
    unit: review.unit.edit(
      review.unit.value,
      localIssues: _maximumUnitIssues(
        baseYield.unit.value,
        source.unit.value,
        units,
      ),
    ),
  );
}

ReviewField<T> _reviewField<T>(
  ExtractedField<T> source,
  List<String> Function(T? value) validate,
) => ReviewField(
  sourceValue: source.value,
  value: source.value,
  evidence: source.evidence,
  confidence: source.confidence,
  sourceIssues: source.issues,
  localIssues: validate(source.value),
);

ReviewField<Object?> _asObjectField<T>(ReviewField<T> field) => ReviewField(
  sourceValue: field.sourceValue,
  value: field.value,
  evidence: field.evidence,
  confidence: field.confidence,
  sourceIssues: field.sourceIssues,
  localIssues: field.localIssues,
  isConfirmed: field.isConfirmed,
);

List<String> _requiredTextIssues(String? value) =>
    value == null || value.trim().isEmpty ? const ['A value is required.'] : [];

List<String> _positiveAmountIssues(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const ['A quantity is required.'];
  }
  try {
    if (Quantity.parse(value, Unit.gram).isZero || value.startsWith('-')) {
      return const ['The quantity must be greater than zero.'];
    }
  } on Object {
    return const ['The quantity must be a positive decimal string.'];
  }
  return const [];
}

List<String> _unitIssues(String? value, UnitAliasResolver units) =>
    units.resolve(value) == null
    ? const ['The unit is unsupported.']
    : const [];

List<String> _maximumUnitIssues(
  String? baseValue,
  String? maxValue,
  UnitAliasResolver units,
) {
  final unitIssues = _unitIssues(maxValue, units);
  if (unitIssues.isNotEmpty) return unitIssues;
  final baseUnit = units.resolve(baseValue);
  final maxUnit = units.resolve(maxValue)!;
  return baseUnit == null || baseUnit.canConvertTo(maxUnit)
      ? const []
      : const ['The maximum yield unit is incompatible.'];
}

List<String> _manualAmountIssues(String? value) => value == null
    ? const []
    : const ['A manual component cannot contain a quantity.'];

List<String> _manualUnitIssues(String? value) => value == null
    ? const []
    : const ['A manual component cannot contain a unit.'];

List<String> _requiredBehaviorIssues(DraftScalingBehavior? value) =>
    value == null ? const ['A scaling behavior is required.'] : const [];
