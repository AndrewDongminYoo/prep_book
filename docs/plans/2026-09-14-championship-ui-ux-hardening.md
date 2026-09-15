# Championship Review UI and Accessibility Hardening Implementation Plan

> **Execution rule:** Implement this plan inline with `superpowers:test-driven-development`.
> Add one failing behavior test before each production change, run the narrow test to prove the failure, implement the minimum code, and rerun the same test before continuing.

**Goal:** Close the four approved championship review findings without expanding the feature set or changing normal mobile behavior.

**Architecture:** Keep review invariants in `ReviewRecipeDraft`, verification semantics in `RecipeDraftVerifier`, localized presentation and focus recovery in the championship review widgets, and browser DOM access in `lib/main_championship.dart`.
The Cubit remains responsible for workflow state, while widgets remain responsible for focus and scrolling.

**Tech stack:** Dart 3.12, Flutter 3.44 or later, Material 3, `flutter_bloc`, `package:web`, Flutter Test, and the existing PrepBook championship architecture.

**Design:** `docs/specs/2026-09-14-championship-ui-ux-hardening.md`

## Success criteria

1. Component correction works without allowing an empty recipe → verify with model, verifier, mapper, and widget tests.
2. Validation summaries are localized and contain no internal paths → verify by rendering Korean and English failure states.
3. Failed Continue moves both focus and viewport to the first unresolved field → verify with a long scrollable widget fixture and direct focus and scroll assertions.
4. Browser document language follows Flutter's resolved locale → verify the callback in widget tests and the DOM in a built web app.
5. Existing workflow boundaries remain intact → verify analysis, Bloc lint, full Flutter tests, and championship web release build.

## Constraints

- Modify only championship production code, championship tests, and these two work documents.
- Do not change CI, deployment, API, rate limiting, extraction schema, normal mobile entrypoints, or persistence.
- Do not add a dependency.
- Preserve immutable draft updates and the existing verifier-before-mapper boundary.
- Preserve author-unknown work.
- The original 2026-09-14 execution stopped before staging, committing, pushing, merging, or deploying.
- Run only one heavy Flutter or browser job at a time.

## Task 1: Add the component-removal invariant

**Files:**

- Modify: `test/championship/model/review_recipe_draft_test.dart`
- Modify: `test/championship/import/championship_recipe_mapper_test.dart`
- Modify: `lib/championship/model/review_recipe_draft.dart`

### Red: Component-removal invariant

Add a model test that removes the first component from a two-component draft and asserts that the remaining component keeps its full value, confirmation, evidence, and issue state.
Add a model test that expects `StateError` when code attempts to remove the only component.
Add a mapper test that removes one component, verifies the draft, maps it, and asserts that the resulting recipe contains only the remaining component.

Run:

```shell
flutter test test/championship/model/review_recipe_draft_test.dart test/championship/import/championship_recipe_mapper_test.dart
```

Expected red result: the tests fail because `ReviewRecipeDraft.removeComponent` does not exist.

### Green: Component-removal invariant

Add `ReviewRecipeDraft.removeComponent(int index)`.
Reject an out-of-range index through the existing list behavior and throw `StateError` when the draft contains one component.
Return a new draft with every other field unchanged and the selected component omitted.

Rerun the narrow test command and require all selected tests to pass.

## Task 2: Add the review remove control

**Files:**

- Modify: `test/championship/view/championship_workflow_test.dart`
- Modify: `lib/championship/view/championship_strings.dart`
- Modify: `lib/championship/view/championship_review_panel.dart`
- Modify: `lib/championship/cubit/championship_demo_cubit.dart` only if the widget cannot update the draft through an existing public method

### Red: Review remove control

Render a two-component review draft, activate the localized remove action for the first component, and assert that only the second component remains.
Render a one-component draft and assert that its remove action is visible but disabled.

Run:

```shell
flutter test test/championship/view/championship_workflow_test.dart
```

Expected red result: the remove action cannot be found.

### Green: Review remove control

Add the smallest Cubit or existing-state update seam needed to apply `removeComponent`.
Render one localized outlined remove button per component.
Disable it when only one component remains.
Do not add a dialog, undo stack, insertion flow, or reordering behavior.

Rerun the narrow test and require it to pass.

## Task 3: Structure and localize verification issues

**Files:**

- Modify: `test/championship/import/recipe_draft_verifier_test.dart`
- Modify: `test/championship/view/championship_workflow_test.dart`
- Modify: `lib/championship/import/recipe_draft_verifier.dart`
- Modify: `lib/championship/cubit/championship_demo_state.dart` if its issue type changes
- Modify: `lib/championship/cubit/championship_demo_cubit.dart` if it transports the issue type
- Modify: `lib/championship/view/championship_strings.dart`
- Modify: `lib/championship/view/championship_review_panel.dart`

### Red: Structured verification issues

Change verifier expectations from English strings to ordered structured issues with a kind and optional field path.
Render a failed Korean review and assert that the summary contains localized field labels but does not contain `recipe.`, `components[`, `must`, or `required`.
Render the same failure in English and assert that the corresponding localized label is present.

Run:

```shell
flutter test test/championship/import/recipe_draft_verifier_test.dart test/championship/view/championship_workflow_test.dart
```

Expected red result: the verifier still exposes raw strings and the widget still renders them.

### Green: Structured verification issues

Introduce one small immutable verification-issue value type and one issue-kind enum in `recipe_draft_verifier.dart`.
Replace raw validation messages with ordered structured issues while preserving all existing validation rules.
Add `ChampionshipStrings` methods that map issue kinds and known field paths to localized user-facing text.
Render only localized text in the summary.
Keep source evidence and provider issues in their existing field-local presentation.

Rerun the narrow test command and require all selected tests to pass.

## Task 4: Focus and reveal the first unresolved field

**Files:**

- Modify: `test/championship/view/championship_workflow_test.dart`
- Modify: `lib/championship/view/championship_review_panel.dart`

### Red: Focus and viewport reveal

Build a review fixture tall enough to require scrolling.
Scroll to Continue, activate it with unresolved fields, and assert that the first issue's editable control owns primary focus and that its render box is inside the scrollable viewport after settling.
Temporarily point the expectation at a different field once to prove that the check can fail for the wrong target, then restore the correct assertion before production edits.

Run:

```shell
flutter test test/championship/view/championship_workflow_test.dart --plain-name "failed Continue focuses and reveals the first unresolved field"
```

Expected red result: focus stays on Continue or the first field remains outside the visible viewport.

### Green: Focus and viewport reveal

Convert the review panel to stateful presentation only as needed.
Own and dispose stable focus nodes for editable paths.
Attach scroll anchors to the corresponding field cards.
Listen for a newly produced non-empty verification issue list, wait for the rendered error frame, call `Scrollable.ensureVisible` for the first matching field, and request focus on that field's actual input.
If no editable path matches, reveal the summary without choosing an unrelated focus target.

Rerun the named test, then rerun the complete workflow test file.

## Task 5: Synchronize the resolved locale with the HTML document

**Files:**

- Modify: `test/championship/view/championship_app_test.dart` or add it if no focused app test exists
- Add: `test/championship/view/championship_document_language_web_test.dart`
- Modify: `lib/championship/view/championship_app.dart`
- Modify: `lib/main_championship.dart`

### Red: HTML document language

Add a widget test that records the optional resolved-locale callback, pumps the app in English and Korean, and asserts that it reports the locale selected by Flutter after localization resolves.
Add a browser-platform test that calls the entrypoint DOM adapter for English and Korean and reads `document.documentElement.lang` after each call.
Change the expected locale once to prove that the callback assertion fails for the wrong value, then restore the correct expectation.

Run:

```shell
flutter test test/championship/view/championship_app_test.dart
flutter test --platform chrome test/championship/view/championship_document_language_web_test.dart
```

Expected red result: `ChampionshipApp` has no resolved-locale callback.

### Green: HTML document language

Add an optional `ValueChanged<Locale>` callback to `ChampionshipApp`.
Use a small stateful widget below `MaterialApp` to observe `Localizations.localeOf(context)` and report only resolved-locale changes after the frame.
In `main_championship.dart`, pass a web-only callback that assigns `locale.languageCode` to `web.document.documentElement?.lang`.
Keep `<html lang="en">` unchanged as the pre-bootstrap fallback.

Rerun the focused app test and browser-platform DOM test and require both to pass.

## Task 6: Verify the integrated change

### Static and automated checks

Run package resolution before trusting formatting behavior:

```shell
flutter pub get
```

Format only the modified Dart files, then inspect the diff:

```shell
dart format lib/championship/model/review_recipe_draft.dart lib/championship/import/recipe_draft_verifier.dart lib/championship/cubit/championship_demo_state.dart lib/championship/view/championship_strings.dart lib/championship/view/championship_review_panel.dart lib/championship/view/championship_app.dart lib/main_championship.dart test/championship/model/review_recipe_draft_test.dart test/championship/import/championship_recipe_mapper_test.dart test/championship/import/recipe_draft_verifier_test.dart test/championship/view/championship_workflow_test.dart test/championship/view/championship_app_test.dart test/championship/view/championship_document_language_web_test.dart test/championship/view/championship_strings_test.dart
git diff --check
```

If a listed optional file was not created or changed, remove it from the format command instead of creating an empty artifact.

Run the gates sequentially:

```shell
flutter analyze
dart run bloc_tools:bloc lint .
flutter test
flutter build web --release --target lib/main_championship.dart --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe --tree-shake-icons
```

### Browser acceptance

Serve the current `build/web` through a local HTTP server and use the dedicated browser worker.
At desktop width and `390` logical pixels, verify component removal, localized failed validation, focus and viewport recovery, and the absence of overflow.
Switch between English and Korean and inspect `document.documentElement.lang` after each resolved locale.
Capture rendered evidence for the changed review state.

### Final review

Inspect `git status --short`, staged diff, unstaged diff, and untracked files separately.
Confirm that no normal mobile entrypoint, CI file, API file, dependency manifest, lockfile, or generated deployment artifact changed.
Do not stage, commit, push, merge, or deploy without a separate request.

## 2026-09-15 approved follow-up

The operator approved a full PR loop for all six findings from the rendered championship UI and UX review.
This follow-up authorizes scoped implementation, commits, push, pull-request creation, hosted review, and repairs.
It does not authorize merge, cleanup, issue creation, or memory recording.
Rendered visual approval remains required before merge.

### Task 7: Correct review semantics

**Files:**

- Modify: `test/championship/view/championship_workflow_test.dart`
- Modify: `lib/championship/view/championship_review_panel.dart`
- Modify: `lib/championship/view/championship_strings.dart`

Add a failing semantics test that distinguishes repeated component fields and confirmation actions and rejects interactive roles on status chips.
Add field-specific input and action labels, and exclude the decorative chip implementation from the static status semantics.

Run:

```shell
flutter test test/championship/view/championship_workflow_test.dart --plain-name "review semantics identify fields actions and static statuses"
```

### Task 8: Put consent before submission

**Files:**

- Modify: `test/championship/view/championship_workflow_test.dart`
- Modify: `lib/championship/view/championship_source_panel.dart`

Add a failing keyboard test that enters valid source text, focuses consent, accepts it, and expects the next Tab target to be the newly enabled submit action.
Move the shared consent and privacy block before the mode-specific submit action.

Run:

```shell
flutter test test/championship/view/championship_workflow_test.dart --plain-name "consent enables the next keyboard submit action"
```

### Task 9: Recover the current phase context

**Files:**

- Modify: `test/championship/view/championship_demo_page_test.dart`
- Modify: `lib/championship/view/championship_demo_page.dart`
- Modify: `lib/championship/view/championship_strings.dart`

Add a failing test that scrolls the source phase, enters review, and observes a zero root scroll offset plus focus and live semantics on the localized current-step region.
Own the root scroll controller and phase focus node in page presentation state, and react only when the Cubit's phase changes.

Run:

```shell
flutter test test/championship/view/championship_demo_page_test.dart --plain-name "phase change restores and identifies the current step"
```

### Task 10: Group exact batch ranges

**Files:**

- Modify: `test/championship/view/championship_workflow_test.dart`
- Modify: `test/championship/view/championship_strings_test.dart`
- Modify: `lib/championship/view/championship_result_panel.dart`
- Modify: `lib/championship/view/championship_strings.dart`

Add a failing 180-piece sample test that expects four component batch ranges and no individual repeated batch labels.
Group only consecutive entries whose exact and displayed values both match, following the existing production-result presentation contract.
Keep the domain result and production-sheet input unchanged.

Run:

```shell
flutter test test/championship/view/championship_workflow_test.dart --plain-name "result groups exact repeated batch quantities"
```

### Task 11: Confirm component removal

**Files:**

- Modify: `test/championship/view/championship_workflow_test.dart`
- Modify: `lib/championship/view/championship_review_panel.dart`
- Modify: `lib/championship/view/championship_strings.dart`

Replace the existing immediate-removal widget expectation with failing cancel and confirm tests.
Use one localized confirmation dialog and continue to enforce the final-component invariant in the model.

Run:

```shell
flutter test test/championship/view/championship_workflow_test.dart --plain-name "component removal requires confirmation"
```

### Task 12: Protect Korean words at the expanded threshold

**Files:**

- Modify: `test/championship/view/championship_demo_page_test.dart`
- Modify: `lib/championship/view/championship_demo_page.dart`

Add a failing render test at 840 px and 900 px that checks every glyph in `레시피` remains on the same rendered line.
Reduce the expanded gap and allocate equal width to the introduction and phase columns.

Run:

```shell
flutter test test/championship/view/championship_demo_page_test.dart --plain-name "keeps the Korean recipe word together at expanded widths"
```

### Task 13: Integrated verification and PR loop

Run focused tests after each red-green cycle.
Then format only changed Dart files and run:

```shell
flutter analyze
dart run bloc_tools:bloc lint .
flutter test
npm run test:api
flutter build web --release --target lib/main_championship.dart --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe --tree-shake-icons
```

Serve the new `build/web` and inspect the changed Korean and English states at 390 px, 840 px, and 900 px.
Inspect browser semantics, keyboard order, current-step focus, root scroll position, grouped 15-batch results, and both component-removal dialog paths.
Complete a medium structured local review, create semantic commits, push the branch, open the pull request, and run the hosted review and CI loop.
Stop for rendered visual approval and operator merge.
