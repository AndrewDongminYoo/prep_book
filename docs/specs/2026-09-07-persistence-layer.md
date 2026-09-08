# Persistence Layer Specification

**Status:** approved 2026-09-07.
**Authority:** `docs/notes/2026-09-06-prepbook-pro-design.md` is the product source of truth.
This document specifies one of its six units and does not restate its scope decisions.

## Purpose

Store the recipe library and production history in a local SQLite database, and expose repository interfaces the application layer can use without knowing how storage works.

The domain layer is pure Dart and must not learn about this unit.
`package:sqflite` is already in the domain purity guard's denylist, so a violation fails the build rather than being caught in review.

## Scope

In scope:

- Repository interfaces for ingredients, recipes with their revisions, and production runs.
- A SQLite implementation of those interfaces.
- The schema, its version, and the upgrade path between versions.
- Transaction boundaries, in particular the one the design document makes an invariant.

Out of scope, deliberately:

- The backup archive format, the system file picker, and validate-then-swap restore.
  Those are an application-layer use case in the design document, and they carry a platform dependency this unit does not need.
  This unit only owes them one affordance, described under "Opening a database by path".
- Spreadsheet import.
  The design document's "Migration" unit is a development-only spreadsheet importer and is unrelated to the schema upgrades specified here.
  This document says **schema upgrade** wherever it means a change to the database shape.
- Prices, costing, suppliers, accounts, and synchronization, all excluded from the first release by the design document's scope fence.

## Terminology

- **Schema upgrade** — a change to the database shape, versioned with `PRAGMA user_version`.
- **Migration** — the spreadsheet importer unit. Never used in this document in any other sense.
- **Snapshot** — a stored `ProductionRun`, immutable once written.
- **Revision** — a saved edit of a recipe, which produces a new row rather than replacing one.

## What the domain gives us to store

The domain types already decide most of the schema.
Two of their properties matter more than the rest.

**A `ProductionRun` holds its recipe by value.**
It carries `recipe` and `dependencySnapshot` as whole `Recipe` objects, not identifiers.
The design document's invariant that a later recipe edit must not alter a stored snapshot is therefore already guaranteed by the domain's own structure.
Persistence must not weaken it, which is why no snapshot row carries a foreign key into `recipes`.

**Only two fields of a `ProductionRun` ever change.**
`acknowledge()` and `override()` return a new instance through `_copyWith`, and the only fields they replace are `acknowledgedWarnings` and `overrides`.
Everything else — `id`, `createdAt`, `recipe`, `dependencySnapshot`, `targetYield`, `result` — is written once and never rewritten.
The schema separates those two mutable sets into their own tables so that the snapshot row itself is insert-only.

## Quantity encoding

A `Quantity` holds an exact `Rational` whose numerator and denominator are both `BigInt`.
SQLite's `INTEGER` is 64-bit and cannot be guaranteed to hold either, so a quantity is stored as a numerator and denominator pair in `TEXT`.

A `Quantity` therefore occupies three columns wherever one is stored: numerator, denominator, and unit.

A `ScaledQuantity` carries both the exact value and the displayed value, because the design document requires rounding never to destroy the exact quantity.
Both are stored, but never as columns.
A `ScaledQuantity` only ever appears inside a `ProductionResult`, which the schema section below keeps whole in `result_json`, so no table has a column group for one.
Its exact and displayed values are two quantities encoded in that JSON, each in the same numerator, denominator and unit form for the same reason.

Corrected 2026-09-07: this section previously said a scaled quantity occupied five columns and listed them, which the schema section below already contradicted.

Storing a single normalized decimal string was rejected.
A scale ratio such as one third has no finite decimal form, so that encoding would have to truncate, and truncating is the exact failure the domain chose `Rational` over `Decimal` to avoid.

`Unit`'s own constructor is private, but the domain's unit space is not a fixed table: `Unit.count` and `Unit.namedYield` build units from arbitrary caller-chosen symbols, so no lookup can recover them.
A unit is stored as the string `unitToStorage` produces — a bare symbol for one of the domain's fixed instances, and a `count:` or `yield:` prefixed form for one built from an arbitrary symbol, so a single column round-trips both.
A stored value that is neither is a corrupt-database error, never a silently constructed unit.

Corrected 2026-09-07: this section previously said `Unit` had a fixed table and that only a symbol was stored and recovered by lookup, which is why `unitToStorage` exists at all.

`RoundingRule.increment` and `Unit.factorToCanonical` are `Decimal` rather than `Rational`.
A `Decimal` is by definition a terminating decimal, so those are stored as a single `TEXT` value with no loss.

## Schema, version 1

Column lists below are the shape, not the full DDL; the implementation plan owns the exact statements.

**`ingredients`** — mutable.
`id` primary key, `name`, `default_unit`, `category` nullable.

**`recipes`** — insert-only per revision.
Composite primary key `(id, revision)`.
Columns for `name`, `category`, `base_yield` (3 columns), `max_batch_yield` (3 columns, nullable), `preparation_notes` as a JSON array, `modified_at`, `is_archived`.

A saved edit inserts a new `(id, revision + 1)` row.
Nothing updates a recipe row except `is_archived`, which the design document treats as a state change rather than an edit.

**`recipe_components`** — belongs to one recipe revision.
Foreign key `(recipe_id, recipe_revision)`, plus `component_id`, `target_kind` (`ingredient` or `sub_recipe`), `target_id`, `base_quantity` (3 columns, nullable), `behavior`, `rounding_increment` nullable, `note` nullable, `display_order`.
Components are copied per revision rather than shared, because a component's meaning is tied to the revision that defines it.

**`production_runs`** — insert-only, never updated.
`id` primary key, `recipe_id`, `recipe_revision`, `target_yield` (3 columns), `created_at`, and `result_json`.

`result_json` holds the serialized `ProductionResult` together with the `recipe` and `dependencySnapshot` the run was computed against.
`recipe_id` and `recipe_revision` are duplicated out of the JSON as columns so history can be listed and filtered without parsing every row.
They are not foreign keys.
A recipe revision can be deleted or archived while a snapshot that named it survives untouched, which is the behaviour the design document requires.

**`run_acknowledgements`** — insert-only.
`(run_id, warning_kind, recipe_id, component_id)`, with `component_id` nullable because `ArchivedDependencyWarning` identifies a recipe alone.
This tuple mirrors the value equality the `ProductionWarning` hierarchy already defines, so a row and a warning correspond exactly.

**`run_overrides`** — insert or replace.
`(run_id, recipe_id, component_id)` primary key, plus a quantity (3 columns).
The key pair is the domain's `OverrideKey`, which is deliberately a recipe-and-component pair rather than a component id alone.

## Transaction boundaries

The design document states that a production run is computed before persistence, and that the snapshot and its acknowledgement state are committed in one transaction.
That is the sharpest constraint on this unit and the reason `sqflite` was chosen: `db.transaction(...)` expresses it directly.

Two operations are transactional:

1. **Saving a production run.** The `production_runs` insert, every `run_acknowledgements` insert, and every `run_overrides` insert commit together or not at all.
2. **Saving a recipe revision.** The `recipes` insert and all of its `recipe_components` inserts commit together.

A failed write leaves the previous state intact, which the design document lists under error handling.

Recording one acknowledgement or one override after the run is already stored is a single statement and needs no explicit transaction.
The invariant is about the initial commit, where a snapshot and the state it was saved with must not be separable.
Anything the operator acknowledges later is its own write.

## Repository interfaces

The interfaces live in this unit, per the design document's own description of it, and the application layer depends on them.
They are expressed in domain types only: a caller passes and receives `Recipe`, `Ingredient` and `ProductionRun`, never a row or a map.

- `IngredientRepository` — list, get by id, upsert, delete.
- `RecipeRepository` — list current revisions, get a specific `(id, revision)`, get the latest revision, save a new revision, archive, list the current revisions that reference a given ingredient directly.
- `ProductionRunRepository` — list run summaries newest first, get a full run by id, save a computed run, record an acknowledgement, record an override.

"List run summaries" returns metadata rather than whole runs, so that a history screen does not deserialize every `result_json` it displays.

## Opening a database by path

`database.dart` opens a database at a caller-supplied path rather than resolving one internally.

This is the single affordance this unit owes the deferred backup work.
Validate-then-swap restore needs to open a candidate database somewhere other than the live location, verify it, and only then replace the current file.
Taking a path costs nothing now and means the backup plan can be built on top of this unit without reopening it.

## Schema version and upgrades

The version is `PRAGMA user_version`, starting at 1.

There is no precedent for this in the operator's projects; it is being set here.

Upgrades are an ordered list of functions from version N to N+1, applied in sequence.
`onUpgrade` never contains conditional logic about which version it came from beyond that sequence.

**The upgrade test harness is built in the same change as version 1**, while there is only one version and the harness is trivial.
Building it later means the session that adds version 2 has to write both the upgrade and the means of testing it, at the moment it is least convenient.
The harness opens a database at an older version, applies the upgrade path, and asserts the resulting shape and the survival of existing rows.

## Error handling

- A write that fails inside a transaction rolls back and leaves the previous state.
- An unknown unit symbol, an unknown warning kind, or `result_json` that does not parse is a corrupt-database error naming the row.
  It is never repaired by guessing, and never silently skipped.
- A read for a missing id returns null; a read for a row that exists but cannot be reconstructed throws.
  Those are different failures and the interfaces keep them distinct.

## Testing strategy

`sqflite` reaches SQLite through a platform channel, so it does not run under `flutter test`.
**`sqflite_common_ffi`** provides the same API over a local library and is what makes this unit testable at all.
The two packages are introduced together, as a runtime and its test harness, rather than one at a time.

Tests run against an in-memory database created fresh per test.

The suite covers, at minimum:

- Round-tripping every domain type through save and load, including a non-terminating quantity such as one third, which must return bit-identical.
- A saved recipe edit producing a new revision while the previous revision remains readable.
- A stored snapshot remaining unchanged after its recipe is edited and after it is archived.
- A failed write inside a transaction leaving the previous state, verified by forcing the failure rather than by inspection.
- An unknown unit symbol and unparseable `result_json` raising rather than returning a partial object.
- The schema upgrade harness described above.

CI requires 100 percent line coverage, so every branch of the mappers and the error paths needs a test that reaches it.

## Decisions recorded here, with no prior precedent

An oracle retrieval on 2026-09-07 found no precedent in the operator's projects for any of the following.
Each is therefore set by this document rather than followed.

- **`sqflite` over `drift`.** No code generation, so `build_runner` stays out of the build and there is no generated output to reconcile with the 100 percent coverage gate. Its transaction API expresses the design document's invariant directly. The cost is hand-written SQL and hand-written mapping, which is acceptable while the query surface is recipe CRUD and a history list.
- **Numerator and denominator as `TEXT`** rather than a decimal string or a scaled integer.
- **Snapshot result as JSON** with duplicated metadata columns, rather than full normalization. The first release has no aggregate query over run internals; multi-recipe daily aggregation is behind the scope fence.
- **`PRAGMA user_version`** with a sequential upgrade list.

## Definition of done

- Every repository interface has a `sqflite` implementation and a test for each method.
- The two transactional operations are proved atomic by a test that forces a mid-transaction failure.
- The schema upgrade harness exists and passes with a single version registered.
- `flutter analyze` is clean, the coverage gate passes at 100 percent, and `trunk check` is clean.
- The domain purity guard still passes, proving no domain file learned about storage.
