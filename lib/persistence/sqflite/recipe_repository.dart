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
      // Normalized before serializing, so this column holds one form for
      // every writer. `toIso8601String` emits a trailing `Z` only for a UTC
      // instant, and a caller supplies whatever `DateTime` it holds —
      // `DateTime.now()` is local. Mixing the two forms in one column makes
      // it uncomparable as text, and a naive value already written cannot
      // be assigned an offset afterwards. `_recipeFromRow` reads it back
      // unchanged and relies on every stored value being UTC.
      'modified_at': recipe.modifiedAt.toUtc().toIso8601String(),
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

  /// Rebuilds the [Recipe] a `recipes` row holds, together with its
  /// components.
  ///
  /// The column casts are unchecked, and a value can reach them at a type
  /// its column does not declare: SQLite applies affinity rather than a
  /// strict type, so a BLOB written into a `TEXT` column and a
  /// non-numeric string written into an `INTEGER` one both survive
  /// unconverted and come back at the type they were written. The cast
  /// then throws a bare `TypeError` naming no row, so it is restated here
  /// as a [CorruptDatabaseError], the same way `decodeRunPayload` restates
  /// a cast failure on decoded JSON. `preparationNotes` is covered too:
  /// `Recipe`'s factory copies the list, which forces the lazy
  /// `cast<String>()` below to check its elements inside this block.
  /// A domain rejection is not swallowed by this — every modelled domain
  /// failure extends `DomainError`, never `TypeError` — and neither is a
  /// component's own corruption, which [_componentFromRow] has already
  /// turned into a [CorruptDatabaseError] before it reaches here.
  Future<Recipe> _recipeFromRow(Map<String, Object?> row) async {
    try {
      final id = row['id']! as String;
      final revision = row['revision']! as int;
      final rowLabel = 'recipes row $id revision $revision';
      final components = await _componentsFor(id, revision);
      return Recipe(
        id: id,
        revision: revision,
        name: row['name']! as String,
        category: row['category'] as String?,
        baseYield: quantityFromColumns(row, 'base_yield', rowLabel: rowLabel),
        maxBatchYield: row['max_batch_unit'] == null
            ? null
            : quantityFromColumns(row, 'max_batch', rowLabel: rowLabel),
        components: components,
        preparationNotes:
            (jsonDecode(row['preparation_notes']! as String) as List<dynamic>)
                .cast<String>(),
        modifiedAt: DateTime.parse(row['modified_at']! as String),
        isArchived: (row['is_archived']! as int) == 1,
      );
      // A wrong-typed column is a corrupt row, not a programmer bug, so its
      // `TypeError` is caught rather than left to escape — see the doc
      // comment above.
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      throw CorruptDatabaseError(
        'recipes row ${row['id']} revision ${row['revision']} holds a '
        'column of the wrong type: $error',
      );
    } on FormatException catch (error) {
      // Reached by `jsonDecode` on `preparation_notes` text that is not JSON
      // at all, and by `DateTime.parse` on a `modified_at` that is not an
      // ISO 8601 instant. `preparation_notes` that *is* valid JSON but is
      // not a list fails one step later, at the `as List<dynamic>` cast, so
      // it lands in the `TypeError` clause above instead.
      throw CorruptDatabaseError(
        'recipes row ${row['id']} revision ${row['revision']} has an '
        'unparseable column: $error',
      );
    }
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

  /// Rebuilds the [RecipeComponent] a `recipe_components` row holds.
  ///
  /// Guarded against a wrong-typed column for the same reason, and in the
  /// same way, as [_recipeFromRow] — see its comment.
  RecipeComponent _componentFromRow(Map<String, Object?> row) {
    try {
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
            : quantityFromColumns(row, 'base', rowLabel: _componentLabel(row)),
        behavior: behavior,
        displayOrder: row['display_order']! as int,
        rounding: roundingIncrement == null
            ? null
            : RoundingRule.upToIncrement(
                Decimal.parse(roundingIncrement as String),
              ),
        note: row['note'] as String?,
      );
      // A wrong-typed column is a corrupt row, not a programmer bug, so its
      // `TypeError` is caught rather than left to escape — see
      // [_recipeFromRow]'s doc comment.
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      throw CorruptDatabaseError(
        '${_componentLabel(row)} holds a column of the wrong type: $error',
      );
    } on FormatException catch (error) {
      // Reached by `Decimal.parse` on a `rounding_increment` that is not a
      // decimal literal.
      throw CorruptDatabaseError(
        '${_componentLabel(row)} has an unparseable column: $error',
      );
    }
  }

  /// Identifies a `recipe_components` row by its three key columns.
  ///
  /// Shared by [_componentFromRow]'s two guards and the [quantityFromColumns]
  /// call inside them, so a row that fails on its base quantity is named the
  /// same way as one that fails on a cast. Reads the raw values rather than
  /// the casts, because the label has to survive the very corruption it
  /// describes.
  String _componentLabel(Map<String, Object?> row) =>
      'recipe_components row ${row['recipe_id']} revision '
      '${row['recipe_revision']} component ${row['component_id']}';
}
