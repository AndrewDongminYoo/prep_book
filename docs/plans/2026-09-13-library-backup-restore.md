# Library Backup and Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to execute this plan task by task.
> Execute in the current workspace, keep the database and bootstrap tasks sequential, and do not create a worktree or delegate tightly coupled implementation.

**Goal:** Let the operator save the complete local library as one versioned `.prepbook` file and replace the active library from a validated backup without risking the current data.

**Architecture:** Two pure application use cases call one typed backup gateway.
Infrastructure under `lib/backup/` owns the ZIP envelope, candidate validation, consistent SQLite snapshots, and recoverable file replacement.
The composition root owns the live connection and remount callback, while one presentation feature owns native picker interaction, confirmation, progress, and localized outcomes.

**Tech Stack:** Dart 3.12, Flutter 3.44 or later, Material 3, Bloc, `sqflite` 2.4.3, `archive: ^4.2.0`, `file_picker: ^12.3.0`, Flutter localization, `sqflite_common_ffi`, Flutter unit and widget tests.

**Spec:** `docs/specs/2026-09-12-library-backup-restore.md`

## Success Criteria

1. Create an exact two-entry backup archive from a consistent live-database snapshot.
   Verify with archive contract tests, candidate validation, and an FFI round trip over every schema table.
2. Reject malformed, oversized, incompatible, corrupt, or domain-invalid candidates before changing the live database.
   Verify with one deliberately failing fixture for every guard and an unchanged-database negative control.
3. Activate a valid restored library immediately, or recover the previous library after every injected post-close failure.
   Verify with the complete swap fault matrix and rebuilt-root integration tests.
4. Expose native save and open flows with neutral cancellation, destructive confirmation, blocking progress, and English and Korean outcomes.
   Verify with cubit tests, responsive widget tests, one iOS Simulator pass, and one Android Emulator pass.
5. Preserve existing boundaries and quality gates.
   Verify with dependency inspection, boundary tests, static analysis, Bloc lint, full randomized tests, reached-line coverage, and Trunk checks over explicit changed paths.

## Global Constraints

- Work in `/Users/dongminyu/Development/01_personal/prep_book` without creating a task worktree.
- Do not stage, commit, push, merge, publish, or install on a physical device without separate authority.
- Keep the archive to exactly `manifest.json` and `library.db` as regular root files.
- Limit both the selected archive and uncompressed database entry to `256 MiB` before materialization.
- Compare ZIP entry CRC values explicitly after reading because the selected `archive` decoder does not enforce them for this path.
- Support iOS and Android only.
- Keep Flutter, SQLite, ZIP, paths, and native picker types out of `lib/application/`.
- Keep persistence, SQLite, ZIP, and `dart:io` out of `lib/presentation/`.
- Add no dependency beyond direct `archive: ^4.2.0` and `file_picker: ^12.3.0`.
- Use one narrow internal file seam for deterministic replacement tests instead of a general filesystem framework.
- Preserve missing ingredient and recipe references because current product behavior permits them.
- Reject malformed stored values and current-revision recipe cycles.
- Preserve the live connection and library view state during backup.
- Close and replace the live database only after archive, schema, SQLite, repository, graph, and operator-confirmation gates succeed.
- Preserve diagnostic database copies when rollback activation fails.
- Run package resolution before formatting.
- Run at most one simulator, emulator, Gradle, or Xcode job at a time.
- Treat coverage as reached-line evidence only; the restore invariant comes from explicit fault-injection tests.
- Record Oracle precedent as `[TOOL_FAILED]` for this plan because the required local transport did not initialize during design retrieval.

## File Ownership Map

| Area                        | Create                                                                                                                                                                                   | Modify                                                                                                                                                                                                                       |
| --------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Application contract        | `lib/application/library_backup.dart`, `test/application/library_backup_test.dart`                                                                                                       | `lib/application/application.dart`, `test/application/application_boundary_test.dart`                                                                                                                                        |
| Archive and filenames       | `lib/backup/backup.dart`, `lib/backup/archive_codec.dart`, `test/backup/archive_codec_test.dart`                                                                                         | None                                                                                                                                                                                                                         |
| Candidate validation        | `lib/backup/database_validator.dart`, `test/backup/database_validator_test.dart`                                                                                                         | `lib/persistence/database.dart`, `test/persistence/database_test.dart`                                                                                                                                                       |
| Snapshot and files          | `lib/backup/backup_files.dart`, `lib/backup/database_snapshotter.dart`, `test/backup/backup_files_test.dart`, `test/backup/database_snapshotter_test.dart`                               | None                                                                                                                                                                                                                         |
| Restore and gateway         | `lib/backup/database_session.dart`, `lib/backup/database_library_backup_gateway.dart`, `test/backup/database_session_test.dart`, `test/backup/database_library_backup_gateway_test.dart` | None                                                                                                                                                                                                                         |
| Composition                 | `test/bootstrap_test.dart`                                                                                                                                                               | `lib/bootstrap.dart`, `lib/main_development.dart`, `lib/main_staging.dart`, `lib/main_production.dart`, `lib/app/view/app.dart`, `test/app/view/app_test.dart`                                                               |
| Presentation                | `lib/presentation/library_backup/**`, `test/presentation/library_backup/**`                                                                                                              | `lib/presentation/presentation.dart`, `lib/presentation/recipe_library/view/recipe_library_page.dart`, `test/presentation/presentation_boundary_test.dart`, `test/presentation/recipe_library/recipe_library_page_test.dart` |
| Localization and completion | `test/backup/library_backup_round_trip_test.dart`                                                                                                                                        | `lib/l10n/arb/app_en.arb`, `lib/l10n/arb/app_ko.arb`, generated files under `lib/l10n/gen/`, `README.md`                                                                                                                     |
| Dependencies                | None                                                                                                                                                                                     | `pubspec.yaml`, `pubspec.lock`, platform-generated plugin registration only when package resolution requires it                                                                                                              |

Do not broaden this map to the editor, production calculation, PDF renderer, or persistence codecs unless a failing backup test proves that an explicit validation seam is missing.

## Task 1: Establish the application contract and direct dependencies

**Files:**

- Create: `lib/application/library_backup.dart`
- Create: `test/application/library_backup_test.dart`
- Modify: `lib/application/application.dart`
- Modify: `test/application/application_boundary_test.dart`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`

**Interfaces:**

```dart
enum LibraryBackupFailureKind {
  cancelled,
  unsupportedFormat,
  invalidArchive,
  backupTooLarge,
  invalidDatabase,
  incompatibleSchema,
  saveFailed,
  restoreFailed,
  recoveryFailed,
}

final class LibraryBackupException implements Exception {
  const LibraryBackupException(this.kind, {this.cause, this.stackTrace});

  final LibraryBackupFailureKind kind;
  final Object? cause;
  final StackTrace? stackTrace;
}

final class LibraryBackupFile {
  const LibraryBackupFile({required this.bytes, required this.suggestedName});

  final Uint8List bytes;
  final String suggestedName;
}

const maxLibraryBackupBytes = 256 * 1024 * 1024;

abstract interface class LibraryBackupGateway {
  Future<LibraryBackupFile> create();
  Future<void> restore(Uint8List archiveBytes);
}

final class CreateLibraryBackup {
  const CreateLibraryBackup(this._gateway);
  Future<LibraryBackupFile> call();
}

final class RestoreLibraryBackup {
  const RestoreLibraryBackup(this._gateway);
  Future<void> call(Uint8List archiveBytes);
}
```

- [ ] **Step 1: Write failing use-case forwarding tests**

Add a recording fake gateway and prove that `CreateLibraryBackup` returns the exact immutable result and `RestoreLibraryBackup` forwards the exact byte object once.
Prove that every typed failure is preserved without translation or loss of its diagnostic cause and stack trace.

- [ ] **Step 2: Plant and reject a boundary violation**

Temporarily add `import 'package:archive/archive.dart';` to a probe under `lib/application/`.
Run `flutter test test/application/application_boundary_test.dart` and require the failure to name both the probe and the forbidden URI.
Remove only the probe after observing RED.

- [ ] **Step 3: Add the contract and barrel export**

Implement the types above with owned bytes and defensive copies wherever a caller could otherwise mutate stored state.
Export `library_backup.dart` from `lib/application/application.dart`.
Keep picker cancellation as a normal presentation result even though `cancelled` remains in the shared outcome taxonomy for adapters that must translate a platform cancellation.

- [ ] **Step 4: Add direct dependencies and resolve the graph**

Add `archive: ^4.2.0` and `file_picker: ^12.3.0` under `dependencies`.
Run `flutter pub get` and retain the regenerated `pubspec.lock` in the same change.

- [ ] **Step 5: Verify the contract and dependency shape**

Run:

```sh
flutter test test/application/library_backup_test.dart test/application/application_boundary_test.dart
flutter pub deps --style=compact
```

Require both packages to appear as direct dependencies at resolved versions accepted by the constraints.

## Task 2: Implement the strict version 1 archive codec

**Files:**

- Create: `lib/backup/backup.dart`
- Create: `lib/backup/archive_codec.dart`
- Create: `test/backup/archive_codec_test.dart`

**Interfaces:**

```dart
final class DecodedLibraryBackup {
  const DecodedLibraryBackup({
    required this.databaseBytes,
    required this.databaseSchemaVersion,
    required this.createdAtUtc,
  });

  final Uint8List databaseBytes;
  final int databaseSchemaVersion;
  final DateTime createdAtUtc;
}

final class BackupArchiveCodec {
  const BackupArchiveCodec();

  Uint8List encode({
    required Uint8List databaseBytes,
    required int databaseSchemaVersion,
    required DateTime createdAtUtc,
  });

  DecodedLibraryBackup decode(Uint8List archiveBytes);
}

String buildLibraryBackupFilename(DateTime localCreatedAt);
```

- [ ] **Step 1: Build malformed fixtures and prove every guard RED**

Write fixture helpers that can independently create a missing entry, duplicate name, directory, symbolic link, nested path, extra entry, missing manifest field, invalid manifest type, invalid UTC timestamp, unsupported format version, future schema, mismatched database entry name, bad CRC, oversized archive declaration, and oversized database declaration.
For every guard, first run the decoder against the malformed fixture and require the expected typed failure before adding or enabling the production check.

- [ ] **Step 2: Encode the exact envelope**

Emit exactly two regular root entries named `manifest.json` and `library.db`.
Serialize the five required manifest fields with a UTC ISO-8601 timestamp and schema version `1`.
Keep entry ordering stable for deterministic tests, but do not treat ZIP metadata bytes as a public compatibility promise.

- [ ] **Step 3: Decode without extracting paths**

Reject the archive-byte limit before ZIP decoding.
Inspect every entry name, type, duplication, and declared uncompressed size before materializing content.
Read the two named entries directly into memory and never call a filesystem extraction helper.
After each entry is read, compare `getCrc32(bytes)` with the entry CRC and map a mismatch to `invalidArchive`.

- [ ] **Step 4: Validate the manifest before returning database bytes**

Require the exact format identifier, format version `1`, database entry `library.db`, and a positive schema version no greater than `currentSchemaVersion`.
Require `createdAtUtc` to parse and remain UTC.
Ignore unknown manifest fields.
Map a newer database schema to `incompatibleSchema`; map all other envelope defects to `unsupportedFormat`, `invalidArchive`, or `backupTooLarge` as specified.

- [ ] **Step 5: Verify round trip and safe filename construction**

Round-trip fixed bytes and a fixed UTC instant.
Prove that `buildLibraryBackupFilename` uses local calendar fields in `prepbook-backup-YYYYMMDD-HHmmss.prepbook` and zero-pads every field.
Run:

```sh
flutter test test/backup/archive_codec_test.dart
```

## Task 3: Validate a candidate database through SQLite and repository readers

**Files:**

- Create: `lib/backup/database_validator.dart`
- Create: `test/backup/database_validator_test.dart`
- Modify: `lib/backup/backup.dart`
- Modify: `lib/persistence/database.dart`
- Modify: `test/persistence/database_test.dart`

**Interfaces:**

```dart
final class BackupDatabaseValidator {
  const BackupDatabaseValidator({required DatabaseFactory factory});

  Future<void> validate({
    required String candidatePath,
    required int manifestSchemaVersion,
  });
}
```

Extend `openPrepBookDatabase` with an optional `singleInstance` argument that defaults to the existing production behavior and is forwarded into `OpenDatabaseOptions`.
The validator must always use `singleInstance: false` for candidate paths.

- [ ] **Step 1: Write the pre-open schema tests**

Create real FFI database files with `PRAGMA user_version` values `0`, `1`, and `currentSchemaVersion + 1`.
Prove that zero and future versions fail before `openPrepBookDatabase` can create or upgrade anything, while version `1` proceeds.
Prove that a manifest and database schema mismatch fails with the correct typed error.

- [ ] **Step 2: Add the `singleInstance` path seam**

Write a failing persistence test that opens the same path twice with `singleInstance: false` and proves the two handles have independent lifetimes.
Add the smallest optional argument to `openPrepBookDatabase`, preserve its current default, and rerun the persistence database tests.

- [ ] **Step 3: Enforce SQLite checks in order**

Read `PRAGMA user_version` through a raw FFI open without upgrade callbacks.
Only after the pre-open checks pass, open through `openPrepBookDatabase` so supported upgrades apply to the candidate alone.
Require `PRAGMA integrity_check` to return exactly `ok` and `PRAGMA foreign_key_check` to return zero rows.
Close every raw and validated handle in `finally` paths.

- [ ] **Step 4: Reconstruct every stored object**

Query every ingredient identifier and call `SqfliteIngredientRepository.findById` for each row.
Query every recipe `(id, revision)` pair and call `SqfliteRecipeRepository.findRevision` for each row.
Query every production run identifier and call `SqfliteProductionRunRepository.findById` for each row.
Treat a missing reconstruction for a row that exists in the table as `invalidDatabase`.
Do not replace these reads with table-shape assertions because they are the checks that exercise the existing codecs.

- [ ] **Step 5: Validate the latest recipe graph**

Build an index from `listLatestRevisions` and run `RecipeDependencyGraph.findCycleFrom` from every latest recipe.
Reject every detected cycle.
Accept missing ingredient and missing sub-recipe targets when all stored objects are otherwise valid.

- [ ] **Step 6: Prove validator reach and policy**

Build one valid fixture that contains a custom unit, non-terminating rational quantity, archived revision, production warning, acknowledgement, override, and historical run.
Corrupt one persisted value from each current codec family and require `invalidDatabase`.
Plant corruption in an old recipe revision and an old production run so a validator that reads only latest rows fails the test.
Add explicit cases for integrity failure, foreign-key failure, latest-revision cycle rejection, and dangling-reference acceptance.
Run:

```sh
flutter test test/persistence/database_test.dart test/backup/database_validator_test.dart
```

## Task 4: Create a consistent validated database snapshot

**Files:**

- Create: `lib/backup/backup_files.dart`
- Create: `lib/backup/database_snapshotter.dart`
- Create: `test/backup/backup_files_test.dart`
- Create: `test/backup/database_snapshotter_test.dart`
- Modify: `lib/backup/backup.dart`

**Internal seam:**

```dart
abstract interface class BackupFiles {
  Future<int> length(String path);
  Future<Uint8List> readBytes(String path);
  Future<void> writeBytes(String path, Uint8List bytes, {required bool flush});
  Future<void> copy(String source, String destination, {required bool flush});
  Future<void> renameReplacing(String source, String destination);
  Future<void> deleteIfExists(String path);
  Future<void> deleteDatabaseSidecars(String databasePath);
}
```

Do not export `BackupFiles` from the backup unit's public barrel.
Use it only where real file effects or fault injection require it.

- [ ] **Step 1: Prove the file seam's real semantics**

Test `IoBackupFiles` in a unique temporary directory.
Require flushed write and copy to preserve exact bytes, replacement rename to leave only the destination bytes, missing-file deletion to be harmless, and sidecar cleanup to target only `-wal` and `-shm` for the exact database path.

- [ ] **Step 2: Add snapshot RED tests around the owned connection**

Open a file-backed FFI database in WAL mode, write a complete baseline, and start a second write through the owned connection while snapshot work is inside its lock.
Require the captured candidate to represent one complete state and never a mix of the two writes.
Require candidate validation failure to leave the live connection open and remove the temporary candidate.

- [ ] **Step 3: Checkpoint and acquire the exclusive transaction**

Run `PRAGMA wal_checkpoint(TRUNCATE)` on the live connection before the snapshot transaction.
Start `Database.transaction` with `exclusive: true` and perform a harmless read through the transaction before reading file bytes so the lock is known to be acquired.
Read the main database through the injected factory's database-byte API while the transaction remains active.
End the transaction without writing.

- [ ] **Step 4: Validate the captured bytes before archive creation**

Write the captured bytes to a unique candidate beside the live database, flush it, and call `BackupDatabaseValidator` with the current schema version.
Return the validated bytes only after validation succeeds.
Delete candidate sidecars and the candidate itself in a `finally` path.
Do not close or replace the live connection.

- [ ] **Step 5: Make the consistency test sensitive**

Before trusting the passing snapshot test, make the controlled test seam report the file read before the lock or checkpoint and require its call-order assertion to fail.
Restore the production sequence and run:

```sh
flutter test test/backup/backup_files_test.dart test/backup/database_snapshotter_test.dart
```

## Task 5: Implement validate-then-swap restore and rollback recovery

**Files:**

- Create: `lib/backup/database_session.dart`
- Create: `test/backup/database_session_test.dart`
- Modify: `lib/backup/backup.dart`

**Session responsibilities:**

- Own the live database path and current connection.
- Write every decoded candidate beside the live database.
- Validate before closing the current connection.
- Activate a reopened database through one callback supplied by the composition root.
- Mount the startup failure application through a second callback only when rollback activation also fails.

- [ ] **Step 1: Define the fault matrix before implementation**

Write one parameterized harness with injection points before live close, during rollback copy, during candidate rename, during replacement reopen, during repository or application rebuild, during rollback rename, and during rollback reopen.
For every pre-close failure, compare both live bytes and loaded objects before and after.
For every post-close failure with successful recovery, require the previous bytes to be active and the typed result to be `restoreFailed`.
For rollback activation failure, require `recoveryFailed`, the failure root to be mounted, and all readable diagnostic copies to remain on disk.

- [ ] **Step 2: Prove the unchanged-database assertion can fail**

Replace the before-snapshot fixture with different known bytes and run one pre-close case.
Require the equality assertion to fail with a database-byte difference.
Restore the correct fixture before continuing.

- [ ] **Step 3: Stage and validate the candidate without touching live files**

Write decoded database bytes to a unique same-directory candidate and flush them.
Run `BackupDatabaseValidator` against that path.
Return a typed validation failure while the current connection and presentation tree remain active if any check fails.

- [ ] **Step 4: Close, protect, and replace in the specified order**

Require the validator to have closed its candidate handle and then await the live connection close.
Remove only the exact live and candidate sidecars.
Copy the closed live database to a unique rollback path with flush enabled.
Atomically rename the candidate over the live database path.
Open the live path through `openPrepBookDatabase`, construct new repositories through the activation callback, and mount a fresh root.
Delete the rollback file only after the new root is mounted successfully.

- [ ] **Step 5: Recover without destroying diagnostic evidence**

On a failure after live close, close any partially opened replacement handle.
Move the failed replacement aside when necessary, atomically restore the rollback file to the live path, reopen it, and activate the previous root.
Only after previous activation succeeds may disposable candidate artifacts be removed.
If rollback activation fails, preserve the failed replacement, rollback, and live-path copies that remain readable and mount `StartupFailureApp`.
Keep the original error and recovery error with their stack traces in diagnostic logs, while returning only the typed public failure.

- [ ] **Step 6: Verify success and cleanup**

Require a successful restore to activate candidate objects, dispose the old connection, and remove candidate, sidecar, and rollback artifacts.
Run:

```sh
flutter test test/backup/database_session_test.dart
```

## Task 6: Compose the gateway and make bootstrap rebuildable

**Files:**

- Create: `lib/backup/database_library_backup_gateway.dart`
- Create: `test/backup/database_library_backup_gateway_test.dart`
- Create: `test/bootstrap_test.dart`
- Modify: `lib/backup/backup.dart`
- Modify: `lib/bootstrap.dart`
- Modify: `lib/main_development.dart`
- Modify: `lib/main_staging.dart`
- Modify: `lib/main_production.dart`
- Modify: `lib/app/view/app.dart`
- Modify: `test/app/view/app_test.dart`

**Composition contract:**

```dart
typedef PrepBookAppBuilder = FutureOr<Widget> Function({
  required RecipeRepository recipes,
  required IngredientRepository ingredients,
  required ProductionRunRepository runs,
  required CreateLibraryBackup createLibraryBackup,
  required RestoreLibraryBackup restoreLibraryBackup,
  required bool restored,
});

typedef PrepareDatabase = FutureOr<void> Function({
  required RecipeRepository recipes,
  required IngredientRepository ingredients,
  required ProductionRunRepository runs,
});
```

Change `bootstrap` to named `builder` and optional `prepare` arguments.
Add only the path resolver, database factory, and mount callbacks needed to test startup and remount behavior without a platform channel.
Production callers use their existing defaults.

- [ ] **Step 1: Test gateway orchestration and error mapping**

Prove that create asks the snapshotter for validated bytes, calls the codec once with `currentSchemaVersion` and one clock instant, and returns the local-time filename with encoded bytes.
Require that one captured instant to be converted to UTC for the manifest and to local calendar fields for the filename.
Prove that restore rejects the outer archive limit before decoding, decodes once, and passes the decoded database bytes and manifest schema to the database session.
For archive, SQLite, and filesystem exceptions, require the corresponding public failure kind while retaining the original cause and stack trace for logging.

- [ ] **Step 2: Implement one serialized gateway**

Compose `BackupArchiveCodec`, `DatabaseSnapshotter`, and the active database session in `DatabaseLibraryBackupGateway`.
Use one in-flight operation field shared by create and restore so no backup can overlap a restore.
Clear the field in `whenComplete` so retry works after success or failure.
Require a second operation submitted while one is in flight to receive one deterministic busy result without invoking a second snapshot or swap.
Do not expose paths, database handles, or concrete repositories through the application interface.

- [ ] **Step 3: Write bootstrap RED tests**

Inject an FFI database path and a recording mount callback.
Prove initial startup opens once, runs `prepare` once, builds once with `restored: false`, and mounts one root.
Prove two startup calls made while the first is blocked join one run.
Prove startup retry reruns open, prepare, build, and mount.
Prove restore activation builds with new repository instances, skips `prepare`, passes `restored: true`, and mounts a fresh root.
Prove unrecoverable activation mounts `StartupFailureApp` and leaves retry available.

- [ ] **Step 4: Split one-time preparation from root construction**

Move development seeding into the `prepare` callback.
Make all three flavor builders pure application construction over the supplied repositories and backup use cases.
Keep staging and production without a prepare callback.
Preserve the existing startup in-flight guard.

- [ ] **Step 5: Bind the active session and rebuild callback**

Resolve the live database path once in bootstrap.
Open the initial connection, construct repositories, run `prepare`, create the gateway over the same owned session, and mount the built root.
On successful restore, reconstruct repositories, gateway use cases, launchers, and `App` over the reopened connection and call the same mount callback with `restored: true`.
On ordinary backup, retain the same root and do not invoke the builder.

- [ ] **Step 6: Carry a one-time restored notice into the fresh root**

Add `restored` and `LibraryBackupLauncher` inputs to `App` and pass them to the recipe library.
The initial root receives `restored: false`.
The post-restore root receives `restored: true`, consumes that signal once after its first frame, and shows the localized success notice without retaining it in persistence.

- [ ] **Step 7: Verify composition**

Run:

```sh
flutter test test/backup/database_library_backup_gateway_test.dart test/bootstrap_test.dart test/app/view/app_test.dart
```

## Task 7: Add native picker orchestration and the library UI

**Files:**

- Create: `lib/presentation/library_backup/library_backup.dart`
- Create: `lib/presentation/library_backup/cubit/library_backup_cubit.dart`
- Create: `lib/presentation/library_backup/cubit/library_backup_state.dart`
- Create: `lib/presentation/library_backup/view/library_backup_platform.dart`
- Create: `lib/presentation/library_backup/view/library_backup_launcher.dart`
- Create: `lib/presentation/library_backup/view/library_backup_dialog.dart`
- Create: `test/presentation/library_backup/library_backup_cubit_test.dart`
- Create: `test/presentation/library_backup/library_backup_platform_test.dart`
- Create: `test/presentation/library_backup/library_backup_dialog_test.dart`
- Modify: `lib/presentation/presentation.dart`
- Modify: `lib/presentation/recipe_library/view/recipe_library_page.dart`
- Modify: `test/presentation/presentation_boundary_test.dart`
- Modify: `test/presentation/recipe_library/recipe_library_page_test.dart`
- Modify: `lib/l10n/arb/app_en.arb`
- Modify: `lib/l10n/arb/app_ko.arb`
- Modify through `flutter gen-l10n`: generated files under `lib/l10n/gen/`

**Presentation interfaces:**

```dart
abstract interface class LibraryBackupPlatform {
  Future<Uint8List?> pickBackup();
  Future<bool> saveBackup(LibraryBackupFile backup);
}

enum LibraryBackupAction { create, restore }

final class LibraryBackupLauncher {
  const LibraryBackupLauncher({
    required CreateLibraryBackup createBackup,
    required RestoreLibraryBackup restoreBackup,
    required LibraryBackupPlatform platform,
  });

  Future<void> open(BuildContext context, LibraryBackupAction action);
}
```

Use a single immutable cubit state with a status enum, active action, pending restore bytes, and optional typed failure.
Statuses must distinguish idle, creating, awaiting confirmation, restoring, succeeded, and failed.

- [ ] **Step 1: Prove the picker adapter boundary RED**

Add `package:file_picker/` to a temporary probe and run the unchanged presentation boundary test.
Require it to fail before adding that one package prefix to the allowlist.
Add a targeted assertion that only `lib/presentation/library_backup/view/library_backup_platform.dart` may contain that package prefix.
Keep `dart:io`, `package:archive/`, and persistence imports forbidden.
Remove the probe after the failure is observed.

- [ ] **Step 2: Test size-before-read and cancellation behavior**

Inject the `FilePicker` call or the minimal picker function into `FilePickerLibraryBackupPlatform`.
Pick one custom-extension file with a read stream, inspect `PlatformFile.size`, and reject a value above `maxLibraryBackupBytes` before listening to the stream.
Collect exact bytes only after the size check passes.
Return `null` when the open picker is cancelled and `false` when the save picker is cancelled.
Map picker exceptions to the typed save or restore-facing failure without exposing a native path.

- [ ] **Step 3: Write the cubit state-machine tests**

For backup, require `creating`, then one save call with the use-case result, then success or neutral idle on cancellation.
For restore, require pick, `awaitingConfirmation`, no restore call before confirmation, `restoring`, then completion.
Require confirmation cancellation to discard pending bytes and call no use case.
Require every failure kind to produce one localizable failed state.
Require repeated actions while busy to perform no second picker, create, save, or restore call.

- [ ] **Step 4: Implement the dialog and launcher**

Open one modal route from the app-bar menu and start the selected action after the route owns its cubit.
Show a destructive confirmation only after valid backup bytes have been picked.
Name both recipes and production history in that confirmation.
Disable confirm, back navigation, and app-bar actions while restore is running.
Treat picker and confirmation cancellation as neutral and close the route without an error message.
Log the underlying typed cause and stack trace, but render only localized actionable text.

- [ ] **Step 5: Add the recipe-library commands without disturbing create**

Add one overflow menu beside the existing create icon.
Add `Back up library` and `Restore backup` items, each routed through `LibraryBackupLauncher` with its matching action.
Leave the existing create button, row actions, pane thresholds, and state fields unchanged.
Do not reload `RecipeLibraryCubit` after backup.

- [ ] **Step 6: Add complete English and Korean copy**

Add keys for both menu labels, progress labels, destructive title and body, confirm and cancel actions, backup saved, restore complete, and one actionable message for every non-cancelled failure kind.
The incompatible-schema message must ask the operator to update PrepBook.
The recovery-failed message must say that the library could not be reopened and that retry is available, without revealing file or SQL details.
Run `flutter gen-l10n` and modify generated files only through that generator.

- [ ] **Step 7: Prove responsive and state-preservation behavior**

At compact and expanded widths with the existing large text scale, verify that the menu, confirmation, progress, and messages render without clipping and remain reachable.
Enter a query, select a recipe in expanded mode, scroll the list, complete backup, and require query, selection, and scroll offset to remain unchanged.
Cancel both native-adapter fakes and require the library to remain interactive.
Simulate restore completion and require the old transient tree to be replaced by a fresh library that shows the one-time completion notice.

- [ ] **Step 8: Verify presentation**

Run:

```sh
flutter test test/presentation/library_backup test/presentation/recipe_library/recipe_library_page_test.dart test/presentation/presentation_boundary_test.dart test/app/view/app_test.dart
```

## Task 8: Prove the complete backup and restore round trip

**Files:**

- Create: `test/backup/library_backup_round_trip_test.dart`
- Modify only if a test exposes a scoped defect: files already owned by Tasks 1 through 7

- [ ] **Step 1: Build a complete source library fixture**

Store rows in all six schema tables: `ingredients`, `recipes`, `recipe_components`, `production_runs`, `run_acknowledgements`, and `run_overrides`.
Include multiple recipe revisions, archived data, a custom unit, a non-terminating rational, warnings, acknowledgements, overrides, and a historical run.

- [ ] **Step 2: Export from a live WAL database**

Open the source through the real FFI factory, force WAL content to exist, create a backup through the real snapshotter and codec, and retain the source connection.
Require archive creation not to close or replace that connection.

- [ ] **Step 3: Restore into a different live library**

Populate a target database with distinct sentinel rows.
Restore the archive through the real codec, validator, files implementation, session, and gateway.
Require activation without process restart and require the rebuilt repositories to return source-library objects rather than sentinels.

- [ ] **Step 4: Compare complete persisted state**

Query all six tables from source and restored databases with deterministic ordering and compare every column value.
Also compare every reconstructed ingredient, every recipe revision, and every production run.
Do not treat raw equality alone as codec validation or repository equality alone as proof that no table row was omitted.

- [ ] **Step 5: Make the end-to-end comparison fail once**

Delete or replace one target fixture row after restore and require the table comparison to fail with the affected table named.
Restore the unmodified path and rerun:

```sh
flutter test test/backup/library_backup_round_trip_test.dart
```

## Task 9: Complete repository gates and native acceptance

**Files:**

- Modify: `README.md`
- Inspect: every changed and untracked path in the repository

- [ ] **Step 1: Run scoped formatting and static checks**

Run:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
dart run bloc_tools:bloc lint .
```

If formatting reports changes, run `dart format` with explicit `lib` and `test` paths, inspect the resulting diff, and rerun the no-change check.

- [ ] **Step 2: Run full randomized tests and inspect what coverage reached**

Run:

```sh
very_good test --coverage --test-randomize-ordering-seed random
```

Require the repository's reached-line coverage gate to remain at `100` percent.
Separately confirm that every new production Dart file appears in coverage input or has a direct test proving its behavior.

- [ ] **Step 3: Run Trunk on explicit changed paths**

Build the path list from the union of tracked changes and untracked files, inspect it for unrelated paths, and pass only that explicit list to Trunk.
Run `trunk fmt` first and `trunk check` second.
Run `git diff --check` after formatting.

- [ ] **Step 4: Verify the iOS Simulator native picker flow**

Check `uptime` and queue the job if one-minute load exceeds the CPU core count.
Use the repository's iOS development flavor on one Simulator through the approved native-tool worker.
Save a backup to a system-visible location, change the library, pick the saved backup, confirm restore, and observe source data without restarting.
Cancel both save and open pickers in separate runs and require the library to remain usable.
Do not treat an injected widget test as native document-provider evidence.

- [ ] **Step 5: Verify the Android Emulator native picker flow**

After the iOS job has fully stopped, check `uptime` again and run one Android Emulator job.
Repeat save, mutate, pick, confirm, immediate restored-data observation, save cancellation, and open cancellation.
Record emulator identity, build flavor, observable results, and any platform limitation.

- [ ] **Step 6: Update status only after automated and native behavior is green**

Change the README feature status from planned or pending to implemented only after Tasks 1 through 8 and both native acceptance passes succeed.
Keep the edit limited to backup and restore status and verification evidence.

- [ ] **Step 7: Inspect final scope without mutating Git**

Run:

```sh
git -C /Users/dongminyu/Development/01_personal/prep_book status --short
git -C /Users/dongminyu/Development/01_personal/prep_book diff --stat
git -C /Users/dongminyu/Development/01_personal/prep_book diff --check
```

Inspect staged, unstaged, and untracked paths separately.
Do not create commits as part of this plan execution unless the operator separately approves a commit plan.

## Completion Evidence

The implementation is complete only when the executor can report all of the following from concrete checks:

- The resolved direct versions of `archive` and `file_picker`.
- The archive guard matrix and its deliberate failure probes.
- The candidate validator's all-row reach, dangling-reference acceptance, and cycle rejection.
- The snapshot concurrency result.
- The full restore fault matrix, including preserved diagnostics on recovery failure.
- The six-table FFI round trip and its deliberate negative control.
- English and Korean compact and expanded widget results.
- Static analysis, Bloc lint, randomized full-suite, reached-line coverage, Trunk formatting, Trunk checks, and `git diff --check` results.
- Separate iOS Simulator and Android Emulator native picker observations.
- Final Git scope with no claim of a commit, push, physical-device install, or release unless separately authorized and performed.

## Deferred Git Checkpoints

This plan intentionally does not prescribe automatic commits.
If commit authority is granted after implementation, group the verified diff by application and dependency contract, backup infrastructure, bootstrap composition, presentation and localization, and completion evidence.
Show the exact staging plan before staging any path.
