# Responsive Presentation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the four existing presentation screens adapt to compact, medium, and expanded window widths without losing in-progress state.

**Architecture:** A small width-class API owns the shared breakpoints.
Each screen uses `LayoutBuilder` and keeps its existing Cubit above the responsive branch.
The library and result views keep only layout-specific selection or scroll state in their existing state objects.

**Tech Stack:** Flutter 3.47.x, Material 3, `flutter_bloc`, Flutter widget tests.

**Spec:** `docs/specs/2026-09-10-responsive-presentation.md`

## Global Constraints

- Use available layout constraints instead of device type or orientation.
- Preserve the current compact workflow.
- Preserve public domain, application, and persistence contracts.
- Do not add a dependency.
- Do not add history, export, backup, restore, migration, or missing recipe-library actions.
- Keep every page-level Cubit above the responsive layout branch.

---

### Task 1: Shared width classes

**Files:**

- Create: `lib/presentation/responsive/window_width_class.dart`
- Create: `test/presentation/responsive/window_width_class_test.dart`
- Modify: `lib/presentation/presentation.dart`

**Interfaces:**

- Consumes: A finite `double` width from `LayoutBuilder.constraints.maxWidth`.
- Produces: `WindowWidthClass windowWidthClassOf(double width)` and `bool get usesMultiplePanes`.

- [x] **Step 1: Write the failing boundary test**

```dart
test('classifies every width at both boundaries', () {
  expect(windowWidthClassOf(599), WindowWidthClass.compact);
  expect(windowWidthClassOf(600), WindowWidthClass.medium);
  expect(windowWidthClassOf(839), WindowWidthClass.medium);
  expect(windowWidthClassOf(840), WindowWidthClass.expanded);
});
```

- [x] **Step 2: Run the test and verify RED**

Run `flutter test test/presentation/responsive/window_width_class_test.dart`.
Expect a compile failure because `WindowWidthClass` does not exist.

- [x] **Step 3: Add the minimal width API**

```dart
enum WindowWidthClass { compact, medium, expanded }

WindowWidthClass windowWidthClassOf(double width) {
  if (width < 600) return WindowWidthClass.compact;
  if (width < 840) return WindowWidthClass.medium;
  return WindowWidthClass.expanded;
}

extension WindowWidthClassLayout on WindowWidthClass {
  bool get usesMultiplePanes => this != WindowWidthClass.compact;
}
```

- [x] **Step 4: Run the test and verify GREEN**

Run `flutter test test/presentation/responsive/window_width_class_test.dart`.
Expect all tests in the file to pass.

- [ ] **Step 5: Stage a semantic commit candidate**

Stage only the three paths from this task if the operator later requests a commit.
Use `feat(presentation): classify responsive window widths` as the commit message.

### Task 2: Recipe library master-detail layout

**Files:**

- Modify: `lib/presentation/recipe_library/view/recipe_library_page.dart`
- Modify: `test/presentation/recipe_library/recipe_library_page_test.dart`

**Interfaces:**

- Consumes: `WindowWidthClass`, `RecipeLibraryState.visibleRecipes`, `RecipeEditorLauncher`, and `ProductionSetupLauncher`.
- Produces: One compact pane or a medium and expanded master-detail pair.

- [x] **Step 1: Write failing responsive behavior tests**

Add tests that set the view to `599` and `600` logical pixels.
Assert that `ValueKey('recipe-detail-pane')` is absent at `599` and present at `600`.
At `840`, select the second visible recipe and assert that its name appears in the detail pane.
Resize to `599` and back to `840`.
Assert that the same recipe remains selected.

- [x] **Step 2: Run the focused tests and verify RED**

Run `flutter test test/presentation/recipe_library/recipe_library_page_test.dart --plain-name 'responsive layout'`.
Expect failure because the detail pane does not exist.

- [x] **Step 3: Add view-owned responsive state**

Convert `RecipeLibraryView` to a `StatefulWidget`.
Store a nullable selected recipe identifier and one list `ScrollController` in its state.
Dispose the controller with the view.

- [x] **Step 4: Render the two-pane library**

Use `LayoutBuilder` inside the existing `Scaffold` body.
Keep the current `CustomScrollView` for compact width.
At wider widths, place that scroll view beside a `VerticalDivider` and a recipe detail pane.
The detail pane uses the selected visible recipe or the first visible recipe.
It exposes the existing Edit and Production Run actions.

- [x] **Step 5: Run the focused tests and verify GREEN**

Run `flutter test test/presentation/recipe_library/recipe_library_page_test.dart`.
Expect all library page tests to pass.

- [ ] **Step 6: Stage a semantic commit candidate**

Stage only the two paths from this task if the operator later requests a commit.
Use `feat(presentation): add recipe master detail layout` as the commit message.

### Task 3: Production setup split layout

**Files:**

- Modify: `lib/presentation/production_setup/view/production_setup_page.dart`
- Modify: `test/presentation/production_setup/production_setup_page_test.dart`

**Interfaces:**

- Consumes: `WindowWidthClass` and the existing `ProductionSetupState`.
- Produces: The existing compact column or a two-pane target and live-outcome layout.

- [x] **Step 1: Write a failing width-transition test**

Open the page at `599` logical pixels.
Enter a valid target and wait for the preview.
Resize to `600` logical pixels.
Assert that `ValueKey('production-setup-outcome-pane')` exists, the target field keeps the typed value, and the calculated batch count remains visible.

- [x] **Step 2: Run the focused test and verify RED**

Run `flutter test test/presentation/production_setup/production_setup_page_test.dart --plain-name 'responsive layout'`.
Expect failure because the outcome pane does not exist.

- [x] **Step 3: Separate the form and outcome widgets**

Keep `ProductionSetupCubit` in `ProductionSetupPage`.
Render the recipe name, target row, and Continue action as one pane.
Render `_Outcome` as the other pane.
Use the current vertical order when `usesMultiplePanes` is false.

- [x] **Step 4: Run the focused tests and verify GREEN**

Run `flutter test test/presentation/production_setup/production_setup_page_test.dart`.
Expect all setup page tests to pass.

- [ ] **Step 5: Stage a semantic commit candidate**

Stage only the two paths from this task if the operator later requests a commit.
Use `feat(presentation): split production setup on wide windows` as the commit message.

### Task 4: Production result split layout and inline warnings

**Files:**

- Modify: `lib/presentation/production_result/cubit/production_result_state.dart`
- Modify: `lib/presentation/production_result/view/production_result_page.dart`
- Modify: `test/presentation/production_result/production_result_cubit_test.dart`
- Modify: `test/presentation/production_result/production_result_page_test.dart`

**Interfaces:**

- Consumes: `WindowWidthClass`, `ProductionResultState.visibleRows`, and component warning keys.
- Produces: `List<ProductionWarning> warningsFor(ResultRow row)` and a wide two-pane result layout.

- [x] **Step 1: Write a failing warning-selection unit test**

Build a state that has warnings for two different component keys.
Call `warningsFor` with one real row.
Assert that the returned list contains only the warning whose `(recipeId, componentId)` pair matches the row.

- [x] **Step 2: Run the unit test and verify RED**

Run `flutter test test/presentation/production_result/production_result_cubit_test.dart --plain-name 'warningsFor'`.
Expect a compile failure because `warningsFor` does not exist.

- [x] **Step 3: Add the warning selector and verify GREEN**

Implement `warningsFor` by comparing `_componentOfWarning(warning)` with `row.key` in state code.
Run the focused unit test again.
Expect it to pass.

- [x] **Step 4: Write failing responsive widget tests**

At `599` logical pixels, assert that the compact reveal action exists for a component warning.
At `600` logical pixels, assert that `ValueKey('production-result-components-pane')` exists and the reveal action is absent.
Assert that the warning message and acknowledgement action render inside the component row.
Type an override, expand a row, resize across the boundary, and assert that both states remain.

- [x] **Step 5: Run the widget tests and verify RED**

Run `flutter test test/presentation/production_result/production_result_page_test.dart --plain-name 'responsive layout'`.
Expect failure because the wide panes do not exist.

- [x] **Step 6: Add the wide result layout**

Keep the current `StatefulWidget` and its row keys.
Use one summary list and one component list at medium and expanded widths.
Keep recipe-level warnings in the summary pane.
Render component warnings inside `_ComponentRow` by using `warningsFor`.
Keep the current compact list and reveal behavior unchanged.

- [x] **Step 7: Run the result suites and verify GREEN**

Run `flutter test test/presentation/production_result/production_result_cubit_test.dart test/presentation/production_result/production_result_page_test.dart`.
Expect all result tests to pass.

- [ ] **Step 8: Stage a semantic commit candidate**

Stage only the four paths from this task if the operator later requests a commit.
Use `feat(presentation): adapt production results to wide windows` as the commit message.

### Task 5: Recipe editor readable width and final gate

**Files:**

- Modify: `lib/presentation/recipe_editor/view/recipe_editor_page.dart`
- Modify: `test/presentation/recipe_editor/recipe_editor_page_test.dart`
- Modify: `docs/specs/2026-09-10-responsive-presentation.md`
- Modify: `docs/plans/2026-09-10-responsive-presentation.md`

**Interfaces:**

- Consumes: The existing editor form and `WindowWidthClass`.
- Produces: A centered editor with a bounded readable width on medium and expanded windows.

- [x] **Step 1: Write a failing editor width-transition test**

Enter text at compact width.
Resize to expanded width.
Assert that `ValueKey('recipe-editor-width-boundary')` exists and that the entered text remains.

- [x] **Step 2: Run the focused test and verify RED**

Run `flutter test test/presentation/recipe_editor/recipe_editor_page_test.dart --plain-name 'responsive layout'`.
Expect failure because the width boundary does not exist.

- [x] **Step 3: Add the editor width boundary**

Wrap the existing `_EditorBody` in `LayoutBuilder`.
At medium and expanded widths, center it in a `ConstrainedBox` with a finite maximum width.
Do not move or recreate `RecipeEditorCubit`.

- [x] **Step 4: Run the editor tests and verify GREEN**

Run `flutter test test/presentation/recipe_editor/recipe_editor_page_test.dart`.
Expect all editor page tests to pass.

- [x] **Step 5: Run formatting and static gates**

Run `dart format --set-exit-if-changed` with every changed Dart path listed explicitly.
Run `flutter analyze`.
Run `dart run bloc_tools:bloc lint .`.
Expect each command to exit with status `0`.

- [x] **Step 6: Run the complete test gate**

Run `very_good test --coverage --test-randomize-ordering-seed random`.
Expect the suite to pass and the coverage gate to remain at `100` percent for reached files.

- [x] **Step 7: Review the final diff**

Run `git diff --check`.
Run `git status --short`.
Run `git diff --stat` and inspect `git diff` for only the approved responsive scope.

- [ ] **Step 8: Stage a semantic commit candidate**

Stage only the responsive implementation, tests, spec, and plan if the operator later requests a commit.
Use `feat(presentation): complete responsive core layouts` as the commit message.
