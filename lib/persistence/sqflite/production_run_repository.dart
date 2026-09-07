import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';
import 'package:prep_book/persistence/sqflite/result_codec.dart';
import 'package:sqflite/sqflite.dart';

/// The `production_runs` columns [ProductionRunRepository.listSummaries]
/// needs. Selecting exactly this list, rather than `SELECT *`, is what keeps
/// that query from ever reading `result_json` — the whole point of
/// [ProductionRunSummary] existing separately from [ProductionRun].
const _summaryColumns = <String>[
  'id',
  'recipe_id',
  'recipe_revision',
  'target_numerator',
  'target_denominator',
  'target_unit',
  'created_at',
];

/// [ProductionRunRepository] backed by the `production_runs`,
/// `run_acknowledgements`, and `run_overrides` tables.
///
/// [save] writes a run's immutable snapshot — its recipe, dependency
/// snapshot, and calculated result, encoded by [encodeRunPayload] — together
/// with the acknowledgement and override state it carries at that moment,
/// all in one transaction. `production_runs` carries no foreign key into
/// `recipes`, so editing, archiving, or deleting the source recipe
/// afterwards can never reach a row already saved here.
final class SqfliteProductionRunRepository implements ProductionRunRepository {
  /// Creates a repository over the already-open database [_db].
  const SqfliteProductionRunRepository(this._db);

  final Database _db;

  @override
  Future<List<ProductionRunSummary>> listSummaries() async {
    final rows = await _db.query(
      'production_runs',
      columns: _summaryColumns,
      orderBy: 'created_at DESC',
    );
    return [
      for (final row in rows)
        ProductionRunSummary(
          id: row['id']! as String,
          recipeId: row['recipe_id']! as String,
          recipeRevision: row['recipe_revision']! as int,
          targetYield: quantityFromColumns(row, 'target'),
          createdAt: DateTime.parse(row['created_at']! as String),
        ),
    ];
  }

  @override
  Future<ProductionRun?> findById(String id) async {
    final rows = await _db.query(
      'production_runs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.single;

    final payload = decodeRunPayload(row['result_json']! as String);
    final acknowledgedWarnings = await _acknowledgementsFor(id);
    final overrides = await _overridesFor(id);

    return ProductionRun(
      id: id,
      createdAt: DateTime.parse(row['created_at']! as String),
      recipe: payload.recipe,
      dependencySnapshot: payload.dependencySnapshot,
      targetYield: quantityFromColumns(row, 'target'),
      result: payload.result,
      overrides: overrides,
      acknowledgedWarnings: acknowledgedWarnings,
    );
  }

  @override
  Future<void> save(ProductionRun run) => _db.transaction((txn) async {
    await txn.insert('production_runs', <String, Object?>{
      'id': run.id,
      'recipe_id': run.recipe.id,
      'recipe_revision': run.recipe.revision,
      ...quantityToColumns(run.targetYield, 'target'),
      'created_at': run.createdAt.toIso8601String(),
      'result_json': encodeRunPayload(run),
    });

    for (final warning in run.acknowledgedWarnings) {
      await txn.insert(
        'run_acknowledgements',
        _acknowledgementRow(run.id, warning),
      );
    }
    for (final entry in run.overrides.entries) {
      await txn.insert(
        'run_overrides',
        _overrideRow(run.id, entry.key, entry.value),
      );
    }
  });

  @override
  Future<void> recordAcknowledgement(
    String runId,
    ProductionWarning warning,
  ) => _db.insert('run_acknowledgements', _acknowledgementRow(runId, warning));

  @override
  Future<void> recordOverride(String runId, OverrideKey key, Quantity value) =>
      _db.insert('run_overrides', _overrideRow(runId, key, value));

  Future<Set<ProductionWarning>> _acknowledgementsFor(String runId) async {
    final rows = await _db.query(
      'run_acknowledgements',
      where: 'run_id = ?',
      whereArgs: [runId],
    );
    return rows.map(_warningFromRow).toSet();
  }

  Future<Map<OverrideKey, Quantity>> _overridesFor(String runId) async {
    final rows = await _db.query(
      'run_overrides',
      where: 'run_id = ?',
      whereArgs: [runId],
    );
    return <OverrideKey, Quantity>{
      for (final row in rows)
        (row['recipe_id']! as String, row['component_id']! as String):
            quantityFromColumns(row, 'override'),
    };
  }

  /// Encodes [warning] as a `run_acknowledgements` row for [runId].
  ///
  /// `component_id` is `NULL` only for [ArchivedDependencyWarning], the one
  /// kind with no component of its own — see the schema comment on
  /// `run_acknowledgements` for why the table has no single `PRIMARY KEY`
  /// covering that nullable column.
  Map<String, Object?> _acknowledgementRow(
    String runId,
    ProductionWarning warning,
  ) => switch (warning) {
    ManualComponentWarning(:final recipeId, :final componentId) =>
      <String, Object?>{
        'run_id': runId,
        'warning_kind': 'manual_component',
        'recipe_id': recipeId,
        'component_id': componentId,
      },
    RoundingAdjustedWarning(:final recipeId, :final componentId) =>
      <String, Object?>{
        'run_id': runId,
        'warning_kind': 'rounding_adjusted',
        'recipe_id': recipeId,
        'component_id': componentId,
      },
    ArchivedDependencyWarning(:final recipeId) => <String, Object?>{
      'run_id': runId,
      'warning_kind': 'archived_dependency',
      'recipe_id': recipeId,
      'component_id': null,
    },
  };

  /// Rebuilds the [ProductionWarning] a `run_acknowledgements` row encodes.
  ///
  /// Mirrors `result_codec.dart`'s `_warningToJson`/`_warningFromJson` kind
  /// strings, duplicated rather than shared for the same reason
  /// `result_codec.dart` duplicates `SqfliteRecipeRepository`'s row mapping.
  /// An unrecognised `warning_kind`, or a `NULL` `component_id` on a kind
  /// that requires one, is a corrupt row: silently dropping the
  /// acknowledgement would make an already-accepted warning block the run
  /// again, and guessing a component id would attach it to the wrong line.
  ProductionWarning _warningFromRow(Map<String, Object?> row) {
    final kind = row['warning_kind'];
    final recipeId = row['recipe_id']! as String;
    final componentId = row['component_id'];
    return switch (kind) {
      'manual_component' when componentId is String => ManualComponentWarning(
        recipeId,
        componentId,
      ),
      'rounding_adjusted' when componentId is String => RoundingAdjustedWarning(
        recipeId,
        componentId,
      ),
      'archived_dependency' => ArchivedDependencyWarning(recipeId),
      _ => throw CorruptDatabaseError(
        'unrecognised acknowledgement row: warning_kind=$kind, '
        'component_id=$componentId',
      ),
    };
  }

  /// Encodes an operator override [value] for [key] on [runId] as a
  /// `run_overrides` row.
  Map<String, Object?> _overrideRow(
    String runId,
    OverrideKey key,
    Quantity value,
  ) {
    final (recipeId, componentId) = key;
    return <String, Object?>{
      'run_id': runId,
      'recipe_id': recipeId,
      'component_id': componentId,
      ...quantityToColumns(value, 'override'),
    };
  }
}
