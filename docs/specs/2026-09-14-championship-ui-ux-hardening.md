# Championship Review UI and Accessibility Hardening Specification

## Status

Approved for implementation in conversation on 2026-09-14.

This specification narrows the next championship-variant change to four review corrections.
It extends `docs/specs/2026-09-13-ai-recipe-import-demo.md` without changing the normal mobile product or the extraction contract.

## Goal

Make the guarded review flow complete enough for a release candidate by letting the operator remove an incorrect extracted component, presenting validation failures in the active language, moving keyboard and viewport attention to the first unresolved field, and keeping the HTML document language aligned with Flutter's resolved locale.

## Scope

The change includes only these outcomes:

1. The operator can remove an extracted component during review while at least one component remains.
2. Review validation summaries use localized user-facing field names and messages instead of internal English paths.
3. A failed Continue action focuses and reveals the first unresolved editable field.
4. The championship page updates the HTML `lang` attribute when Flutter resolves or changes the locale.

## Non-goals

- Do not redesign the championship page, theme, navigation, phase structure, or extraction flow.
- Do not change the AI request, response schema, endpoint, provider behavior, rate limiting, deployment, or CI workflows.
- Do not add recipe persistence, undo history, component reordering, or component insertion.
- Do not change the normal development, staging, or production mobile entrypoints.
- Do not introduce a dependency.

## Functional requirements

### Component removal

- Each component review section has a localized remove action.
- The action removes that component from the in-memory review draft immediately.
- The action is disabled when the draft contains one component.
- `ReviewRecipeDraft` rejects a direct attempt to remove its final component so the invariant does not depend on the widget.
- Removing a component preserves every remaining component value, confirmation, evidence, and issue in the original order.
- The mapper continues to include every remaining verified component and no removed component.

### Localized verification summary

- Verification failures use structured issue data that separates the issue kind from its field path.
- The review panel converts each structured issue to active-locale copy through `ChampionshipStrings`.
- User-facing copy names fields such as recipe name, base yield, maximum batch yield, component name, quantity, unit, and behavior.
- Component field labels include a one-based component number.
- The visible Korean summary does not expose identifiers such as `recipe.maxBatchYield`, `components[0].quantity`, or English validation phrases.
- Evidence and model-supplied source issues remain field-local and are not used as internal validation identifiers.

### Failed Continue recovery

- Continue invokes the existing verifier and keeps the current draft when verification fails.
- The first structured verification issue determines the recovery target.
- If the issue identifies an editable field, the review panel scrolls that field into the visible portion of the nearest scrollable and requests focus after the error state renders.
- If no editable field matches the first issue, the panel reveals the validation summary and does not move focus to an unrelated control.
- The behavior works with keyboard activation and pointer activation.
- Responsive rebuilds do not replace the review draft.

### HTML document language

- `ChampionshipApp` reports the locale that Flutter actually resolves through its localization system.
- The web entrypoint sets `document.documentElement.lang` to the resolved locale language code.
- The attribute updates when the resolved locale changes during the app lifetime.
- The default static `lang="en"` value remains a safe pre-bootstrap fallback.
- No normal mobile entrypoint imports `package:web`.

## Data and state design

`ReviewRecipeDraft.removeComponent(index)` owns the non-empty component invariant and returns a new immutable draft.

`RecipeDraftVerifier` returns ordered structured issues.
Each issue contains an issue kind and an optional review-field path.
The verifier remains the only authority that decides whether the draft can proceed.

The review widget owns focus nodes and scroll anchors because focus and viewport recovery are presentation responsibilities.
The Cubit continues to own phase and draft state.

`ChampionshipApp` exposes an optional resolved-locale callback.
The championship web composition root adapts that callback to the browser DOM.

## Accessibility and interaction requirements

- Remove actions have localized accessible labels supplied by visible button text.
- A disabled final-component remove action remains visible so the minimum-component rule is discoverable.
- Validation copy must remain meaningful without color or internal path knowledge.
- Focus must land on the actual editable control, not only its surrounding card.
- Scrolling must preserve enough context to show the field label and its issue state.
- Locale reporting must follow Flutter's resolved locale rather than the requested locale alone.

## Acceptance criteria

- [ ] Removing the first component from a multi-component draft leaves the later components unchanged and in order.
- [ ] Removing the only component is rejected by the model and unavailable in the UI.
- [ ] The mapper excludes a component removed before verification.
- [ ] Korean verification summaries contain localized field names and no internal paths or English validation phrases.
- [ ] English verification summaries remain readable and identify the same fields.
- [ ] A failed Continue action in a scrollable review focuses and reveals the first unresolved editable field.
- [ ] A widget test observes the locale callback after Flutter resolves English and Korean locales.
- [ ] A browser check observes the HTML `lang` attribute change to the active locale.
- [ ] Existing championship sample, target, result, and export behavior remains unchanged.
- [ ] Flutter analysis, Bloc lint, Flutter tests, and the championship web release build pass.

## Evidence discipline

The relevant Oracle search found no project-specific precedent for component removal, review focus recovery, or document-language synchronization: `[no precedent found]`.

The applicable general precedent is `.claude/rules/evidence-basis-discipline.md`.
It requires each check to create the state under review and observe the property that matters.
This specification therefore requires the localization test to inspect rendered copy, the recovery test to observe both focus and viewport state after a real failed Continue action, and the locale test to inspect the resolved locale callback and browser DOM instead of only widget configuration.
