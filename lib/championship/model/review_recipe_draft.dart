import 'package:prep_book/championship/import/unit_alias_resolver.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/domain/domain.dart';

/// A validation issue the review layer raises on its own, without the model.
///
/// The model reports what the source does or does not say in `sourceIssues`,
/// in the request's language. Local issues describe what the reviewer still
/// has to do, so they are codes here and sentences only where they are shown.
/// [message] is the technical English form the verifier reports against a
/// field path; the review screen renders each code in the app's locale.
enum ReviewIssue {
  valueRequired('A value is required.', isAbsence: true),
  quantityRequired('A quantity is required.', isAbsence: true),
  quantityNotPositive('The quantity must be greater than zero.'),
  quantityNotDecimal('The quantity must be a positive decimal string.'),
  unitRequired('A unit is required.', isAbsence: true),
  unitUnsupported('The unit is unsupported.'),
  maxUnitIncompatible('The maximum yield unit is incompatible.'),
  manualHasQuantity('A manual component cannot contain a quantity.'),
  manualHasUnit('A manual component cannot contain a unit.'),
  behaviorRequired('A scaling behavior is required.', isAbsence: true);

  const ReviewIssue(this.message, {this.isAbsence = false});

  final String message;

  /// Whether the issue says only that the value is missing. A missing value
  /// the model has already explained is not reported a second time.
  final bool isAbsence;
}

final class ReviewField<T> {
  ReviewField({
    required this.sourceValue,
    required this.value,
    required this.evidence,
    required this.confidence,
    required List<String> sourceIssues,
    required List<ReviewIssue> localIssues,
    this.isConfirmed = false,
  }) : sourceIssues = List.unmodifiable(sourceIssues),
       localIssues = List.unmodifiable(localIssues);

  final T? sourceValue;
  final T? value;
  final String evidence;
  final ExtractionConfidence confidence;
  final List<String> sourceIssues;
  final List<ReviewIssue> localIssues;
  final bool isConfirmed;

  bool get isEdited => value != sourceValue;

  /// The model's issues that still apply: all of them until the value is
  /// edited or explicitly confirmed, none afterwards. An edit replaces the
  /// proposal they describe; a confirmation records that the reviewer read
  /// them against the source and accepted the value anyway.
  List<String> get activeSourceIssues => List.unmodifiable(
    isEdited || isConfirmed ? const <String>[] : sourceIssues,
  );

  /// The local issues that still apply. An absence the model has already
  /// reported is left to that report, so the same gap is not shown twice.
  List<ReviewIssue> get activeLocalIssues => List.unmodifiable([
    for (final issue in localIssues)
      if (!issue.isAbsence || activeSourceIssues.isEmpty) issue,
  ]);

  List<String> get activeIssues => List.unmodifiable([
    ...activeSourceIssues,
    for (final issue in activeLocalIssues) issue.message,
  ]);

  /// Whether the reviewer may confirm this value one field at a time. A
  /// present, locally valid value qualifies even when the model flagged it:
  /// resolving the model's doubt is what the explicit confirmation is for.
  bool get canConfirm => value != null && activeLocalIssues.isEmpty;

  /// Whether bulk confirmation may take this value: [canConfirm], and the
  /// model raised nothing against it, so no judgment is being skipped.
  bool get isUnambiguous => canConfirm && activeIssues.isEmpty;

  ReviewField<T> edit(
    T? nextValue, {
    List<ReviewIssue> localIssues = const [],
  }) => ReviewField(
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

  ReviewField<T> confirmIfUnambiguous() => isUnambiguous ? confirm() : this;
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

  /// Changes a component's scaling behavior.
  ///
  /// The amount and unit are only touched when the change moves the component
  /// across the manual boundary: becoming manual clears them, because a manual
  /// component carries no quantity, and leaving manual brings the model's
  /// proposal back for confirmation. Between two numeric behaviors the
  /// quantity means the same thing, so a confirmed amount and unit stay
  /// confirmed.
  ReviewRecipeDraft editComponentBehavior(
    int index,
    DraftScalingBehavior? value,
  ) {
    final component = components[index];
    final wasManual = component.behavior.value == DraftScalingBehavior.manual;
    final isManual = value == DraftScalingBehavior.manual;
    final behavior = component.behavior.edit(
      value,
      localIssues: _requiredBehaviorIssues(value),
    );
    if (isManual == wasManual) {
      return _replaceComponent(index, component.copyWith(behavior: behavior));
    }
    if (isManual) {
      return _replaceComponent(
        index,
        component.copyWith(
          amount: component.amount.edit(null),
          unit: component.unit.edit(null),
          behavior: behavior,
        ),
      );
    }
    final amount = component.amount.sourceValue;
    final unit = component.unit.sourceValue;
    return _replaceComponent(
      index,
      component.copyWith(
        amount: component.amount.edit(
          amount,
          localIssues: _positiveAmountIssues(amount),
        ),
        unit: component.unit.edit(unit, localIssues: _unitIssues(unit, units)),
        behavior: behavior,
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

  ReviewRecipeDraft removeComponent(int index) {
    RangeError.checkValidIndex(index, components);
    if (components.length == 1) {
      throw StateError('A recipe must contain at least one component.');
    }
    return ReviewRecipeDraft._(
      sourceKind: sourceKind,
      recipe: recipe,
      components: [
        for (var itemIndex = 0; itemIndex < components.length; itemIndex += 1)
          if (itemIndex != index) components[itemIndex],
      ],
      units: units,
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
  List<ReviewIssue> Function(T? value) validate,
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

List<ReviewIssue> _requiredTextIssues(String? value) =>
    value == null || value.trim().isEmpty
    ? const [ReviewIssue.valueRequired]
    : const [];

List<ReviewIssue> _positiveAmountIssues(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const [ReviewIssue.quantityRequired];
  }
  if (value.startsWith('-')) {
    return const [ReviewIssue.quantityNotPositive];
  }
  try {
    if (Quantity.parse(value, Unit.gram).isZero) {
      return const [ReviewIssue.quantityNotPositive];
    }
  } on Object {
    return const [ReviewIssue.quantityNotDecimal];
  }
  return const [];
}

List<ReviewIssue> _unitIssues(String? value, UnitAliasResolver units) {
  if (value == null || value.trim().isEmpty) {
    return const [ReviewIssue.unitRequired];
  }
  return units.resolve(value) == null
      ? const [ReviewIssue.unitUnsupported]
      : const [];
}

List<ReviewIssue> _maximumUnitIssues(
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
      : const [ReviewIssue.maxUnitIncompatible];
}

List<ReviewIssue> _manualAmountIssues(String? value) =>
    value == null ? const [] : const [ReviewIssue.manualHasQuantity];

List<ReviewIssue> _manualUnitIssues(String? value) =>
    value == null ? const [] : const [ReviewIssue.manualHasUnit];

List<ReviewIssue> _requiredBehaviorIssues(DraftScalingBehavior? value) =>
    value == null ? const [ReviewIssue.behaviorRequired] : const [];
