# File Picker 13 Nullable Length Compatibility

## Status

Approved by the operator's request to finish and upload the existing workspace change on 2026-09-17.

## Problem

The workspace upgrades `file_picker` from 12.3.0 to 13.1.0.
The selected-file API now returns `int?` from `length()` and `lengthSync()`.
The championship image picker and the mobile library backup picker must handle a file whose length cannot be determined.

## Scope

- Keep the existing image and backup selection behavior when a length is available.
- Reject an image with an unavailable length as `RecipeImagePickerFailure.missingBytes` before reading its bytes.
- Reject a backup with an unavailable length as `LibraryBackupFailureKind.restoreFailed` before opening its byte stream.
- Update the direct dependency and lockfile together.
- Cover both unavailable-length paths with focused tests that observe whether reading starts.

## Non-goals

- Change the image size limit, supported formats, backup format, or restore transaction.
- Change screen copy, layout, or other user interface behavior.
- Add another dependency or a new file-picker abstraction.

## Acceptance

1. An image picker file with a `null` length produces `missingBytes` without calling `readAsBytes()`.
2. A backup picker file with a `null` length produces `restoreFailed` without opening its stream.
3. Existing successful selection and oversize rejection tests still pass.
4. The resolved dependency graph matches `pubspec.yaml`, and the project's format, analysis, lint, and test gates pass.
