# Production History Implementation Plan

## Contract

Implement `docs/specs/2026-09-16-production-history.md` on `feat/production-history`.
Keep stored runs immutable and reopen only the stored snapshot.
Do not modify the separate `fix/cold-start-findings` worktree.

## Owned paths

- `lib/persistence/**` and focused persistence tests for schema version 2 and summary metadata.
- `lib/presentation/production_history/**` and focused presentation tests for the history flow.
- `lib/app/view/app.dart`, `lib/main_development.dart`, `lib/main_staging.dart`, and `lib/main_production.dart` for composition.
- `lib/presentation/recipe_library/view/recipe_library_page.dart` and its focused test for the route entry point.
- `lib/l10n/arb/app_en.arb` and `lib/l10n/arb/app_ko.arb` for user-facing strings.
- `README.md` and `CLAUDE.md` for current-state corrections.

## Steps

1. Add failing persistence tests for version 1 backfill, fresh and upgraded catalog equality, summary metadata, draft derivation, and payload-free version 2 listing.
2. Run the focused persistence tests and record the expected RED failures caused by the absent schema version 2 contract.
3. Implement schema version 2, data backfill, exact current-catalog validation, and summary metadata writes and reads.
4. Run the focused persistence tests until they pass.
5. Add failing cubit and widget tests for history loading, empty, failure, retry, localized row content, stored-snapshot opening, and missing-run handling.
6. Run the focused presentation tests and record the expected RED failures caused by the absent production history surface.
7. Implement the smallest history cubit, route launcher, page, localization entries, recipe-library action, and composition-root wiring that pass those tests.
8. Run `flutter gen-l10n` and rerun the focused presentation and app tests.
9. Update `README.md` and `CLAUDE.md` only where they still describe production history as absent.
10. Run explicit-path formatting and checks, `flutter analyze`, Bloc lint, and `very_good test --coverage`.
11. Review the full diff against the frozen specification.
12. Capture rendered history evidence and request operator visual approval for the final head.
13. Create concern-based commits, push, open the PR, and observe current-head CI and hosted reviews within the recorded public-repository budget.
14. Stop at `ready` and request an operator merge with the verified head and recommended merge method.

## Verification

```sh
flutter test test/persistence/schema_upgrade_test.dart test/persistence/production_run_repository_test.dart test/backup/database_validator_test.dart
flutter test test/presentation/production_history/production_history_cubit_test.dart test/presentation/production_history/production_history_page_test.dart test/presentation/recipe_library/recipe_library_page_test.dart test/app/view/app_test.dart
flutter gen-l10n
dart format <changed-dart-paths>
flutter analyze
dart run bloc_tools:bloc lint .
very_good test --coverage --test-randomize-ordering-seed random
trunk fmt <changed-paths>
trunk check <changed-paths>
```

The focused RED runs must fail because the required behavior is absent, not because dependencies or generated localizations are missing.
The final visual check must use rendered output from the candidate head.
