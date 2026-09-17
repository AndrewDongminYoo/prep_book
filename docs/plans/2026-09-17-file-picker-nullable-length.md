# File Picker 13 Nullable Length Delivery Plan

## Contract

Implement `docs/specs/2026-09-17-file-picker-nullable-length.md` on branch `fix/file-picker-nullable-length`.
Preserve the six existing workspace changes while verifying and finishing them.

## Steps

1. Inspect the existing diff and the installed `file_picker` 13.1.0 API.
   Verify that both length methods return nullable values and that the dependency lockfile resolves.
2. Strengthen the focused image regression so it records a byte-read attempt.
   Make a scoped mutant call `readAsBytes()` on the `null` path and confirm that the regression fails for the intended reason.
3. Keep the smallest production handling for `null` length in `lib/championship/input/file_picker_recipe_image_picker.dart` and `lib/presentation/library_backup/view/library_backup_platform.dart`.
   Run the focused image and backup platform tests, including existing success and oversize cases.
4. Run `flutter pub get`, scoped `dart format`, `flutter analyze`, Bloc lint, and `very_good test --coverage --test-randomize-ordering-seed random`.
   Check a championship web build because the image picker is used by that entrypoint.
5. Review the complete candidate against the contract.
   Commit the dependency upgrade and compatibility behavior in coherent groups, push the branch, and open a PR against `main`.
6. Observe current-head CI and hosted review within the recorded round budget.
   Stop at the operator merge boundary after the readiness gates pass.

## Owned paths

- `pubspec.yaml` and `pubspec.lock`.
- `lib/championship/input/file_picker_recipe_image_picker.dart` and its focused test.
- `lib/presentation/library_backup/view/library_backup_platform.dart` and its focused test.
- This specification and plan.

## Verification limits

Focused tests use injected picker files.
They do not prove native system-picker or browser-dialog behavior, which requires a separate runtime pass.
