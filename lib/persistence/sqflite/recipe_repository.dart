import 'dart:convert';

import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';
import 'package:sqflite/sqflite.dart';

/// Selects every `recipes` row whose revision is the highest stored for its
/// id.
const _latestRevisionsSql = '''
SELECT recipes.* FROM recipes
INNER JOIN (
  SELECT id, MAX(revision) AS revision FROM recipes GROUP BY id
) latest ON recipes.id = latest.id AND recipes.revision = latest.revision
ORDER BY recipes.id
''';

/// [RecipeRepository] backed by the `recipes` and `recipe_components`
/// tables.
///
/// A recipe revision is immutable once saved: [saveRevision] only ever
/// inserts a new `(id, revision)` row, and a revision's components are
/// written alongside it in the same transaction so a partially-saved recipe
/// is never visible to a reader.
final class SqfliteRecipeRepository implements RecipeRepository {
  /// Creates a repository over the already-open database [_db].
  const SqfliteRecipeRepository(this._db);

  final Database _db;

  @override
  Future<List<Recipe>> listLatestRevisions() async {
    final rows = await _db.rawQuery(_latestRevisionsSql);
    final recipes = <Recipe>[];
    for (final row in rows) {
      recipes.add(await _recipeFromRow(row));
    }
    return recipes;
  }

  @override
  Future<Recipe?> findRevision(String id, int revision) async {
    final rows = await _db.query(
      'recipes',
      where: 'id = ? AND revision = ?',
      whereArgs: [id, revision],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _recipeFromRow(rows.single);
  }

  @override
  Future<Recipe?> findLatest(String id) async {
    final rows = await _db.query(
      'recipes',
      where: 'id = ?',
      whereArgs: [id],
      orderBy: 'revision DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _recipeFromRow(rows.single);
  }

  @override
  Future<void> saveRevision(Recipe recipe) => _db.transaction((txn) async {
    await txn.insert('recipes', <String, Object?>{
      'id': recipe.id,
      'revision': recipe.revision,
      'name': recipe.name,
      'category': recipe.category,
      ...quantityToColumns(recipe.baseYield, 'base_yield'),
      if (recipe.maxBatchYield case final max?)
        ...quantityToColumns(max, 'max_batch')
      else ...<String, Object?>{
        'max_batch_numerator': null,
        'max_batch_denominator': null,
        'max_batch_unit': null,
      },
      'preparation_notes': jsonEncode(recipe.preparationNotes),
      'modified_at': recipe.modifiedAt.toIso8601String(),
      'is_archived': recipe.isArchived ? 1 : 0,
    });

    for (final component in recipe.components) {
      await txn.insert(
        'recipe_components',
        _componentToRow(recipe, component),
      );
    }
  });

  @override
  Future<void> setArchived(String id, {required bool isArchived}) => _db.update(
    'recipes',
    <String, Object?>{'is_archived': isArchived ? 1 : 0},
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<Recipe> _recipeFromRow(Map<String, Object?> row) async {
    final id = row['id']! as String;
    final revision = row['revision']! as int;
    final components = await _componentsFor(id, revision);
    return Recipe(
      id: id,
      revision: revision,
      name: row['name']! as String,
      category: row['category'] as String?,
      baseYield: quantityFromColumns(row, 'base_yield'),
      maxBatchYield: row['max_batch_unit'] == null
          ? null
          : quantityFromColumns(row, 'max_batch'),
      components: components,
      preparationNotes:
          (jsonDecode(row['preparation_notes']! as String) as List<dynamic>)
              .cast<String>(),
      modifiedAt: DateTime.parse(row['modified_at']! as String),
      isArchived: (row['is_archived']! as int) == 1,
    );
  }

  Future<List<RecipeComponent>> _componentsFor(
    String recipeId,
    int revision,
  ) async {
    final rows = await _db.query(
      'recipe_components',
      where: 'recipe_id = ? AND recipe_revision = ?',
      whereArgs: [recipeId, revision],
      orderBy: 'display_order',
    );
    return rows.map(_componentFromRow).toList();
  }

  Map<String, Object?> _componentToRow(
    Recipe recipe,
    RecipeComponent component,
  ) {
    final (targetKind, targetId) = switch (component.target) {
      IngredientRef(:final ingredientId) => ('ingredient', ingredientId),
      SubRecipeRef(:final recipeId) => ('recipe', recipeId),
    };
    return <String, Object?>{
      'recipe_id': recipe.id,
      'recipe_revision': recipe.revision,
      'component_id': component.id,
      'target_kind': targetKind,
      'target_id': targetId,
      if (component.baseQuantity case final base?)
        ...quantityToColumns(base, 'base')
      else ...<String, Object?>{
        'base_numerator': null,
        'base_denominator': null,
        'base_unit': null,
      },
      'behavior': component.behavior.name,
      'rounding_increment': component.rounding?.increment.toString(),
      'note': component.note,
      'display_order': component.displayOrder,
    };
  }

  RecipeComponent _componentFromRow(Map<String, Object?> row) {
    final targetKind = row['target_kind'];
    final targetId = row['target_id']! as String;
    final target = switch (targetKind) {
      'ingredient' => IngredientRef(targetId),
      'recipe' => SubRecipeRef(targetId),
      _ => throw CorruptDatabaseError(
        'unknown component target kind: $targetKind',
      ),
    };

    final behaviorName = row['behavior'];
    final behavior = ScalingBehavior.values.asNameMap()[behaviorName];
    if (behavior == null) {
      throw CorruptDatabaseError(
        'unknown component behavior: $behaviorName',
      );
    }

    final roundingIncrement = row['rounding_increment'];

    return RecipeComponent(
      id: row['component_id']! as String,
      target: target,
      baseQuantity: row['base_unit'] == null
          ? null
          : quantityFromColumns(row, 'base'),
      behavior: behavior,
      displayOrder: row['display_order']! as int,
      rounding: roundingIncrement == null
          ? null
          : RoundingRule.upToIncrement(
              Decimal.parse(roundingIncrement as String),
            ),
      note: row['note'] as String?,
    );
  }
}
