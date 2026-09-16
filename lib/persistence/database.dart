import 'package:prep_book/persistence/schema/v1.dart';
import 'package:prep_book/persistence/schema/v2.dart';
import 'package:sqflite/sqflite.dart';

/// The schema version this build writes and expects.
const currentSchemaVersion = 2;

/// Upgrades keyed by the version they produce. Applied in ascending order, so
/// version N is reached by running every entry from 2 through N.
///
const schemaUpgrades = <int, List<String>>{2: schemaV2UpgradeStatements};

/// A data migration that runs after one schema version's DDL.
typedef SchemaBackfill = Future<void> Function(DatabaseExecutor db);

/// Backfills keyed by the version whose DDL must run first.
const schemaUpgradeBackfills = <int, SchemaBackfill>{
  2: backfillProductionRunSummaryMetadata,
};

/// Runs every upgrade that takes a database from version [from] to [to], in ascending order of the version it produces.
///
/// This is what [openPrepBookDatabase] hands sqflite as its `onUpgrade` handler, and it is a named function rather than a closure so tests can drive the real upgrade path directly.
///
/// [upgrades] and [backfills] default to the production migration contract.
/// Tests may substitute them to exercise ordering and missing-version behavior independently from a specific schema change.
Future<void> applySchemaUpgrades(
  DatabaseExecutor db,
  int from,
  int to, {
  Map<int, List<String>> upgrades = schemaUpgrades,
  Map<int, SchemaBackfill> backfills = schemaUpgradeBackfills,
}) async {
  for (var version = from + 1; version <= to; version++) {
    for (final statement in upgrades[version] ?? const <String>[]) {
      await db.execute(statement);
    }
    await backfills[version]?.call(db);
  }
}

/// Creates the version 1 schema in [db] and then brings it up to [version].
///
/// This is what [openPrepBookDatabase] hands sqflite as its `onCreate` handler, and it is a named function rather than a closure for the same reason [applySchemaUpgrades] is: so tests can drive it directly.
///
/// The [applySchemaUpgrades] call keeps fresh creation and incremental upgrades on the same schema path.
/// sqflite calls `onCreate` instead of `onUpgrade` for a brand-new database and then stamps it at the requested version, so creating only [schemaV1Statements] would leave a fresh database with an obsolete catalog recorded as current.
///
/// At version 1 the call does nothing because [applySchemaUpgrades]'s loop starts at `from + 1`.
///
/// [upgrades] and [backfills] exist for the same test seam as the corresponding parameters on [applySchemaUpgrades].
Future<void> createPrepBookSchema(
  DatabaseExecutor db,
  int version, {
  Map<int, List<String>> upgrades = schemaUpgrades,
  Map<int, SchemaBackfill> backfills = schemaUpgradeBackfills,
}) async {
  for (final statement in schemaV1Statements) {
    await db.execute(statement);
  }
  await applySchemaUpgrades(
    db,
    1,
    version,
    upgrades: upgrades,
    backfills: backfills,
  );
}

/// Verifies that [db] has exactly the application schema for this build.
///
/// SQLite integrity and foreign-key checks do not prove that tables, columns,
/// constraints, indexes, or triggers match the schema the repositories expect.
/// Portable restore therefore compares the stored catalog with the same DDL
/// that creates a new database. Platform-maintained SQLite objects are ignored.
Future<void> validatePrepBookSchema(DatabaseExecutor db) async {
  final expected = <String, ({String type, String sql})>{};
  final declaration = RegExp(
    '^CREATE (?:UNIQUE )?(TABLE|INDEX) ([^ (]+)',
    caseSensitive: false,
  );
  for (final statement in schemaV2Statements) {
    final sql = _normalizeSchemaSql(statement);
    final match = declaration.firstMatch(sql)!;
    expected[match.group(2)!] = (type: match.group(1)!.toLowerCase(), sql: sql);
  }

  final rows = await db.query(
    'sqlite_master',
    columns: ['type', 'name', 'sql'],
    where: "name NOT LIKE 'sqlite_%'",
  );
  var applicationObjectCount = 0;
  for (final row in rows) {
    final name = row['name'];
    final type = row['type'];
    final sql = row['sql'];
    if (name is! String || type is! String || sql is! String) {
      throw const FormatException('The SQLite schema catalog is invalid.');
    }
    if (name == 'android_metadata') {
      if (type != 'table' ||
          _normalizeSchemaSql(sql) !=
              'create table android_metadata (locale text)') {
        throw const FormatException(
          'The Android SQLite metadata object is invalid.',
        );
      }
      continue;
    }
    applicationObjectCount++;
    final expectedObject = expected[name];
    if (expectedObject == null ||
        type != expectedObject.type ||
        _normalizeSchemaSql(sql) != expectedObject.sql) {
      throw FormatException('The SQLite schema object $name is invalid.');
    }
  }
  if (applicationObjectCount != expected.length) {
    throw const FormatException('The SQLite schema object count is invalid.');
  }
}

String _normalizeSchemaSql(String sql) => sql
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ')
    .replaceAll(RegExp(r'\s*,\s*'), ', ')
    .replaceAll(RegExp(r'\s*\)'), ')')
    .toLowerCase();

/// Opens the database at [path], creating or upgrading it as needed.
///
/// Takes a path rather than resolving one so that a candidate database can be
/// opened somewhere other than the live location. Validate-then-swap restore
/// is out of scope here and depends on exactly that.
///
/// [factory] exists for tests, which pass the FFI factory; production passes
/// nothing and gets the platform channel.
///
/// [singleInstance] defaults to sqflite's shared-handle behavior. Candidate
/// validation disables it so closing a temporary handle cannot close or reuse
/// the live database connection.
Future<Database> openPrepBookDatabase({
  required String path,
  DatabaseFactory? factory,
  bool singleInstance = true,
}) {
  final open = factory ?? databaseFactory;
  return open.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: currentSchemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: createPrepBookSchema,
      onUpgrade: applySchemaUpgrades,
      singleInstance: singleInstance,
    ),
  );
}
