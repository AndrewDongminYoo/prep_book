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
      onCreate: (db, version) async {
        for (final statement in schemaV1Statements) {
          await db.execute(statement);
        }
      },
      // coverage:ignore-start
      // Unreachable while currentSchemaVersion is 1: sqflite calls onCreate,
      // never onUpgrade, for a brand-new (version 0) database, and no stored
      // version can sit strictly between 0 and 1. This becomes reachable
      // once schemaUpgrades gets its first entry (schema version 2) — delete
      // these two markers in that same change and cover this with a real
      // upgrade test instead.
      onUpgrade: (db, from, to) async {
        for (var version = from + 1; version <= to; version++) {
          for (final statement in schemaUpgrades[version] ?? const <String>[]) {
            await db.execute(statement);
          }
        }
      },
      // coverage:ignore-end
    ),
  );
}
