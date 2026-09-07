import 'dart:convert';

import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';
import 'package:prep_book/persistence/sqflite/timestamps.dart';
import 'package:sqflite/sqflite.dart';

/// Reduces `recipes` to one row per id: the highest revision stored for it.
///
/// Shared by the two queries below rather than written twice, so what
/// "latest" means cannot drift between listing every recipe and listing the
/// subset that uses one ingredient. A subset computed against a different
/// notion of latest than the whole would be a bug, not a degree of freedom.
const _latestRevisionsFrom = '''
FROM recipes
INNER JOIN (
  SELECT id, MAX(revision) AS revision FROM recipes GROUP BY id
) latest ON recipes.id = latest.id AND recipes.revision = latest.revision''';

/// Selects every `recipes` row whose revision is the highest stored for its
/// id.
const _latestRevisionsSql =
    '''
SELECT recipes.* $_latestRevisionsFrom
ORDER BY recipes.id
''';

/// [_latestRevisionsSql] restricted to the recipes whose latest revision
/// references one ingredient, bound to the single `?` parameter.
///
/// `target_kind = 'ingredient'` is load-bearing rather than defensive:
/// `recipe_components.target_id` carries no foreign key and the same column
/// holds sub-recipe ids, so a recipe whose id happens to equal an ingredient
/// id would otherwise be reported as a user of that ingredient.
///
/// `EXISTS` rather than a join to `recipe_components`, because a recipe that
/// names the ingredient in two of its components is one recipe; a join would
/// return it once per matching component.
const _latestRevisionsUsingIngredientSql =
    '''
SELECT recipes.* $_latestRevisionsFrom
WHERE EXISTS (
  SELECT 1 FROM recipe_components
  WHERE recipe_components.recipe_id = recipes.id
    AND recipe_components.recipe_revision = recipes.revision
    AND recipe_components.target_kind = 'ingredient'
    AND recipe_components.target_id = ?
)
ORDER BY recipes.id
''';

/// Whether the nullable quantity group named [prefix] holds anything at all
/// in [row].
///
/// The two nullable quantity groups this file reads — a recipe's maximum
/// batch yield and a component's base amount — are written all-NULL or
/// all-present. Deciding on the unit column alone was a fail-open read: a
/// group whose unit is NULL while its numerator is populated never reached
/// `quantityFromColumns`, whose own "all three or throw" guard is the thing
/// that would have caught it. The amount was dropped instead — silently on
/// a manual component, and on any other behavior as a bare `DomainError`
/// escaping both of [SqfliteRecipeRepository._componentFromRow]'s clauses,
/// which a caller wrapping storage reads in `on CorruptDatabaseError` never
/// sees.
///
/// So any one of the three columns being present is enough to commit to
/// reading the group and let that guard rule on it. A `CHECK` constraint
/// would express the same rule in the schema, but it would make a
/// half-filled group unrepresentable and so block the `UPDATE` the failure
/// tests use to plant exactly this corruption.
bool _quantityGroupPresent(Map<String, Object?> row, String prefix) =>
    row['${prefix}_numerator'] != null ||
    row['${prefix}_denominator'] != null ||
    row['${prefix}_unit'] != null;

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

  /// Writes [recipe] and its components as a new revision, in one
  /// transaction.
  ///
  /// This column set is mirrored by `result_codec.dart`'s `_recipeToJson`,
  /// which encodes the same `Recipe` fields into a run snapshot. The two
  /// are deliberately separate — a change to this row shape must not be
  /// able to reach a payload already stored — so a field added to `Recipe`
  /// has to be added in both places. See `_recipeComponentToJson` there for
  /// the full reasoning; naming each other is the agreed mitigation until a
  /// shared encoder earns its own change.
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
      // every writer: [timestampToStorage] moves the value to UTC and
      // always writes the microsecond triplet. A bare `toIso8601String`
      // leaves the first to whatever `DateTime` the caller happened to hold
      // and the second to whether that instant landed on a whole
      // millisecond. `_recipeFromRow` reads the column back unchanged and
      // relies on every stored value being in that one form. Nothing orders
      // on this column today, but it stores the same value the run payload
      // and `production_runs.created_at` do, and one writer for the three
      // is what keeps them from drifting; see [timestampToStorage].
      'modified_at': timestampToStorage(recipe.modifiedAt),
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
  Future<List<Recipe>> listLatestRevisionsUsingIngredient(
    String ingredientId,
  ) async {
    final rows = await _db.rawQuery(_latestRevisionsUsingIngredientSql, [
      ingredientId,
    ]);
    final recipes = <Recipe>[];
    for (final row in rows) {
      recipes.add(await _recipeFromRow(row));
    }
    return recipes;
  }

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
  /// `cast<String>()` below to check its elements inside this block. That
  /// is a property of a domain internal rather than of anything visible
  /// here, so `failure_paths_test.dart` asserts it against the domain
  /// directly as well as reaching this guard through a stored row.
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
        maxBatchYield: _quantityGroupPresent(row, 'max_batch')
            ? quantityFromColumns(row, 'max_batch', rowLabel: rowLabel)
            : null,
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

  /// Encodes [component] as a `recipe_components` row belonging to
  /// [recipe]'s revision.
  ///
  /// Mirrored field for field by `result_codec.dart`'s
  /// `_recipeComponentToJson`, which writes the same component into a run
  /// snapshot instead. Kept separate on purpose; that function's own
  /// comment carries the reasoning. The two `target_kind` values are part of
  /// that mirroring and must stay identical in both places.
  ///
  /// A sub-recipe's kind is `sub_recipe`, the value the specification names,
  /// rather than `recipe`: this row already has a `recipe_id` column naming
  /// the recipe that *owns* the component, so `target_kind = 'recipe'` read
  /// as if it pointed at that one. The distinction is invisible in a query
  /// that gets it wrong — a filter on `sub_recipe` written from the
  /// specification would have matched no row and reported nothing, silently.
  Map<String, Object?> _componentToRow(
    Recipe recipe,
    RecipeComponent component,
  ) {
    final (targetKind, targetId) = switch (component.target) {
      IngredientRef(:final ingredientId) => ('ingredient', ingredientId),
      SubRecipeRef(:final recipeId) => ('sub_recipe', recipeId),
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
        'sub_recipe' => SubRecipeRef(targetId),
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
        baseQuantity: _quantityGroupPresent(row, 'base')
            ? quantityFromColumns(row, 'base', rowLabel: _componentLabel(row))
            : null,
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
