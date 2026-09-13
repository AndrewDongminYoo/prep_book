# Library Backup and Restore Specification

**Status:** approved 2026-09-13.
**Authority:** `docs/notes/2026-09-06-prepbook-pro-design.md` is the product source of truth.
This document specifies the portable library backup that the product design includes in the first release.

## Purpose

Let the operator save the complete local PrepBook library as one portable file and replace the current library from a valid backup without risking the current data.
The feature must work offline on the supported iOS and Android targets.

## Approved direction

The operator approved these decisions on 2026-09-12:

- One versioned `.prepbook` file contains a manifest and a SQLite snapshot.
- Restore validates the archive schema and the complete candidate database before it changes the live database.
- A failed restore leaves the live database unchanged.
- A successful restore reconnects the application to the new database immediately and starts a fresh library screen.

## Scope

In scope:

- Export all stored ingredients, all recipe revisions, all production runs, acknowledgements, and overrides.
- Save the archive through the native system file interface.
- Pick one archive through the native system file interface.
- Confirm the destructive replacement before restore starts.
- Validate the archive structure, format version, database schema, SQLite integrity, foreign keys, stored domain objects, and the current recipe graph.
- Replace the live database only after validation succeeds.
- Reopen the new database and rebuild the application over new repositories.
- Recover the previous database if the final replace or reopen step fails.
- Report cancellation separately from failure.
- Provide English and Korean interface copy.

Out of scope:

- Merging one library into another.
- Selecting only recipes or only production history.
- Scheduled or automatic backups.
- Cloud storage integration beyond locations that the system picker already exposes.
- Backup encryption, passwords, or account-based key recovery.
- Importing spreadsheets, PDFs, or a raw SQLite file that is not inside a PrepBook archive.
- Editing a backup or promising that its internal files are a public interchange format.
- Desktop and web support.

## Approaches considered

### Chosen: manifest plus SQLite snapshot

The archive contains the exact database snapshot and a small manifest.
This preserves every stored row without a second serialization model.
The candidate database can reuse the existing repository mappers and domain constructors during validation.
It also uses the path seam that `openPrepBookDatabase` already provides for validate-then-swap restore.

### Rejected: raw SQLite file

A bare database file has the smallest implementation, but it has no application-format envelope.
It cannot distinguish a PrepBook backup version from an unrelated SQLite database before opening it.
It also gives future archive migrations no manifest-level version.

### Rejected: logical JSON export

A logical export can avoid carrying a SQLite file, but it creates a second mapping for every table and stored object.
That mapping would duplicate the tested persistence codecs and would need its own migration rules before the first backup ships.
The first release gains no user-visible benefit from that duplication.

## Dependencies

Add `file_picker` as the one platform dependency for opening and saving a backup through native pickers.
The current `file_picker` 12 API supports `pickFile()` and `saveFile()` on iOS and Android.
Its iOS implementation requires iOS 14 or later, while this repository targets iOS 15.

Add `archive` as a direct dependency because production code will import it to encode and decode ZIP content.
`archive` already appears transitively in the current lockfile, but a transitive dependency is not an API contract that application code can import safely.

Do not add a second SQLite implementation, a filesystem abstraction package, a cryptography package, or a state-management package.
The existing `sqflite`, `dart:io`, `dart:convert`, and Bloc APIs cover the remaining work.

## Archive format version 1

The external filename ends in `.prepbook`.
The suggested filename is `prepbook-backup-YYYYMMDD-HHmmss.prepbook`, where the timestamp is the backup creation time in local calendar fields.
The manifest still records the instant in UTC.

The file is a ZIP archive with exactly two regular files at its root:

```log
manifest.json
library.db
```

Directories, symbolic links, duplicate names, nested paths, and additional entries are invalid.
The decoder reads the two named entries directly and never extracts an archive path to disk.
This keeps path traversal outside the restore surface.

`manifest.json` has this version 1 shape:

```json
{
  "format": "prep_book_backup",
  "formatVersion": 1,
  "databaseSchemaVersion": 1,
  "createdAtUtc": "2026-09-12T12:34:56.000Z",
  "databaseEntry": "library.db"
}
```

Every field is required.
Unknown manifest fields are ignored so a compatible writer can add metadata later.
An unknown `format`, unsupported `formatVersion`, future `databaseSchemaVersion`, invalid UTC timestamp, or different database entry name is rejected before the candidate database is opened.

ZIP entry CRC validation detects accidental archive damage.
The SQLite and domain validation stages remain mandatory because an intact ZIP can still contain an invalid database.
Version 1 does not add a cryptographic signature because the product has no account, trusted sender, or key-recovery system.

The implementation must inspect the declared uncompressed size before it materializes an entry.
The initial release limits both the archive file and the uncompressed database entry to 256 MiB.
This is a defensive input limit, not a statement about expected customer data size.
A later change can raise it with device-memory evidence.

## Module boundaries

`lib/application/` owns two use cases and the interface that backs them:

- `CreateLibraryBackup` returns immutable archive bytes and the suggested filename.
- `RestoreLibraryBackup` accepts archive bytes and completes only after the new library is active.
- `LibraryBackupGateway` is the application-facing interface that both use cases call.
- Typed backup errors are part of the use-case contract so presentation code can select localized messages without importing infrastructure.

The application interface uses `Uint8List`, value objects, and typed backup errors.
It does not name Flutter, `sqflite`, `file_picker`, paths, files, ZIP entries, or concrete repositories.
The current application boundary test remains unchanged.

`lib/backup/` owns the infrastructure implementation:

- `BackupArchiveCodec` encodes and decodes the versioned archive.
- `BackupDatabaseValidator` validates a candidate database through SQLite checks and the existing persistence readers.
- `DatabaseLibraryBackupGateway` creates snapshots and performs validate-then-swap restore through the active database session.
- The implementation maps archive, SQLite, and filesystem exceptions to the typed application errors.

`lib/bootstrap.dart` remains the composition root.
It owns the live database path, database connection, repository instances, and the callback that mounts a rebuilt application.
The backup gateway receives that session instead of discovering global state.
Only one backup or restore operation can run at a time.

`lib/presentation/library_backup/` owns the operator flow:

- `LibraryBackupCubit` holds picker and operation state.
- `LibraryBackupPlatform` is the test seam for native open and save calls.
- `FilePickerLibraryBackupPlatform` is the only type that imports `file_picker`.
- `LibraryBackupLauncher` opens the flow from the recipe library.

The presentation layer receives the two use cases and the platform adapter.
It does not import persistence, `sqflite`, `archive`, or `dart:io`.
The presentation boundary allowlist needs only the new `file_picker` package prefix for the adapter.

## Creating a consistent snapshot

The application owns one `sqflite` connection to the live database.
Every current repository uses that connection.
The backup session serializes backup and restore operations so two file operations cannot overlap.

`CreateLibraryBackup` performs these steps:

1. Ask the live connection to checkpoint and truncate any WAL content.
2. Start an exclusive SQLite transaction on the owned connection without writing data.
3. Read the main database bytes while that transaction prevents another write through the connection.
4. End the transaction.
5. Write the bytes to a candidate file under the application database directory.
6. Open and validate that candidate through the same validator that restore uses.
7. Encode the validated bytes with the manifest.
8. Remove the candidate file in a `finally` path.

The implementation must not copy the live database without the checkpoint and lock.
SQLite documents that a file copied while another write transaction is active can combine old and new content or lose required WAL content.
The application-owned single connection is the condition that makes the checkpoint followed by the exclusive lock sufficient here.

The live connection stays open, so creating or saving a backup does not rebuild the application and does not discard the current library search or scroll state.
The platform save dialog runs only after the archive bytes are ready.
Picker cancellation discards the bytes and returns the cubit to idle without an error message.

## Restore flow

The operator flow is deliberately replace-only:

1. The operator selects `Restore backup` from the library app bar menu.
2. The native picker returns one `.prepbook` file or a cancellation.
3. The application checks the selected file size before reading all bytes.
4. The interface shows a confirmation that restore replaces all current recipes and production history.
5. Cancellation returns to the unchanged library.
6. Confirmation starts validation and replacement behind a blocking progress state.
7. Success rebuilds the application at a fresh recipe library screen and announces completion.
8. Failure keeps or recovers the previous library and shows an actionable localized error.

The confirmation does not offer merge or selective restore.
The confirm action cannot be submitted twice.
Back navigation and the app bar actions are disabled while the swap is in progress.

## Candidate validation

Restore writes `library.db` to a unique candidate path inside the application database directory.
Keeping the candidate on the same filesystem as the live database makes the final rename atomic at the filesystem level.

The validator performs these checks in order:

1. Read `PRAGMA user_version` without upgrade callbacks, require it to equal the manifest value, and reject zero or a version above `currentSchemaVersion`.
2. Open the candidate through `openPrepBookDatabase` with `singleInstance: false` so supported schema upgrades apply only to the candidate.
3. Require `PRAGMA integrity_check` to return `ok`.
4. Require `PRAGMA foreign_key_check` to return no rows.
5. Read every ingredient identifier and reconstruct every ingredient through `SqfliteIngredientRepository`.
6. Read every recipe `(id, revision)` pair and reconstruct every revision through `SqfliteRecipeRepository`.
7. Read every production run identifier and reconstruct every run through `SqfliteProductionRunRepository`.
8. Build the latest-revision recipe index and reject every cycle that `RecipeDependencyGraph.findCycleFrom` reports.
9. Close the candidate before replacement.

The repository reads are load-bearing validation.
They exercise quantity, unit, timestamp, warning, override, snapshot, and result codecs instead of trusting that table columns merely exist.

Missing ingredient or recipe references are not automatically corruption.
The current application permits an operator-confirmed ingredient deletion to leave a dangling ingredient reference, and archived or historical data can name unavailable dependencies.
The validator therefore rejects cycles and malformed stored objects, but it does not change the existing missing-dependency policy.

## Validate-then-swap replacement

No live file changes before candidate validation and operator confirmation both succeed.
The database session then performs this sequence:

1. Close the candidate connection.
2. Close the live connection and wait for the close to complete.
3. Remove closed connection sidecar files that belong to the candidate and live paths.
4. Copy the live database to a unique rollback path and flush that copy.
5. Atomically rename the validated candidate over the live database path.
6. Open the live path through `openPrepBookDatabase`.
7. Build new repository instances over the new connection.
8. Build and mount a fresh application root.
9. Delete the rollback copy only after the new root is mounted.

If rename, reopen, repository construction, or application construction fails after the live connection closes:

- Close any partially opened candidate connection.
- Atomically restore the rollback copy to the live path.
- Reopen the previous database.
- Rebuild the application over the previous repositories.
- Throw a typed restore failure after the previous library is active again.

If rollback reopen also fails, mount the existing startup failure application and preserve both database files for diagnosis.
Do not delete the only readable copy to make cleanup appear successful.

## Bootstrap and application rebuilding

The composition root separates one-time preparation from application construction.
The development flavor currently seeds data inside its builder.
That seed must become an initial-prepare callback so a restored development database is not modified before the restored screen appears.

Initial startup performs these steps:

1. Open the live database.
2. Run the flavor-specific prepare callback once.
3. Construct repositories and backup use cases.
4. Build and mount the application.

Successful restore skips the prepare callback.
It reconstructs repositories and use cases, resets navigation to the recipe library, and mounts the new root.
Startup retry still repeats the complete initial startup path.

The existing in-flight startup guard remains.
The database session adds a separate in-flight backup guard so repeated menu taps join or reject the current operation rather than opening overlapping database sessions.

## Presentation behavior

Add an overflow menu to the recipe library app bar beside the existing create action.
The menu contains `Back up library` and `Restore backup`.
The create action remains unchanged.

Backup behavior:

- Show blocking progress while the archive is created.
- Open the native save interface with the suggested `.prepbook` filename.
- Show a localized success message after the platform confirms that it saved the file.
- Treat picker cancellation as a neutral outcome.
- Keep the current recipe selection, search text, and scroll position.

Restore behavior:

- Pick one `.prepbook` file before showing the destructive confirmation.
- Name both recipes and production history in the confirmation.
- Show one blocking progress state for validation and replacement.
- Reset navigation and transient presentation state after success.
- Keep the current screen and presentation state after every pre-swap failure.

Errors do not expose file paths, SQL, exception class names, or stack traces.
Logs keep the underlying error and stack trace for diagnosis.

## Failure taxonomy

The interface distinguishes these outcomes:

- `cancelled`: the operator dismissed a picker or confirmation, so no error is shown.
- `unsupportedFormat`: the file is not a supported PrepBook archive version.
- `invalidArchive`: the ZIP or manifest is malformed, incomplete, duplicated, or unsafe.
- `backupTooLarge`: the selected or expanded content exceeds the input limit.
- `invalidDatabase`: SQLite integrity, foreign keys, stored values, or recipe-cycle validation failed.
- `incompatibleSchema`: the database schema is newer than this application supports.
- `saveFailed`: archive creation succeeded, but the system did not save it.
- `restoreFailed`: replacement failed, but the previous library was recovered.
- `recoveryFailed`: neither the new nor previous database could be activated, so the startup failure screen is mounted.

The English and Korean strings state the next action where one exists.
For example, an incompatible schema asks the operator to update PrepBook rather than retry the same file.

## Testing strategy

### Archive codec tests

- Round-trip a fixed manifest and fixed database bytes.
- Reject each missing required entry and field.
- Reject duplicate entries, nested paths, symbolic links, added entries, invalid timestamps, unsupported versions, future schema versions, corrupt ZIP data, and both size-limit paths.
- Make each archive guard fail with a deliberately malformed fixture before trusting its passing case.

### Database validation tests

- Validate a database that contains every stored object kind, including a non-terminating rational quantity, custom units, archived revisions, warnings, acknowledgements, and overrides.
- Corrupt one value for each existing persistence codec and require validation to fail.
- Reject `integrity_check`, `foreign_key_check`, and a current recipe cycle.
- Accept an operator-created dangling ingredient reference because current product behavior permits it.
- Prove that every row, not only the latest recipe and newest run, is read.

### Snapshot and swap tests

- Write during an attempted snapshot and prove that the captured database is one complete state.
- Force candidate validation to fail and compare the live database bytes and loaded objects before and after.
- Force failure before rename, during rename, after rename, during reopen, and during rebuild.
- Prove that each failure either leaves the original live file untouched or restores the rollback copy.
- Make the unchanged-database assertion fail once by replacing the fixture before trusting its passing result.
- Prove that successful restore activates the candidate data and removes temporary files.
- Prove that a recovery failure preserves diagnostic copies.

### Application and presentation tests

- Keep application use cases independent of Flutter, files, ZIP, and SQLite.
- Verify backup success, cancellation, busy-state de-duplication, and each typed error state in the cubit.
- Verify the restore warning names both recipes and production history.
- Verify that cancellation performs no restore call.
- Verify that controls are disabled during a restore.
- Verify that backup keeps query, selection, and scroll state.
- Verify that restore success mounts a fresh library whose visible data comes from the candidate database.
- Verify English and Korean labels and messages.
- Exercise compact and expanded widths at the existing large text scale used by presentation tests.

### Platform acceptance

Automated tests use injected picker functions and the FFI database factory.
They do not prove native document-provider behavior.

Before completion, verify these flows on one iOS Simulator and one Android Emulator:

- Save a backup to a system-visible location.
- Change the library.
- Pick the saved backup.
- Confirm restore.
- Observe the restored library without restarting the app.
- Cancel both native pickers and confirm that the library remains usable.

A physical-device pass is separate release evidence and is not required by this implementation task unless the operator asks for it.

## Expected implementation scope

Likely new paths:

- `lib/backup/**`
- `lib/application/library_backup.dart`
- `lib/presentation/library_backup/**`
- Matching tests under `test/backup/`, `test/application/`, and `test/presentation/library_backup/`

Likely modified paths:

- `pubspec.yaml` and `pubspec.lock`
- `lib/bootstrap.dart`
- The three flavor entrypoints
- `lib/app/view/app.dart`
- `lib/application/application.dart`
- `lib/presentation/presentation.dart`
- `lib/presentation/recipe_library/view/recipe_library_page.dart`
- English and Korean ARB files
- Boundary tests whose explicit allowlists or roots gain the new unit
- `README.md` status after the feature is complete

The work must not refactor the existing editor, production calculation, PDF export, or persistence codecs except where the backup session needs an explicit validation seam.

## Verification

The minimum complete gate is:

```sh
flutter pub get
dart format --output=none --set-exit-if-changed lib test
flutter analyze
dart run bloc_tools:bloc lint .
very_good test --coverage --test-randomize-ordering-seed random
trunk check <explicit changed paths>
```

The dependency graph must show `file_picker` and `archive` as direct dependencies at the resolved versions.
The coverage result proves only the reached Dart lines.
The restore invariants require the explicit fault-injection tests and the two native picker passes listed above.

## Definition of done

- The operator can save one `.prepbook` archive through the native picker on iOS and Android.
- The archive contains the complete stored library and production history.
- A valid archive restores and becomes visible without an application restart.
- Every invalid candidate fails before the live database changes.
- Every injected swap failure preserves or recovers the previous library.
- Cancellation is neutral and retry remains available.
- Backup preserves the current library presentation state.
- English and Korean interfaces are complete.
- Static analysis, Bloc lint, the full test suite, the coverage gate, and scoped Trunk checks pass.
- Simulator and emulator evidence confirms the real native picker flows.

## Sources and precedent

- Product authority: `docs/notes/2026-09-06-prepbook-pro-design.md`.
- Persistence path seam and transaction contract: `docs/specs/2026-09-07-persistence-layer.md`.
- Application boundary and deferred attachment point: `docs/specs/2026-09-08-application-layer.md`.
- Native picker support and current API: <https://pub.dev/packages/file_picker>.
- ZIP streaming and path-safety considerations: <https://pub.dev/documentation/archive/latest/>.
- Safe SQLite backup methods and journal constraints: <https://www.sqlite.org/howtocorrupt.html> and <https://www.sqlite.org/backup.html>.
- Oracle project precedent: `[TOOL_FAILED]` because the required local Oracle transport did not initialize on 2026-09-12.
  This result does not mean that no precedent exists.
