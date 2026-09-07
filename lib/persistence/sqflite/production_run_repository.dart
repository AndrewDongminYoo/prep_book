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
      // `id` breaks a tie rather than leaving one. Two runs saved within
      // the same millisecond carry the same `created_at`, and an ORDER BY
      // that does not distinguish them lets SQLite return them in any
      // order — and in a different one between two queries, so the same
      // history list could reorder under the operator. The direction is
      // arbitrary; being settled is not.
      orderBy: 'created_at DESC, id ASC',
    );
    return rows.map(_summaryFromRow).toList();
  }

  /// Rebuilds the [ProductionRunSummary] a `production_runs` row holds.
  ///
  /// Guarded against a wrong-typed or unparseable column the same way, and
  /// for the same reason, as `SqfliteRecipeRepository._recipeFromRow`:
  /// SQLite applies affinity rather than a strict type, so a BLOB in a
  /// `TEXT` column and a non-numeric string in an `INTEGER` one both reach
  /// the casts below and would otherwise throw a bare `TypeError` naming no
  /// row.
  ProductionRunSummary _summaryFromRow(Map<String, Object?> row) {
    try {
      return ProductionRunSummary(
        id: row['id']! as String,
        recipeId: row['recipe_id']! as String,
        recipeRevision: row['recipe_revision']! as int,
        targetYield: quantityFromColumns(
          row,
          'target',
          rowLabel: 'production_runs row ${row['id']}',
        ),
        createdAt: DateTime.parse(row['created_at']! as String),
      );
      // A wrong-typed column is a corrupt row, not a programmer bug, so its
      // `TypeError` is caught rather than left to escape.
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      throw CorruptDatabaseError(
        'production_runs row ${row['id']} holds a column of the wrong type: '
        '$error',
      );
    } on FormatException catch (error) {
      // Reached by `DateTime.parse` on a `created_at` that is not an ISO
      // 8601 instant.
      throw CorruptDatabaseError(
        'production_runs row ${row['id']} has an unparseable column: $error',
      );
    }
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

    // Only the two columns this method reads itself are wrapped. Everything
    // else it goes on to call — `decodeRunPayload`, `quantityFromColumns`,
    // `_acknowledgementsFor`, `_overridesFor` — already names its own row in
    // a [CorruptDatabaseError], and catching those here would relabel a
    // corrupt acknowledgement or override as a corrupt `production_runs` row.
    final String resultJson;
    final DateTime createdAt;
    try {
      resultJson = row['result_json']! as String;
      createdAt = DateTime.parse(row['created_at']! as String);
      // A wrong-typed column is a corrupt row, not a programmer bug, so its
      // `TypeError` is caught rather than left to escape.
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      throw CorruptDatabaseError(
        'production_runs row $id holds a column of the wrong type: $error',
      );
    } on FormatException catch (error) {
      throw CorruptDatabaseError(
        'production_runs row $id has an unparseable column: $error',
      );
    }

    final payload = decodeRunPayload(
      resultJson,
      rowLabel: 'production_runs row $id',
    );
    final acknowledgedWarnings = await _acknowledgementsFor(id);
    final overrides = await _overridesFor(id);

    return ProductionRun(
      id: id,
      createdAt: createdAt,
      recipe: payload.recipe,
      dependencySnapshot: payload.dependencySnapshot,
      targetYield: quantityFromColumns(
        row,
        'target',
        rowLabel: 'production_runs row $id',
      ),
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
      // Normalized before serializing, because [listSummaries] orders on
      // this column as text. `toIso8601String` emits a trailing `Z` only
      // for a UTC instant, so a mix of local and UTC writers would sort
      // '…T21:00:00.000Z' after '…T21:00:00.000' and put the history out of
      // order — and a naive value already written cannot be assigned an
      // offset afterwards. [_summaryFromRow] and [findById] read it back
      // unchanged and rely on every stored value being UTC.
      'created_at': run.createdAt.toUtc().toIso8601String(),
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
  ) => _db.insert(
    'run_acknowledgements',
    _acknowledgementRow(runId, warning),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<void> recordOverride(String runId, OverrideKey key, Quantity value) =>
      _db.insert(
        'run_overrides',
        _overrideRow(runId, key, value),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

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
        _overrideKeyFromRow(row): quantityFromColumns(
          row,
          'override',
          rowLabel: _overrideLabel(row),
        ),
    };
  }

  /// Identifies a `run_overrides` row by its three key columns.
  ///
  /// Shared by [_overrideKeyFromRow] and the [quantityFromColumns] call
  /// beside it, so a row that fails on its stored amount is named the same
  /// way as one that fails on its key. Reads the raw values rather than the
  /// casts, because the label has to survive the corruption it describes.
  String _overrideLabel(Map<String, Object?> row) =>
      'run_overrides row for run ${row['run_id']} recipe '
      '${row['recipe_id']} component ${row['component_id']}';

  /// Rebuilds the [OverrideKey] a `run_overrides` row is stored under.
  ///
  /// Read on [findById]'s own call path, so an unguarded cast here would
  /// surface a bare `TypeError` out of the one method whose every other
  /// failure mode names its row.
  OverrideKey _overrideKeyFromRow(Map<String, Object?> row) {
    try {
      return (row['recipe_id']! as String, row['component_id']! as String);
      // A wrong-typed column is a corrupt row, not a programmer bug, so its
      // `TypeError` is caught rather than left to escape.
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      throw CorruptDatabaseError(
        '${_overrideLabel(row)} holds a column of the wrong type: $error',
      );
    }
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
    final rowLabel = _acknowledgementLabel(row);
    try {
      final kind = row['warning_kind'];
      final recipeId = row['recipe_id']! as String;
      final componentId = row['component_id'];
      return switch (kind) {
        'manual_component' when componentId is String => ManualComponentWarning(
          recipeId,
          componentId,
        ),
        'rounding_adjusted' when componentId is String =>
          RoundingAdjustedWarning(recipeId, componentId),
        'archived_dependency' => ArchivedDependencyWarning(recipeId),
        _ => throw CorruptDatabaseError(
          'unrecognised acknowledgement in $rowLabel: warning_kind=$kind, '
          'component_id=$componentId',
        ),
      };
      // A wrong-typed column is a corrupt row, not a programmer bug, so its
      // `TypeError` is caught rather than left to escape. Read on
      // [findById]'s own call path, like [_overrideKeyFromRow].
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      throw CorruptDatabaseError(
        '$rowLabel holds a column of the wrong type: $error',
      );
    }
  }

  /// Identifies a `run_acknowledgements` row by the run that owns it.
  ///
  /// Shared by [_warningFromRow]'s two failures, so an unrecognised kind is
  /// named the same way as a wrong-typed column. The run id is what makes
  /// either message actionable: `warning_kind` and `component_id` repeat
  /// across every run in the table, so they identify no row on their own.
  String _acknowledgementLabel(Map<String, Object?> row) =>
      'run_acknowledgements row for run ${row['run_id']}';

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
