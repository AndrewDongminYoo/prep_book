# Championship Workflow Design Specification

## Status

The operator approved the visual redesign and detail pass in conversation on 2026-09-17.
This specification records the approved scope for the pull request.

## Problem

The Championship web flow appeared like an unstyled Flutter demo.
The source, review, and result states lacked a consistent visual hierarchy.
Step connectors and control outlines needed clearer detail.

## Scope

- Present the existing source, review, target, and result phases in one centered workflow.
- Keep the offline sample visible in the first source viewport at desktop and compact widths.
- Show connected steps with distinct completed, current, and future states.
- Use consistent card, input, segmented control, and button outlines.
- Keep review evidence and correction controls near each field.
- Make the result summary and production sheet readable at desktop and compact widths.
- Preserve the existing phase behavior, review confirmation rules, and exact calculation engine.

## Non-goals

- Do not change recipe extraction, calculation, API routes, deployment configuration, or normal mobile screens.
- Do not add a dependency or a new state management layer.
- Do not include unrelated mobile accessibility, backup, or endpoint configuration changes in this pull request.

## Acceptance criteria

1. Source, review, and result render without horizontal overflow at 1440 px and 390 px widths.
2. The source sample action is visible in the first viewport and enters review without network access.
3. Three connectors remain visible between the four steps at default text scale.
4. Large text uses a layout that does not clip the step labels or review controls.
5. Outlined controls have visible borders with consistent corners and accessible tap targets.
6. The sample retains the exact `180 piece` to `15 batches` calculation.
7. Championship widget tests, Flutter analysis, and the web release build pass.

## Visual evidence

The reviewed local captures are under `.qa-artifacts/detail-pass-*.png`.
They are local review artifacts and are not part of the production bundle.
