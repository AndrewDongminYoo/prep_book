import 'package:prep_book/persistence/schema/v1.dart';
import 'package:sqflite/sqflite.dart';

/// The schema version this build writes and expects.
const currentSchemaVersion = 1;

/// Upgrades keyed by the version they produce. Applied in ascending order, so
/// version N is reached by running every entry from 2 through N.
///
/// Empty at version 1. The harness that exercises this map exists from the
/// first version deliberately: writing it alongside version 2 would mean
/// building the upgrade and its means of verification at the same time.
const schemaUpgrades = <int, List<String>>{};

/// Runs every upgrade that takes a database from version [from] to [to], in
/// ascending order of the version it produces.
///
/// This is what [openPrepBookDatabase] hands sqflite as its `onUpgrade`
/// handler, and it is a named function rather than a closure so a test can
/// drive it directly. At version 1 there is no stored version between 0 and
/// the current one, so sqflite calls `onCreate` and never this — without a
/// seam the whole upgrade path would ship unexercised, which is the failure
/// the specification asks the harness to prevent by existing from the first
/// version.
///
/// [upgrades] defaults to the real [schemaUpgrades]. A test substitutes a
/// map of its own, so the loop, the ordering, and the gap between two
/// registered versions are all exercised against a real database before the
/// first genuine upgrade is written.
Future<void> applySchemaUpgrades(
  DatabaseExecutor db,
  int from,
  int to, {
  Map<int, List<String>> upgrades = schemaUpgrades,
}) async {
  for (var version = from + 1; version <= to; version++) {
    for (final statement in upgrades[version] ?? const <String>[]) {
      await db.execute(statement);
    }
  }
}

/// Creates the version 1 schema in [db] and then brings it up to [version].
///
/// This is what [openPrepBookDatabase] hands sqflite as its `onCreate`
/// handler, and it is a named function rather than a closure for the same
/// reason [applySchemaUpgrades] is: so a test can drive it directly.
///
/// The [applySchemaUpgrades] call is what makes the create path correct at
/// any version above 1. sqflite calls `onCreate` — not `onUpgrade` — for a
/// brand-new database, and then stamps it at the version the open requested.
/// A create that ran only [schemaV1Statements] would therefore leave a fresh
/// installation holding the version 1 tables while recorded as being at the
/// current version, and every later open would consider it up to date. The
/// gap surfaces at runtime as a missing table or column rather than at open,
/// which is the failure with no signal attached to it.
///
/// At version 1 the call does nothing, because [applySchemaUpgrades]'s loop
/// starts at `from + 1`.
///
/// [upgrades] defaults to the real [schemaUpgrades], and exists for the same
/// reason [applySchemaUpgrades]'s does. [openPrepBookDatabase] hardcodes
/// `version: currentSchemaVersion`, so nothing can force a create above
/// version 1 through it, and the call below would ship unexercised until the
/// first genuine upgrade — the untested seam the harness exists to prevent.
/// A test substitutes a map of its own and asserts that what a fake version
/// 2 adds is really present in the newly created database.
Future<void> createPrepBookSchema(
  DatabaseExecutor db,
  int version, {
  Map<int, List<String>> upgrades = schemaUpgrades,
}) async {
  for (final statement in schemaV1Statements) {
    await db.execute(statement);
  }
  await applySchemaUpgrades(db, 1, version, upgrades: upgrades);
}

/// Opens the database at [path], creating or upgrading it as needed.
///
/// Takes a path rather than resolving one so that a candidate database can be
/// opened somewhere other than the live location. Validate-then-swap restore
/// is out of scope here and depends on exactly that.
///
/// [factory] exists for tests, which pass the FFI factory; production passes
/// nothing and gets the platform channel.
Future<Database> openPrepBookDatabase({
  required String path,
  DatabaseFactory? factory,
}) {
  final open = factory ?? databaseFactory;
  return open.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: currentSchemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: createPrepBookSchema,
      onUpgrade: applySchemaUpgrades,
    ),
  );
}
