# Championship Workflow Design Implementation Plan

## Contract

Use `docs/specs/2026-09-17-championship-workflow-design.md` as the approved scope.
Keep existing extraction, review, calculation, and export behavior.

## Steps

1. Update the Championship theme and workflow shell in `lib/championship/view/championship_app.dart` and `championship_demo_page.dart`.
   Verify the first viewport and the step layout in `test/championship/view/championship_demo_page_test.dart`.
2. Apply the shared control styling and responsive content layout to the source, review, target, and result panels.
   Verify the sample workflow and exact result in `test/championship/view/championship_workflow_test.dart`.
3. Update the short brand copy in `championship_strings.dart` and its copy test.
4. Add the connector and outlined border regression checks.
   The connector test failed before the implementation because the keyed connector was absent.
5. Format the changed Dart paths.
   Run `flutter analyze`, Championship tests, the full Flutter suite, API tests, Bloc lint, and the Championship web release build.
6. Inspect local desktop and compact browser renders, then complete a read-only review of the scoped diff.
7. Commit the UI contract and implementation, open a pull request, and verify current-head CI and hosted review.

## Boundaries

Stage only the Championship UI files, their tests, and these two documents.
Leave other modified files and local QA captures outside the commit.
The operator retains the merge decision.
