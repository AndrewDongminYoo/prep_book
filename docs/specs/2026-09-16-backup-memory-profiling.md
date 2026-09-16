# Backup Memory Profiling

## Status

Approved by the operator's request to continue `pr-loop` with the prepared iOS Simulator and Android Emulator on 2026-09-16.

## Problem

Issue #31 asks for evidence that the 256 MiB backup limit is safe on supported iOS and Android device classes.
PR #30 already changed rollback copies to stream through files and transferred ownership of internally generated archive and decoded database buffers.
The remaining decision must therefore start with measurement instead of another speculative refactor.

## Goal

Create a repeatable development-only harness that measures the PrepBook app process while a valid near-limit library passes through backup creation, native save and pick handoffs, archive decoding, candidate validation, successful restore, and rollback recovery.
Record one iOS Simulator result and one Android Emulator result before changing the supported limit.
An observed Android out-of-memory failure in the native byte-channel save path permits one bounded streaming correction with a failing regression and repeat measurements.

## Scope

- Generate a valid current-schema SQLite fixture near a requested byte size without first constructing an equally large Dart buffer.
- Validate the generated fixture through `BackupDatabaseValidator` before profiling it.
- Sample app-process resident memory from a helper isolate while the main isolate performs synchronous archive work.
- Exercise the production backup codec, snapshotter, database validator, session replacement, file-picker adapter, and rollback path.
- Record the fixture size, archive size, baseline, peak, ending resident memory, platform, runtime, build mode, and measurement caveats.
- Change `maxLibraryBackupBytes` only when the two measurements justify it; correct an observed platform failure with its own regression and repeat run.

## Non-goals

- Do not claim that Simulator or Emulator evidence proves physical-device safety.
- Do not close Issue #31 in this milestone.
- Do not use the daily physical iPhone or any physical Android device.
- Do not weaken CRC, declared-size, actual-size, SQLite integrity, foreign-key, domain, exact-schema, or atomic-replacement checks.
- Do not add a user-visible profiling screen or ship profiling code in `lib/`.
- Do not profile CPU stacks with ETTrace or diagnose leaks that this bounded RSS run does not reveal.

## Fixture contract

The generator creates the production schema through `openPrepBookDatabase` and inserts one valid ingredient row.
It fills a temporary table with high-entropy SQLite `randomblob` values in bounded transactions, disables secure deletion for the fixture connection, and drops the temporary table after reaching the target size.
The final database keeps the random free pages without retaining an extra table, so the exact production schema remains valid and ZIP compression cannot turn the fixture into a half-size archive.
The generator checkpoints the WAL before measuring the main database file, stops at or above the requested size without crossing the application limit, drops the temporary table, closes the writer, and validates the result through the production restore validator.

Tests use a small target.
The device runs use an explicit near-limit target and report the actual size rather than assuming that the requested size was reached exactly.

## Measurement contract

Each named phase starts from a recorded RSS baseline and samples `ProcessInfo.currentRss` from a helper isolate at a fixed interval while the operation runs.
Each result reports baseline, peak, ending RSS, elapsed time, and sample count.
The harness prints one machine-readable JSON report after the run.

The native picker phases use the production `FilePickerLibraryBackupPlatform` path.
External automation may select or save the fixture, but it must not replace the adapter with a memory-only fake for the reported native result.
The rollback phase deliberately fails activation after replacement and verifies that the original database is reopened and readable.

## Acceptance criteria

- A focused host test first fails against an unimplemented generator and then proves that a small fixture reaches its requested size, stays below the configured maximum, remains at least 90 percent of the database size after ZIP encoding, uses the current schema, and passes `BackupDatabaseValidator`.
- The profiling harness compiles for the development flavor on iOS Simulator and Android Emulator.
- One near-limit run on each platform reports every named phase with the exact fixture and archive sizes.
- The corruption, oversize, cancellation, validation, and rollback regression suites remain green.
- Any production change is tied to an observed phase and has a regression that fails without the fix.
- The final report labels physical-device safety as unverified and leaves Issue #31 open unless later evidence satisfies its complete contract.

## Visual approval

Visual approval is not required because the milestone changes no rendered application output.
Native picker interaction is runtime evidence, not a UI design review.
