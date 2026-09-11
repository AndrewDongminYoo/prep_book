# Responsive Presentation Design

## Status

Approved through the responsive presentation direction in conversation on 2026-09-10.

## Goal

The existing recipe library, recipe editor, production setup, and production result screens must adapt to the width that Flutter gives each screen.
The change must preserve the current compact workflow and must make useful use of medium and expanded widths.

## Source requirements

The product design requires layouts for phone, tablet, landscape, and split-window widths.
It also requires the app to preserve navigation state, entered target yield, overrides, and scroll position when the width class changes.
See `docs/notes/2026-09-06-prepbook-pro-design.md` under Responsive interaction design.

Flutter recommends that an adaptive layout use the available window or parent constraints instead of a hardware type.
Flutter also documents `600` logical pixels as the common boundary between compact navigation and a large-screen layout.
See <https://docs.flutter.dev/ui/adaptive-responsive/general>.

## Width classes

The presentation layer defines these width classes:

- `compact`: width below `600` logical pixels.
- `medium`: width from `600` logical pixels up to, but not including, `840` logical pixels.
- `expanded`: width of at least `840` logical pixels.

A small `WindowWidthClass` API owns these values.
Screens use `LayoutBuilder` and pass its `maxWidth` to that API.
No screen checks the device model, orientation name, or physical display size.
When text scaling exceeds `200` percent, a screen keeps its width class but uses one pane until each proposed pane has the same effective text room as a `300` logical pixel pane at `200` percent.

## Screen behavior

### Recipe library

The compact layout keeps the current list and route-based actions.
The medium and expanded layouts show the recipe list and a selected recipe summary as a master-detail pair.
The first visible recipe becomes the default selection when the current selection is not visible.
Selecting another row updates the detail pane without opening a route.
The detail pane offers the existing Edit and Production Run actions.

The recipe library owns selection and scroll position as view state.
The existing `RecipeLibraryCubit` continues to own reads, the search query, and the archived filter.

### Recipe editor

The editor keeps one form and one `RecipeEditorCubit` for every width class.
Compact screens use the current full-width form.
Medium and expanded screens center the form and limit its readable width.
The form does not create a second editor state or a duplicate save path.

### Production setup

The compact layout keeps the current vertical order.
The medium and expanded layouts put the target form and Continue action in the first pane.
They put the live calculated outcome in the second pane.
One `ProductionSetupCubit` remains above the width branch, so the target amount, target unit, calculation status, and preview survive a resize.

### Production result

The compact layout keeps the current single-column review and warning reveal action.
The medium and expanded layouts put the run summary, recipe-level warnings, and save action in the first pane.
They put the component tree in the second pane.
Component warnings appear beside the component that they name in the second pane.
The wide layout does not show the compact warning reveal action for those warnings.

One `ProductionResultCubit` remains above the width branch.
Expansion state, warning acknowledgements, override drafts, and the stored run state therefore survive a resize.

## State and scrolling

Width changes must not construct a new page-level Cubit.
Each stateful view owns the scroll controller that must survive its layout branch.
The recipe library also owns its selected recipe identifier.
If a filter hides the selected recipe, the detail pane uses the first visible recipe without deleting the saved selection.

## Accessibility

The responsive branch must not remove labels from existing controls.
The detail pane must use buttons for Edit and Production Run.
The layout must not require a gesture without a labeled control.
Existing Material controls retain their minimum interactive dimensions.

## Non-goals

This change does not add a production history screen.
This change does not add PDF generation, sharing, printing, backup, restore, migration, category filtering, recipe duplication, or recipe archiving controls.
This change does not add a navigation rail because the app currently has only one top-level destination.
This change does not modify domain, application, or persistence contracts.

## Acceptance criteria

- Widths of `599`, `600`, `839`, and `840` logical pixels select the specified width classes.
- The recipe library renders one pane at compact width and two panes at medium or expanded width unless the large-text fallback requires one pane.
- A selected recipe remains selected after a compact-to-expanded-to-compact transition when it remains visible.
- A typed production target and its calculated preview remain present after a width transition.
- Production result overrides, expansion state, and warning acknowledgements remain present after a width transition.
- Component warnings render beside their component in medium and expanded layouts.
- Existing compact widget tests continue to pass.
- `flutter analyze`, Bloc lint, and the full coverage suite pass.
