# Persistence Layer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store the recipe library and production history in a local SQLite database behind repository interfaces the application layer can use, without the domain layer learning that storage exists.

**Architecture:** `sqflite` over a database opened by caller-supplied path, with `PRAGMA user_version` and a sequential upgrade list. Quantities are stored as numerator and denominator `TEXT` pairs because a `Rational` holds `BigInt` values. A `ProductionRun` is written once as metadata columns plus a `result_json` blob; only its acknowledgements and overrides live in separate, growable tables.

**Tech Stack:** Dart 3.13+, `sqflite` for the runtime, `sqflite_common_ffi` for tests, the existing `decimal`/`rational` pair, `flutter_test`, `very_good_analysis` lints.

**Spec:** `docs/specs/2026-09-07-persistence-layer.md`

## Global Constraints

- The domain stays pure. No file under `lib/domain/` may change in this plan. `package:sqflite` is already in the purity guard's denylist, and Task 1 must not touch that guard.
- Binary floating point is prohibited in anything that carries a quantity. `double` must not appear in `lib/persistence/` or its tests.
- CI requires 100 percent line coverage (`very_good test --coverage --min-coverage 100`). Every error branch written in a task needs a test in the same task.
- Analysis must stay clean under `flutter analyze` with `very_good_analysis` ^10.3.0.
- Every commit passes the `trunk fmt` pre-commit hook. Stage with `git add <paths>`, then commit the index. Never scope a commit with a pathspec.
- Commit subjects are conventional commits in English. No AI attribution trailers, no session URLs.
- Korean is not used in this layer's identifiers or comments; persistence has no user-facing strings.
- "Schema upgrade" means a change to the database shape. This project's "Migration" unit is a spreadsheet importer and is not in scope here; do not use the word for schema work.

## Package introduction, stated once

Two packages arrive together in Task 1.

`sqflite` reaches SQLite through a platform channel and therefore does not run under `flutter test` at all.
`sqflite_common_ffi` provides the same API over a local library and is the only way this layer can be tested, which is what makes them a runtime and its harness rather than two independent choices.

Add them with `flutter pub add sqflite` and `flutter pub add dev:sqflite_common_ffi`, and commit `pubspec.lock` in the same commit as `pubspec.yaml`.

## File Structure

```log
lib/persistence/
├── persistence.dart                barrel; exports interfaces and the SQLite factory
├── repositories.dart               the three interfaces plus ProductionRunSummary
├── database.dart                   openDatabase by path, user_version, upgrades
├── errors.dart                     CorruptDatabaseError
├── schema/
│   └── v1.dart                     the CREATE statements for version 1
└── sqflite/
    ├── quantity_columns.dart       Quantity/ScaledQuantity <-> column maps
    ├── result_codec.dart           ProductionResult <-> JSON
    ├── ingredient_repository.dart
    ├── recipe_repository.dart
    └── production_run_repository.dart

test/persistence/
├── database_test.dart
├── schema_upgrade_test.dart
├── quantity_columns_test.dart
├── result_codec_test.dart
├── ingredient_repository_test.dart
├── recipe_repository_test.dart
├── production_run_repository_test.dart
└── failure_paths_test.dart
```

`test/persistence/` is deliberately not under `test/domain/`, so the domain purity scans do not reach it.

---

### Task 1: Database, schema version 1, and the upgrade harness

**Files:**

- Modify: `pubspec.yaml`, `pubspec.lock`
- Create: `lib/persistence/database.dart`, `lib/persistence/schema/v1.dart`
- Test: `test/persistence/database_test.dart`, `test/persistence/schema_upgrade_test.dart`

**Interfaces:**

- Produces: `Future<Database> openPrepBookDatabase({required String path, DatabaseFactory? factory})`, `const int currentSchemaVersion`, `const List<String> schemaV1Statements`, and `const Map<int, List<String>> schemaUpgrades`.

- [ ] **Step 1: Add the packages**

```bash
cd <worktree>
flutter pub add sqflite
flutter pub add dev:sqflite_common_ffi
```

- [ ] **Step 2: Write the failing test for opening at version 1**

```dart
// test/persistence/database_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('a new database opens at the current schema version', () async {
    final db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    expect(await db.getVersion(), currentSchemaVersion);
  });

  test('every version 1 table exists', () async {
    final db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    addTearDown(db.close);

    final rows = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: 'type = ?',
      whereArgs: ['table'],
    );
    final names = rows.map((row) => row['name']! as String).toSet();

    expect(names, containsAll(<String>[
      'ingredients',
      'recipes',
      'recipe_components',
      'production_runs',
      'run_acknowledgements',
      'run_overrides',
    ]));
  });
}
```

- [ ] **Step 3: Run the tests and watch them fail**

Run: `flutter test test/persistence/database_test.dart`
Expected: FAIL, `Target of URI doesn't exist: 'package:prep_book/persistence/database.dart'`.

- [ ] **Step 4: Write the version 1 statements**

```dart
// lib/persistence/schema/v1.dart
/// The tables as of schema version 1.
///
/// A quantity is three columns (numerator, denominator, unit symbol) because a
/// `Rational` holds `BigInt` values that SQLite's 64-bit `INTEGER` cannot be
/// relied on to store. A scaled quantity is five: the exact pair, the displayed
/// pair, and the shared unit.
const schemaV1Statements = <String>[
  '''
CREATE TABLE ingredients (
  id                  TEXT PRIMARY KEY,
  name                TEXT NOT NULL,
  default_unit_symbol TEXT NOT NULL,
  category            TEXT
)''',
  '''
CREATE TABLE recipes (
  id                     TEXT NOT NULL,
  revision               INTEGER NOT NULL,
  name                   TEXT NOT NULL,
  category               TEXT,
  base_yield_numerator   TEXT NOT NULL,
  base_yield_denominator TEXT NOT NULL,
  base_yield_unit        TEXT NOT NULL,
  max_batch_numerator    TEXT,
  max_batch_denominator  TEXT,
  max_batch_unit         TEXT,
  preparation_notes      TEXT NOT NULL,
  modified_at            TEXT NOT NULL,
  is_archived            INTEGER NOT NULL,
  PRIMARY KEY (id, revision)
)''',
  '''
CREATE TABLE recipe_components (
  recipe_id            TEXT NOT NULL,
  recipe_revision      INTEGER NOT NULL,
  component_id         TEXT NOT NULL,
  target_kind          TEXT NOT NULL,
  target_id            TEXT NOT NULL,
  base_numerator       TEXT,
  base_denominator     TEXT,
  base_unit            TEXT,
  behavior             TEXT NOT NULL,
  rounding_increment   TEXT,
  note                 TEXT,
  display_order        INTEGER NOT NULL,
  PRIMARY KEY (recipe_id, recipe_revision, component_id),
  FOREIGN KEY (recipe_id, recipe_revision)
    REFERENCES recipes (id, revision) ON DELETE CASCADE
)''',
  '''
CREATE TABLE production_runs (
  id                    TEXT PRIMARY KEY,
  recipe_id             TEXT NOT NULL,
  recipe_revision       INTEGER NOT NULL,
  target_numerator      TEXT NOT NULL,
  target_denominator    TEXT NOT NULL,
  target_unit           TEXT NOT NULL,
  created_at            TEXT NOT NULL,
  result_json           TEXT NOT NULL
)''',
  '''
CREATE TABLE run_acknowledgements (
  run_id       TEXT NOT NULL,
  warning_kind TEXT NOT NULL,
  recipe_id    TEXT NOT NULL,
  component_id TEXT,
  PRIMARY KEY (run_id, warning_kind, recipe_id, component_id),
  FOREIGN KEY (run_id) REFERENCES production_runs (id) ON DELETE CASCADE
)''',
  '''
CREATE TABLE run_overrides (
  run_id       TEXT NOT NULL,
  recipe_id    TEXT NOT NULL,
  component_id TEXT NOT NULL,
  numerator    TEXT NOT NULL,
  denominator  TEXT NOT NULL,
  unit_symbol  TEXT NOT NULL,
  PRIMARY KEY (run_id, recipe_id, component_id),
  FOREIGN KEY (run_id) REFERENCES production_runs (id) ON DELETE CASCADE
)''',
  'CREATE INDEX idx_runs_recipe ON production_runs (recipe_id, recipe_revision)',
  'CREATE INDEX idx_runs_created ON production_runs (created_at DESC)',
];
```

Note the composite primary key on `run_acknowledgements` includes a nullable
`component_id`. SQLite treats NULLs as distinct in a primary key, so an
`ArchivedDependencyWarning` row cannot collide with itself; Task 7 tests that a
repeated acknowledgement does not duplicate.

- [ ] **Step 5: Write the database opener**

```dart
// lib/persistence/database.dart
import 'package:sqflite/sqflite.dart';

import 'schema/v1.dart';

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
      onUpgrade: (db, from, to) async {
        for (var version = from + 1; version <= to; version++) {
          for (final statement in schemaUpgrades[version] ?? const <String>[]) {
            await db.execute(statement);
          }
        }
      },
    ),
  );
}
```

- [ ] **Step 6: Run the tests and watch them pass**

Run: `flutter test test/persistence/database_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 7: Write the upgrade harness test**

```dart
// test/persistence/schema_upgrade_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('every registered upgrade is reachable from version 1', () {
    for (final version in schemaUpgrades.keys) {
      expect(version, greaterThan(1));
      expect(version, lessThanOrEqualTo(currentSchemaVersion));
    }
  });

  test('applying the upgrade path preserves existing rows', () async {
    final path = inMemoryDatabasePath;
    final db = await openPrepBookDatabase(
      path: path,
      factory: databaseFactoryFfi,
    );
    await db.insert('ingredients', <String, Object?>{
      'id': 'flour',
      'name': 'Flour',
      'default_unit_symbol': 'g',
      'category': null,
    });

    // Re-running the opener against an already-current database must be a
    // no-op rather than a re-create, which is what a failed upgrade path
    // would look like.
    final reopened = await openPrepBookDatabase(
      path: path,
      factory: databaseFactoryFfi,
    );
    addTearDown(reopened.close);

    final rows = await reopened.query('ingredients');
    expect(rows, hasLength(1));
    expect(rows.single['id'], 'flour');
    expect(await reopened.getVersion(), currentSchemaVersion);
  });
}
```

- [ ] **Step 8: Run it and confirm it passes**

Run: `flutter test test/persistence/schema_upgrade_test.dart`
Expected: PASS, 2 tests.

- [ ] **Step 9: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/persistence/database.dart lib/persistence/schema/v1.dart test/persistence/database_test.dart test/persistence/schema_upgrade_test.dart
git commit -m "feat(persistence): open a versioned SQLite database"
```

---

### Task 2: Quantity and unit column mapping

**Files:**

- Create: `lib/persistence/sqflite/quantity_columns.dart`, `lib/persistence/errors.dart`
- Test: `test/persistence/quantity_columns_test.dart`

**Interfaces:**

- Consumes: nothing from Task 1.
- Produces: `Map<String, Object?> quantityToColumns(Quantity q, String prefix)`, `Quantity quantityFromColumns(Map<String, Object?> row, String prefix)`, `Map<String, Object?> scaledToColumns(ScaledQuantity q, String prefix)`, `ScaledQuantity scaledFromColumns(Map<String, Object?> row, String prefix)`, `Unit unitBySymbol(String symbol)`, and `final class CorruptDatabaseError implements Exception`.

- [ ] **Step 1: Write the failing round-trip test**

```dart
// test/persistence/quantity_columns_test.dart
import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';

void main() {
  test('a non-terminating quantity round-trips exactly', () {
    final third = Quantity.fromDecimal(Decimal.one, Unit.gram) /
        Decimal.fromInt(3).toRational();
    final columns = quantityToColumns(third, 'base');
    expect(columns['base_numerator'], '1');
    expect(columns['base_denominator'], '3');

    expect(quantityFromColumns(columns, 'base'), third);
  });

  test('an unknown unit symbol is a corrupt database, not a new unit', () {
    expect(
      () => unitBySymbol('parsec'),
      throwsA(isA<CorruptDatabaseError>()),
    );
  });
}
```

The first test's construction of one third must match whatever the domain
actually exposes; read `lib/domain/units/quantity.dart` before writing it and
use the real API rather than the shape above if they differ. The assertion that
matters is that `'1'` and `'3'` come back, not how the value was built.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/persistence/quantity_columns_test.dart`
Expected: FAIL on the missing URIs.

- [ ] **Step 3: Write the error type**

```dart
// lib/persistence/errors.dart
/// A stored row cannot be turned back into a domain object.
///
/// Always names the row. Never repaired by guessing a value, because a guess
/// here would put an invented quantity into a production record.
final class CorruptDatabaseError implements Exception {
  const CorruptDatabaseError(this.message);

  final String message;

  @override
  String toString() => 'CorruptDatabaseError: $message';
}
```

- [ ] **Step 4: Write the mapping**

```dart
// lib/persistence/sqflite/quantity_columns.dart
import 'package:prep_book/domain/domain.dart';
import 'package:rational/rational.dart';

import '../errors.dart';

/// Recovers the domain `Unit` for a stored symbol.
///
/// `Unit` has a private constructor and a fixed table, so a symbol that is not
/// in it cannot be honoured. That is a corrupt row, not a unit to invent.
Unit unitBySymbol(String symbol) {
  for (final unit in Unit.all) {
    if (unit.symbol == symbol) return unit;
  }
  throw CorruptDatabaseError('unknown unit symbol: $symbol');
}

Map<String, Object?> quantityToColumns(Quantity quantity, String prefix) =>
    <String, Object?>{
      '${prefix}_numerator': quantity.amount.numerator.toString(),
      '${prefix}_denominator': quantity.amount.denominator.toString(),
      '${prefix}_unit': quantity.unit.symbol,
    };

Quantity quantityFromColumns(Map<String, Object?> row, String prefix) {
  final numerator = row['${prefix}_numerator'];
  final denominator = row['${prefix}_denominator'];
  final symbol = row['${prefix}_unit'];
  if (numerator is! String || denominator is! String || symbol is! String) {
    throw CorruptDatabaseError('incomplete quantity in column group $prefix');
  }
  return Quantity(
    Rational(BigInt.parse(numerator), BigInt.parse(denominator)),
    unitBySymbol(symbol),
  );
}
```

`Unit.all` and the `Quantity` constructor above are the names this task
assumes. Read `lib/domain/units/unit.dart` and `quantity.dart` first; if the
domain exposes different names, use the real ones and keep the behaviour.

- [ ] **Step 5: Add the scaled-quantity pair**

```dart
Map<String, Object?> scaledToColumns(ScaledQuantity scaled, String prefix) =>
    <String, Object?>{
      '${prefix}_exact_numerator': scaled.exact.amount.numerator.toString(),
      '${prefix}_exact_denominator': scaled.exact.amount.denominator.toString(),
      '${prefix}_displayed_numerator':
          scaled.displayed.amount.numerator.toString(),
      '${prefix}_displayed_denominator':
          scaled.displayed.amount.denominator.toString(),
      '${prefix}_unit': scaled.exact.unit.symbol,
    };
```

Write `scaledFromColumns` as its mirror, throwing `CorruptDatabaseError` on any
column that is not a `String`, and add a round-trip test for a scaled quantity
whose exact and displayed values differ.

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/persistence/quantity_columns_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/persistence/errors.dart lib/persistence/sqflite/quantity_columns.dart test/persistence/quantity_columns_test.dart
git commit -m "feat(persistence): map exact quantities to text column pairs"
```

---

### Task 3: Repository interfaces and the ingredient repository

**Files:**

- Create: `lib/persistence/repositories.dart`, `lib/persistence/sqflite/ingredient_repository.dart`, `lib/persistence/persistence.dart`
- Test: `test/persistence/ingredient_repository_test.dart`

**Interfaces:**

- Consumes: `openPrepBookDatabase`, `unitBySymbol`.
- Produces: `abstract interface class IngredientRepository`, `abstract interface class RecipeRepository`, `abstract interface class ProductionRunRepository`, `final class ProductionRunSummary`, and `final class SqfliteIngredientRepository implements IngredientRepository`.

This task defines all three interfaces so later tasks implement against fixed
signatures, but implements only the first.

- [ ] **Step 1: Write the interfaces**

```dart
// lib/persistence/repositories.dart
import 'package:prep_book/domain/domain.dart';

abstract interface class IngredientRepository {
  Future<List<Ingredient>> listAll();
  Future<Ingredient?> findById(String id);
  Future<void> upsert(Ingredient ingredient);
  Future<void> delete(String id);
}

abstract interface class RecipeRepository {
  /// The highest revision of every recipe, archived ones included.
  Future<List<Recipe>> listLatestRevisions();
  Future<Recipe?> findRevision(String id, int revision);
  Future<Recipe?> findLatest(String id);

  /// Inserts [recipe] as a new revision. Never updates an existing one, so a
  /// stored production run keeps the revision it was computed against.
  Future<void> saveRevision(Recipe recipe);

  Future<void> setArchived(String id, {required bool isArchived});
}

/// Enough of a run to list it without deserializing its result.
final class ProductionRunSummary {
  const ProductionRunSummary({
    required this.id,
    required this.recipeId,
    required this.recipeRevision,
    required this.targetYield,
    required this.createdAt,
  });

  final String id;
  final String recipeId;
  final int recipeRevision;
  final Quantity targetYield;
  final DateTime createdAt;
}

abstract interface class ProductionRunRepository {
  /// Newest first.
  Future<List<ProductionRunSummary>> listSummaries();
  Future<ProductionRun?> findById(String id);

  /// Writes the run and the acknowledgement and override state it carries in
  /// one transaction.
  Future<void> save(ProductionRun run);

  Future<void> recordAcknowledgement(String runId, ProductionWarning warning);
  Future<void> recordOverride(String runId, OverrideKey key, Quantity value);
}
```

- [ ] **Step 2: Write the failing repository test**

```dart
// test/persistence/ingredient_repository_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:prep_book/persistence/sqflite/ingredient_repository.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late SqfliteIngredientRepository repository;

  setUp(() async {
    db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repository = SqfliteIngredientRepository(db);
  });

  tearDown(() => db.close());

  test('an ingredient round-trips', () async {
    const flour = Ingredient(id: 'flour', name: 'Flour', defaultUnit: Unit.gram);
    await repository.upsert(flour);

    expect(await repository.findById('flour'), flour);
  });

  test('a missing id reads as null rather than throwing', () async {
    expect(await repository.findById('absent'), isNull);
  });

  test('upsert replaces rather than duplicating', () async {
    const first = Ingredient(id: 'f', name: 'Flour', defaultUnit: Unit.gram);
    const renamed = Ingredient(id: 'f', name: 'Bread flour', defaultUnit: Unit.gram);
    await repository.upsert(first);
    await repository.upsert(renamed);

    expect(await repository.listAll(), hasLength(1));
    expect((await repository.findById('f'))!.name, 'Bread flour');
  });

  test('delete removes the row', () async {
    const flour = Ingredient(id: 'flour', name: 'Flour', defaultUnit: Unit.gram);
    await repository.upsert(flour);
    await repository.delete('flour');

    expect(await repository.listAll(), isEmpty);
  });
}
```

`Unit.gram` is assumed; use whatever `lib/domain/units/unit.dart` actually
names its gram constant.

- [ ] **Step 3: Run it and watch it fail**

Run: `flutter test test/persistence/ingredient_repository_test.dart`
Expected: FAIL on the missing repository URI.

- [ ] **Step 4: Implement the repository**

```dart
// lib/persistence/sqflite/ingredient_repository.dart
import 'package:prep_book/domain/domain.dart';
import 'package:sqflite/sqflite.dart';

import '../repositories.dart';
import 'quantity_columns.dart';

final class SqfliteIngredientRepository implements IngredientRepository {
  const SqfliteIngredientRepository(this._db);

  final Database _db;

  @override
  Future<List<Ingredient>> listAll() async {
    final rows = await _db.query('ingredients', orderBy: 'name');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Ingredient?> findById(String id) async {
    final rows = await _db.query(
      'ingredients',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.single);
  }

  @override
  Future<void> upsert(Ingredient ingredient) => _db.insert(
        'ingredients',
        <String, Object?>{
          'id': ingredient.id,
          'name': ingredient.name,
          'default_unit_symbol': ingredient.defaultUnit.symbol,
          'category': ingredient.category,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  @override
  Future<void> delete(String id) =>
      _db.delete('ingredients', where: 'id = ?', whereArgs: [id]);

  Ingredient _fromRow(Map<String, Object?> row) => Ingredient(
        id: row['id']! as String,
        name: row['name']! as String,
        defaultUnit: unitBySymbol(row['default_unit_symbol']! as String),
        category: row['category'] as String?,
      );
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/persistence/ingredient_repository_test.dart`
Expected: PASS, 4 tests.

- [ ] **Step 6: Add the barrel**

```dart
// lib/persistence/persistence.dart
export 'database.dart';
export 'errors.dart';
export 'repositories.dart';
export 'sqflite/ingredient_repository.dart';
```

Later tasks add their repositories to this list as they land.

- [ ] **Step 7: Commit**

```bash
git add lib/persistence/repositories.dart lib/persistence/persistence.dart lib/persistence/sqflite/ingredient_repository.dart test/persistence/ingredient_repository_test.dart
git commit -m "feat(persistence): add repository interfaces and ingredient storage"
```

---

### Task 4: Recipe repository with revisions

**Files:**

- Create: `lib/persistence/sqflite/recipe_repository.dart`
- Modify: `lib/persistence/persistence.dart`
- Test: `test/persistence/recipe_repository_test.dart`

**Interfaces:**

- Consumes: `RecipeRepository`, `quantityToColumns`, `quantityFromColumns`, `unitBySymbol`.
- Produces: `final class SqfliteRecipeRepository implements RecipeRepository`.

- [ ] **Step 1: Write the failing revision tests**

```dart
test('saving an edit creates a new revision and keeps the old one', () async {
  final first = buildRecipe(id: 'sourdough', revision: 1, name: 'Sourdough');
  final second = buildRecipe(id: 'sourdough', revision: 2, name: 'Sourdough v2');
  await repository.saveRevision(first);
  await repository.saveRevision(second);

  expect((await repository.findRevision('sourdough', 1))!.name, 'Sourdough');
  expect((await repository.findLatest('sourdough'))!.revision, 2);
  expect(await repository.listLatestRevisions(), hasLength(1));
});

test('components belong to their revision', () async {
  final one = buildRecipe(id: 'r', revision: 1, componentIds: ['flour']);
  final two = buildRecipe(id: 'r', revision: 2, componentIds: ['flour', 'salt']);
  await repository.saveRevision(one);
  await repository.saveRevision(two);

  expect((await repository.findRevision('r', 1))!.components, hasLength(1));
  expect((await repository.findRevision('r', 2))!.components, hasLength(2));
});

test('a failed component insert rolls back the recipe row', () async {
  final broken = buildRecipe(id: 'r', revision: 1, componentIds: ['a', 'a']);

  await expectLater(repository.saveRevision(broken), throwsA(anything));
  expect(await repository.findRevision('r', 1), isNull);
});
```

Write a `buildRecipe` helper in the test file that constructs a valid `Recipe`
through the domain's real factory, taking id, revision, name and component ids.
Read `lib/domain/recipe/recipe.dart` for the actual constructor. The duplicate
component id in the third test is what forces the primary-key violation; if the
domain rejects duplicates before persistence sees them, force the failure by
inserting a component row for a recipe revision that does not exist instead, so
the foreign key fires.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/persistence/recipe_repository_test.dart`
Expected: FAIL on the missing repository.

- [ ] **Step 3: Implement `saveRevision` inside a transaction**

```dart
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
        await txn.insert('recipe_components', _componentToRow(recipe, component));
      }
    });
```

`quantityToColumns` emits `base_yield_numerator`, `base_yield_denominator` and
`base_yield_unit` for the prefix `base_yield`, which match the version 1 column
names exactly. Keep them aligned; a rename in one place must be made in both.

- [ ] **Step 4: Implement the reads and `setArchived`**

Read a recipe by querying `recipes` for the `(id, revision)` pair, then
`recipe_components` ordered by `display_order`, and rebuild through the domain
factory so its validation runs on the way in. `findLatest` orders by `revision`
descending with `limit: 1`. `listLatestRevisions` groups by id and takes the
maximum revision. `setArchived` updates `is_archived` on every revision of the
id, because archiving is a property of the recipe rather than of one revision.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/persistence/recipe_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/persistence/sqflite/recipe_repository.dart lib/persistence/persistence.dart test/persistence/recipe_repository_test.dart
git commit -m "feat(persistence): store recipes as immutable revisions"
```

---

### Task 5: Production result JSON codec

**Files:**

- Create: `lib/persistence/sqflite/result_codec.dart`
- Test: `test/persistence/result_codec_test.dart`

**Interfaces:**

- Consumes: `CorruptDatabaseError`.
- Produces: `String encodeRunPayload(ProductionRun run)` and `RunPayload decodeRunPayload(String json)`, where `RunPayload` carries the `Recipe`, the `Map<String, Recipe>` dependency snapshot, and the `ProductionResult`.

The payload is everything about a run that never changes. Acknowledgements and
overrides are excluded on purpose; they live in their own tables because they
are the only fields `_copyWith` replaces.

- [ ] **Step 1: Write the failing round-trip test**

```dart
test('a run payload round-trips including a non-terminating quantity', () {
  final run = buildRunScaledByOneThird();
  final decoded = decodeRunPayload(encodeRunPayload(run));

  expect(decoded.recipe, run.recipe);
  expect(decoded.dependencySnapshot, run.dependencySnapshot);
  expect(decoded.result, run.result);
});

test('every warning kind survives the round trip', () {
  final run = buildRunWithAllWarningKinds();
  final decoded = decodeRunPayload(encodeRunPayload(run));

  expect(decoded.result.warnings, run.result.warnings);
});

test('malformed json is a corrupt database', () {
  expect(
    () => decodeRunPayload('{not json'),
    throwsA(isA<CorruptDatabaseError>()),
  );
});

test('an unknown warning kind is a corrupt database', () {
  expect(
    () => decodeRunPayload('{"warnings":[{"kind":"invented"}]}'),
    throwsA(isA<CorruptDatabaseError>()),
  );
});
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/persistence/result_codec_test.dart`
Expected: FAIL on the missing codec.

- [ ] **Step 3: Encode quantities as numerator and denominator strings**

Inside JSON, a `Quantity` is `{"n": "1", "d": "3", "u": "kg"}` and a
`ScaledQuantity` is `{"exact": {...}, "displayed": {...}}`. Do not write a
decimal string; the same non-terminating value that forced `Rational` in the
domain would be truncated here.

- [ ] **Step 4: Tag the warning hierarchy explicitly**

`ProductionWarning` is sealed, so switch over it exhaustively and write a
`kind` discriminator (`manual_component`, `rounding_adjusted`,
`archived_dependency`). On decode, an unrecognized `kind` throws
`CorruptDatabaseError` rather than being dropped, because a silently dropped
warning would make a blocked run look finalizable.

- [ ] **Step 5: Wrap every parse failure**

Catch `FormatException` and any cast failure from `jsonDecode` and rethrow as
`CorruptDatabaseError` naming what failed to parse.

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/persistence/result_codec_test.dart`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add lib/persistence/sqflite/result_codec.dart test/persistence/result_codec_test.dart
git commit -m "feat(persistence): encode production results without losing exactness"
```

---

### Task 6: Production run repository

**Files:**

- Create: `lib/persistence/sqflite/production_run_repository.dart`
- Modify: `lib/persistence/persistence.dart`
- Test: `test/persistence/production_run_repository_test.dart`

**Interfaces:**

- Consumes: `ProductionRunRepository`, `ProductionRunSummary`, `encodeRunPayload`, `decodeRunPayload`, `quantityToColumns`.
- Produces: `final class SqfliteProductionRunRepository implements ProductionRunRepository`.

- [ ] **Step 1: Write the failing tests, including the invariant**

```dart
test('a saved run round-trips', () async {
  final run = buildRun(id: 'run-1');
  await repository.save(run);

  final loaded = await repository.findById('run-1');
  expect(loaded!.result, run.result);
  expect(loaded.targetYield, run.targetYield);
});

test('editing the recipe afterwards does not change the stored run', () async {
  final run = buildRun(id: 'run-1', recipeId: 'r', recipeRevision: 1);
  await repository.save(run);
  await recipes.saveRevision(buildRecipe(id: 'r', revision: 2, name: 'Changed'));

  final loaded = await repository.findById('run-1');
  expect(loaded!.recipe.name, run.recipe.name);
  expect(loaded.recipe.revision, 1);
});

test('archiving the recipe does not change the stored run', () async {
  final run = buildRun(id: 'run-1', recipeId: 'r', recipeRevision: 1);
  await repository.save(run);
  await recipes.setArchived('r', isArchived: true);

  expect((await repository.findById('run-1'))!.recipe.isArchived, isFalse);
});

test('summaries come back newest first without loading results', () async {
  await repository.save(buildRun(id: 'old', createdAt: DateTime.utc(2026, 1, 1)));
  await repository.save(buildRun(id: 'new', createdAt: DateTime.utc(2026, 6, 1)));

  final summaries = await repository.listSummaries();
  expect(summaries.map((s) => s.id), ['new', 'old']);
});

test('saving a run commits its acknowledgements in the same transaction',
    () async {
  final run = buildRunWithAcknowledgement(id: 'run-1');
  await repository.save(run);

  expect((await repository.findById('run-1'))!.acknowledgedWarnings,
      run.acknowledgedWarnings);
});
```

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/persistence/production_run_repository_test.dart`
Expected: FAIL on the missing repository.

- [ ] **Step 3: Implement `save` as one transaction**

```dart
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
        await txn.insert('run_acknowledgements', _acknowledgementRow(run.id, warning));
      }
      for (final entry in run.overrides.entries) {
        await txn.insert('run_overrides', _overrideRow(run.id, entry.key, entry.value));
      }
    });
```

This is the design document's invariant, expressed directly: the snapshot and
the acknowledgement state it was saved with commit together or not at all.

- [ ] **Step 4: Implement `findById` and `listSummaries`**

`findById` reads the run row, decodes the payload, reads the two child tables,
and rebuilds the `ProductionRun` with its acknowledgements and overrides.
`listSummaries` queries only `production_runs`, selecting the metadata columns
and never `result_json`, ordered by `created_at` descending.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/persistence/production_run_repository_test.dart`
Expected: PASS, 5 tests.

- [ ] **Step 6: Commit**

```bash
git add lib/persistence/sqflite/production_run_repository.dart lib/persistence/persistence.dart test/persistence/production_run_repository_test.dart
git commit -m "feat(persistence): store production runs as immutable snapshots"
```

---

### Task 7: Acknowledgements and overrides after the fact

**Files:**

- Modify: `lib/persistence/sqflite/production_run_repository.dart`
- Test: `test/persistence/production_run_repository_test.dart`

**Interfaces:**

- Consumes: everything from Task 6.
- Produces: working `recordAcknowledgement` and `recordOverride`.

- [ ] **Step 1: Write the failing tests**

```dart
test('recording an acknowledgement makes the run finalizable', () async {
  final run = buildRunWithOneBlockingWarning(id: 'run-1');
  await repository.save(run);
  expect((await repository.findById('run-1'))!.isFinalizable, isFalse);

  await repository.recordAcknowledgement('run-1', run.result.warnings.first);

  expect((await repository.findById('run-1'))!.isFinalizable, isTrue);
});

test('acknowledging the same warning twice does not duplicate', () async {
  final run = buildRunWithOneBlockingWarning(id: 'run-1');
  await repository.save(run);
  final warning = run.result.warnings.first;

  await repository.recordAcknowledgement('run-1', warning);
  await repository.recordAcknowledgement('run-1', warning);

  expect((await repository.findById('run-1'))!.acknowledgedWarnings, hasLength(1));
});

test('an override is keyed by recipe and component together', () async {
  final run = buildRun(id: 'run-1');
  await repository.save(run);

  await repository.recordOverride('run-1', ('parent', 'salt'), someQuantity);
  await repository.recordOverride('run-1', ('child', 'salt'), otherQuantity);

  final loaded = await repository.findById('run-1');
  expect(loaded!.overrides, hasLength(2));
});

test('recording an override replaces the previous value for that key', () async {
  final run = buildRun(id: 'run-1');
  await repository.save(run);

  await repository.recordOverride('run-1', ('r', 'salt'), firstQuantity);
  await repository.recordOverride('run-1', ('r', 'salt'), secondQuantity);

  final loaded = await repository.findById('run-1');
  expect(loaded!.overrides, hasLength(1));
  expect(loaded.overrides[('r', 'salt')], secondQuantity);
});
```

The third test is the one that matters most: an override key is deliberately a
recipe-and-component pair, because a sub-recipe referenced twice can carry the
same component id as its parent.

- [ ] **Step 2: Run and watch them fail**

Run: `flutter test test/persistence/production_run_repository_test.dart`
Expected: FAIL, the four new tests.

- [ ] **Step 3: Implement both as single statements**

Use `ConflictAlgorithm.replace` on both inserts. Neither needs an explicit
transaction: each is one statement, and the design document's invariant is
about the initial commit rather than about later state changes.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/persistence/production_run_repository_test.dart`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add lib/persistence/sqflite/production_run_repository.dart test/persistence/production_run_repository_test.dart
git commit -m "feat(persistence): record acknowledgements and overrides"
```

---

### Task 8: Failure paths and the full gate

**Files:**

- Create: `test/persistence/failure_paths_test.dart`
- Modify: whichever repository a test proves is missing a guard

**Interfaces:**

- Consumes: everything above.
- Produces: no new API. This task exists because the coverage gate demands every error branch be reached, and because a guard nobody has watched fail is not known to work.

- [ ] **Step 1: Write the corruption tests**

```dart
test('an unknown unit symbol in a stored row throws rather than guessing',
    () async {
  await db.insert('ingredients', <String, Object?>{
    'id': 'x',
    'name': 'X',
    'default_unit_symbol': 'parsec',
    'category': null,
  });

  await expectLater(
    ingredients.findById('x'),
    throwsA(isA<CorruptDatabaseError>()),
  );
});

test('unparseable result_json throws rather than returning a partial run',
    () async {
  await db.insert('production_runs', <String, Object?>{
    'id': 'broken',
    'recipe_id': 'r',
    'recipe_revision': 1,
    'target_numerator': '1',
    'target_denominator': '1',
    'target_unit': 'kg',
    'created_at': DateTime.utc(2026).toIso8601String(),
    'result_json': '{not json',
  });

  await expectLater(
    runs.findById('broken'),
    throwsA(isA<CorruptDatabaseError>()),
  );
});

test('a missing quantity column throws rather than defaulting to zero',
    () async {
  await db.insert('ingredients', <String, Object?>{
    'id': 'y',
    'name': 'Y',
    'default_unit_symbol': 'g',
    'category': null,
  });
  await db.rawUpdate('UPDATE ingredients SET default_unit_symbol = NULL');

  await expectLater(
    ingredients.findById('y'),
    throwsA(isA<CorruptDatabaseError>()),
  );
});
```

The third test needs `default_unit_symbol` to be nullable to run; if the schema
forbids it, drop that test and instead corrupt a nullable quantity group on
`recipe_components`, where `base_numerator` can legitimately be NULL and a
partially-filled group is the real hazard.

- [ ] **Step 2: Write the transaction-rollback test**

```dart
test('a failure partway through saving a run leaves no row behind', () async {
  final run = buildRunWhoseSecondAcknowledgementViolatesAConstraint();

  await expectLater(runs.save(run), throwsA(anything));

  expect(await runs.findById(run.id), isNull);
  expect(await db.query('run_acknowledgements'), isEmpty);
});
```

Force the failure rather than asserting from inspection. Inserting the same
acknowledgement tuple twice within one `save` violates the composite primary
key and is the cheapest way to make the transaction fail midway.

- [ ] **Step 3: Run the tests and watch them fail or pass honestly**

Run: `flutter test test/persistence/failure_paths_test.dart`

A test that passes immediately here means the guard already worked. A test that
fails means a guard is missing; add it to the repository the test names, then
re-run. Do not adjust the test to match the code.

- [ ] **Step 4: Run the full gate**

```bash
flutter analyze
very_good test --coverage --min-coverage 100
trunk check lib/persistence test/persistence
```

Expected: no analyzer issues, coverage gate exit 0, trunk clean. If coverage is
short, the uncovered lines are error branches; add the test that reaches them
rather than lowering the threshold.

- [ ] **Step 5: Confirm the domain never learned about storage**

```bash
flutter test test/domain/domain_purity_test.dart
```

Expected: PASS. This proves no file under `lib/domain/` imports `sqflite` and
that nothing in this plan reached across the boundary.

- [ ] **Step 6: Commit**

```bash
git add test/persistence/failure_paths_test.dart
git commit -m "test(persistence): prove the corruption and rollback guards fail closed"
```

---

## Self-review notes

Checked against the spec on 2026-09-07.

- Every spec section has a task: schema and version in Task 1, quantity encoding in Task 2, interfaces in Task 3, revision behaviour in Task 4, snapshot encoding in Task 5, transaction boundaries in Tasks 4 and 6, the mutable pair in Task 7, error handling and the definition of done in Task 8.
- The spec's "opening a database by path" affordance is Task 1's `openPrepBookDatabase({required String path})`, and no later task hardcodes a location.
- Column names are written once in Task 1 and referenced by prefix afterwards. `quantityToColumns(q, 'base_yield')` produces exactly the `base_yield_*` names the schema declares; a rename must happen in both places.
- Several tasks name domain APIs (`Unit.all`, `Unit.gram`, the `Quantity` and `Recipe` constructors) from the domain's shape rather than from a verified read. Each such step says to read the domain file first and use the real names. That is deliberate: inventing a signature here would be worse than telling the implementer where to look.
