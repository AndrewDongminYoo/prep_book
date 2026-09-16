import 'package:prep_book/persistence/schema/v1.dart';
import 'package:prep_book/persistence/sqflite/result_codec.dart';
import 'package:sqflite/sqflite.dart';

/// The version 2 `production_runs` declaration.
///
/// The two appended columns are summary metadata from the immutable payload.
/// The defaults let SQLite add both `NOT NULL` columns to a populated version
/// 1 table before [backfillProductionRunSummaryMetadata] replaces them.
const _productionRunsV2 = '''
CREATE TABLE production_runs (
  id                      TEXT PRIMARY KEY,
  recipe_id               TEXT NOT NULL,
  recipe_revision         INTEGER NOT NULL,
  target_numerator        TEXT NOT NULL,
  target_denominator      TEXT NOT NULL,
  target_unit             TEXT NOT NULL,
  created_at              TEXT NOT NULL,
  result_json             TEXT NOT NULL,
  recipe_name             TEXT NOT NULL DEFAULT '',
  blocking_warning_count  INTEGER NOT NULL DEFAULT 0
    CHECK (blocking_warning_count >= 0)
)''';

/// The exact application catalog at schema version 2.
///
/// Version 2 changes only the fourth version 1 declaration, the
/// `production_runs` table. Keeping the other declarations from version 1
/// means fresh creation and exact validation share their unchanged source.
final schemaV2Statements = <String>[
  ...schemaV1Statements.take(3),
  _productionRunsV2,
  ...schemaV1Statements.skip(4),
];

/// The DDL that upgrades a version 1 catalog to version 2.
const schemaV2UpgradeStatements = <String>[
  "ALTER TABLE production_runs ADD COLUMN recipe_name TEXT NOT NULL DEFAULT ''",
  'ALTER TABLE production_runs ADD COLUMN blocking_warning_count INTEGER NOT NULL DEFAULT 0 CHECK (blocking_warning_count >= 0)',
];

/// Backfills summary metadata from each version 1 run payload.
///
/// The existing codec validates the complete payload before either value is
/// written. A corrupt payload therefore aborts the upgrade instead of leaving
/// a current-version database with metadata that cannot identify its source.
Future<void> backfillProductionRunSummaryMetadata(DatabaseExecutor db) async {
  final rows = await db.query(
    'production_runs',
    columns: ['id', 'result_json'],
  );
  for (final row in rows) {
    final id = row['id']! as String;
    final payload = decodeRunPayload(
      row['result_json']! as String,
      rowLabel: 'production_runs row $id',
    );
    final blockingWarningCount = payload.result.warnings
        .where((warning) => warning.isBlocking)
        .length;
    final changed = await db.update(
      'production_runs',
      <String, Object?>{
        'recipe_name': payload.recipe.name,
        'blocking_warning_count': blockingWarningCount,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changed != 1) {
      throw StateError('production_runs row $id disappeared during upgrade');
    }
  }
}
