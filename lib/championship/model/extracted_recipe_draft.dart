enum RecipeImportSourceKind { sample, text, image }

enum ExtractionConfidence { high, medium, low }

enum DraftScalingBehavior { proportional, perBatch, fixedOnce, manual }

final class ExtractedField<T> {
  ExtractedField({
    required this.value,
    required this.evidence,
    required this.confidence,
    required List<String> issues,
  }) : issues = List.unmodifiable(issues);

  final T? value;
  final String evidence;
  final ExtractionConfidence confidence;
  final List<String> issues;

  Map<String, Object?> toJson(Object? Function(T? value) encodeValue) => {
    'value': encodeValue(value),
    'evidence': evidence,
    'confidence': confidence.name,
    'issues': issues,
  };
}

final class ExtractedYieldDraft {
  const ExtractedYieldDraft({required this.amount, required this.unit});

  final ExtractedField<String> amount;
  final ExtractedField<String> unit;

  Map<String, Object?> toJson() => {
    'amount': amount.toJson((value) => value),
    'unit': unit.toJson((value) => value),
  };
}

final class ExtractedRecipeDetails {
  ExtractedRecipeDetails({
    required this.name,
    required this.baseYield,
    required this.maxBatchYield,
    required List<ExtractedField<String>> preparationNotes,
  }) : preparationNotes = List.unmodifiable(preparationNotes);

  final ExtractedField<String> name;
  final ExtractedYieldDraft baseYield;
  final ExtractedYieldDraft? maxBatchYield;
  final List<ExtractedField<String>> preparationNotes;

  Map<String, Object?> toJson() => {
    'name': name.toJson((value) => value),
    'baseYield': baseYield.toJson(),
    'maxBatchYield': maxBatchYield?.toJson(),
    'preparationNotes': [
      for (final note in preparationNotes) note.toJson((value) => value),
    ],
  };
}

final class ExtractedRecipeComponent {
  const ExtractedRecipeComponent({
    required this.name,
    required this.amount,
    required this.unit,
    required this.behavior,
    required this.note,
  });

  final ExtractedField<String> name;
  final ExtractedField<String> amount;
  final ExtractedField<String> unit;
  final ExtractedField<DraftScalingBehavior> behavior;
  final ExtractedField<String>? note;

  Map<String, Object?> toJson() => {
    'name': name.toJson((value) => value),
    'amount': amount.toJson((value) => value),
    'unit': unit.toJson((value) => value),
    'behavior': behavior.toJson((value) => value?.name),
    'note': note?.toJson((value) => value),
  };
}

final class ExtractedRecipeDraft {
  ExtractedRecipeDraft._({
    required this.schemaVersion,
    required this.sourceKind,
    required this.recipe,
    required List<ExtractedRecipeComponent> components,
  }) : components = List.unmodifiable(components);

  factory ExtractedRecipeDraft.fromJson(Map<String, Object?> json) {
    _expectKeys(json, const {
      'schemaVersion',
      'sourceKind',
      'recipe',
      'components',
    }, r'$root');
    final schemaVersion = _required(json, 'schemaVersion', r'$root');
    if (schemaVersion is! int || schemaVersion != 1) {
      throw const FormatException('schemaVersion must be 1.');
    }

    return ExtractedRecipeDraft._(
      schemaVersion: 1,
      sourceKind: _parseEnum(
        _required(json, 'sourceKind', r'$root'),
        RecipeImportSourceKind.values,
        'sourceKind',
      ),
      recipe: _parseRecipe(_required(json, 'recipe', r'$root')),
      components: _parseList(
        _required(json, 'components', r'$root'),
        'components',
        _parseComponent,
      ),
    );
  }

  final int schemaVersion;
  final RecipeImportSourceKind sourceKind;
  final ExtractedRecipeDetails recipe;
  final List<ExtractedRecipeComponent> components;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'sourceKind': sourceKind.name,
    'recipe': recipe.toJson(),
    'components': [for (final component in components) component.toJson()],
  };
}

ExtractedRecipeDetails _parseRecipe(Object? value) {
  final json = _parseMap(value, 'recipe');
  _expectKeys(json, const {
    'name',
    'baseYield',
    'maxBatchYield',
    'preparationNotes',
  }, 'recipe');
  final maxBatchYield = _required(json, 'maxBatchYield', 'recipe');
  return ExtractedRecipeDetails(
    name: _parseStringField(_required(json, 'name', 'recipe'), 'recipe.name'),
    baseYield: _parseYield(
      _required(json, 'baseYield', 'recipe'),
      'recipe.baseYield',
    ),
    maxBatchYield: maxBatchYield == null
        ? null
        : _parseYield(maxBatchYield, 'recipe.maxBatchYield'),
    preparationNotes: _parseList(
      _required(json, 'preparationNotes', 'recipe'),
      'recipe.preparationNotes',
      _parseStringField,
    ),
  );
}

ExtractedYieldDraft _parseYield(Object? value, String path) {
  final json = _parseMap(value, path);
  _expectKeys(json, const {'amount', 'unit'}, path);
  return ExtractedYieldDraft(
    amount: _parseStringField(_required(json, 'amount', path), '$path.amount'),
    unit: _parseStringField(_required(json, 'unit', path), '$path.unit'),
  );
}

ExtractedRecipeComponent _parseComponent(Object? value, String path) {
  final json = _parseMap(value, path);
  _expectKeys(json, const {'name', 'amount', 'unit', 'behavior', 'note'}, path);
  final behavior = _parseBehaviorField(
    _required(json, 'behavior', path),
    '$path.behavior',
  );
  final amount = _parseStringField(
    _required(json, 'amount', path),
    '$path.amount',
  );
  final unit = _parseStringField(_required(json, 'unit', path), '$path.unit');
  if (behavior.value == DraftScalingBehavior.manual &&
      (amount.value != null || unit.value != null)) {
    throw FormatException('$path manual components cannot contain quantities.');
  }
  final note = _required(json, 'note', path);
  return ExtractedRecipeComponent(
    name: _parseStringField(_required(json, 'name', path), '$path.name'),
    amount: amount,
    unit: unit,
    behavior: behavior,
    note: note == null ? null : _parseStringField(note, '$path.note'),
  );
}

ExtractedField<String> _parseStringField(Object? value, String path) =>
    _parseField(value, path, (fieldValue) {
      if (fieldValue != null && fieldValue is! String) {
        throw FormatException('$path.value must be a string or null.');
      }
      return fieldValue as String?;
    });

ExtractedField<DraftScalingBehavior> _parseBehaviorField(
  Object? value,
  String path,
) => _parseField(
  value,
  path,
  (fieldValue) => fieldValue == null
      ? null
      : _parseEnum(fieldValue, DraftScalingBehavior.values, '$path.value'),
);

ExtractedField<T> _parseField<T>(
  Object? value,
  String path,
  T? Function(Object? value) parseValue,
) {
  final json = _parseMap(value, path);
  _expectKeys(json, const {'value', 'evidence', 'confidence', 'issues'}, path);
  final evidence = _required(json, 'evidence', path);
  if (evidence is! String) {
    throw FormatException('$path.evidence must be a string.');
  }
  final issues = _parseList<String>(
    _required(json, 'issues', path),
    '$path.issues',
    (issue, issuePath) {
      if (issue is! String) {
        throw FormatException('$issuePath must be a string.');
      }
      return issue;
    },
  );
  return ExtractedField(
    value: parseValue(_required(json, 'value', path)),
    evidence: evidence,
    confidence: _parseEnum(
      _required(json, 'confidence', path),
      ExtractionConfidence.values,
      '$path.confidence',
    ),
    issues: issues,
  );
}

Map<String, Object?> _parseMap(Object? value, String path) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$path must be an object.');
  }
  return value;
}

List<T> _parseList<T>(
  Object? value,
  String path,
  T Function(Object? value, String path) parseItem,
) {
  if (value is! List<Object?>) {
    throw FormatException('$path must be an array.');
  }
  return [
    for (var index = 0; index < value.length; index += 1)
      parseItem(value[index], '$path[$index]'),
  ];
}

T _parseEnum<T extends Enum>(Object? value, List<T> values, String path) {
  if (value is! String) {
    throw FormatException('$path must be a string.');
  }
  for (final candidate in values) {
    if (candidate.name == value) return candidate;
  }
  throw FormatException('$path contains an unsupported value.');
}

Object? _required(Map<String, Object?> json, String key, String _) => json[key];

void _expectKeys(Map<String, Object?> json, Set<String> expected, String path) {
  if (json.length != expected.length || !json.keys.every(expected.contains)) {
    throw FormatException('$path has an invalid property set.');
  }
}
