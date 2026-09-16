# Production History

## Status

Approved by the operator's request to run the next unimplemented product milestone through `pr-loop` on 2026-09-16.

## Problem

The approved product design requires a production history screen.
The application and persistence layers can list and reopen stored runs, but the presentation layer exposes no history route.
The current summary contract also omits the stored recipe name and warning state that the screen must show.

## Scope

- Add a read-only production history route from the recipe library.
- Show the stored recipe name, recipe revision, target yield, creation time, and whether the run was saved as a draft.
- List runs in the repository's established newest-first order.
- Reopen the stored snapshot in the existing production-sheet preview so the operator can share or print it again.
- Add schema version 2 metadata that lets the history list avoid decoding every `result_json` payload.
- Upgrade version 1 databases and backups to version 2 without losing stored runs.
- Validate the exact version 2 SQLite catalog after fresh creation and after upgrade.
- Localize every new user-facing string in English and Korean.

## Non-goals

- Do not edit, acknowledge, override, recalculate, or delete a stored run.
- Do not add history search, filters, pagination, grouping, or bulk actions.
- Do not change the production-sheet format or export behavior.
- Do not change issue `#12` or add an editable-history use case.
- Do not change the separate `fix/cold-start-findings` worktree.
- Do not add a dependency.

## Data contract

`ProductionRunSummary` adds the stored recipe name and a draft flag.
The draft flag means that one or more blocking warnings remain unacknowledged.
The summary never reads the current recipe library.

Schema version 2 adds `recipe_name` and `blocking_warning_count` to `production_runs`.
The repository writes both values from the immutable snapshot in the same transaction as the run.
The history query derives the draft flag by comparing `blocking_warning_count` with stored acknowledgements for blocking warning kinds.
This derivation keeps the summary correct if the existing repository acknowledgement method is used later.

The version 1 upgrade decodes each stored payload through the existing production-run codec before it backfills the two metadata columns.
An invalid payload aborts the upgrade.
The upgraded catalog and a freshly created version 2 catalog must match the same exact schema declaration.

## Presentation contract

The recipe library app bar exposes one history action with a localized tooltip.
The history screen has loading, loaded, empty, and failure states.
The failure state offers a retry.

Each loaded row shows:

- The stored recipe name.
- The stored recipe revision.
- The target yield.
- The creation date and time in the active locale.
- A localized `Draft` or `Ready` status.

Activating a row loads the run by its stored identifier.
If the run exists, the existing production-sheet preview opens with that exact snapshot.
If the run disappeared or the read fails, the current screen remains visible and shows a localized message.

## Acceptance criteria

- A version 1 database with a stored run upgrades to version 2 and returns the correct recipe name and draft state from `listSummaries`.
- A fresh version 2 database and an upgraded version 2 database pass the same exact-catalog validation.
- Missing, changed, and unexpected version 2 catalog objects remain rejected by backup validation.
- The summary query does not decode `result_json` after version 2 metadata exists.
- The history screen renders newest-first rows with every required field in English and Korean.
- The history screen renders loading, empty, failure, and retry behavior.
- A history row opens the exact stored snapshot in the production-sheet route.
- A missing or unreadable stored run produces a visible failure without opening another route.
- The existing mobile flows, backup and restore, and championship boundary remain unchanged.

## Visual approval

Operator visual approval is required because this milestone adds a screen and a recipe-library app-bar action.
The final review artifact must show the history entry point and the loaded history screen at the reviewed head SHA.
