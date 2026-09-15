# AI Recipe Import Championship Variant Design

## Status

Approved as an isolated competition variant in conversation on 2026-09-13.

The implementation baseline is `main@8a8e6c8e394960346eadaa16f8defda1973b496a`.
The 2026-09-15 post-deployment acceptance found that the self-hosted pdf.js base path was not a valid dynamic-import specifier, so the production-sheet preview failed before it requested either bundled module.
The current branch uses an explicit `./assets/` specifier.
Its local release build loaded both modules from the application origin and rendered the preview.
Production verification remains incomplete until the correction is merged and deployed.
The production Share action produced a non-zero readable PDF.
Safari, an isolated browser-storage comparison, successful Retry recovery, and direct print-dialog observation also remain incomplete.
See `docs/notes/2026-09-20-ai-championship-submission.md`.

This document authorizes one narrow exception to the first-release scope in
`docs/notes/2026-09-06-prepbook-pro-design.md`.
It does not replace that product design and does not pivot the shipping mobile
application toward a required backend, AI workflow, or web product.

## Goal

Publish a no-login web demo that turns one recipe text or one recipe image into
a reviewable recipe draft, requires the operator to resolve every ambiguous
quantity or unit, then passes only confirmed structured data into PrepBook's
existing exact scaling engine and production-sheet export.

The public demo must make this boundary visible:

> AI interprets the source. PrepBook calculates the production plan.

## Problem

Small kitchens commonly keep recipes in messages, photographs, printouts, and
loosely formatted documents.
Re-entering those recipes is slow, but allowing a language model to silently
infer missing units or calculate scaled quantities would make the result unsafe
for production work.

The useful product capability is therefore not unrestricted recipe generation.
It is a guarded import adapter that converts unstructured source material into
a traceable draft, exposes uncertainty, and hands verified values to the
existing deterministic domain.

## Product relationship

The normal `development`, `staging`, and `production` entrypoints remain the
offline-first iOS and Android product described by the approved source design.
They must not import the competition variant.

The competition variant:

- lives under `lib/championship/`;
- starts from `lib/main_championship.dart`;
- supports Flutter Web only;
- keeps all recipe and image state in browser memory;
- does not open SQLite or call the existing persistence repositories;
- does not modify the normal recipe library;
- reuses the existing domain calculator and production-sheet feature;
- may call one serverless extraction endpoint only after an explicit user
  action;
- remains removable without changing the normal application entrypoints.

The reusable seam is the structured draft-to-domain mapping.
Competition landing copy, sample content, API transport, and submission-specific
presentation remain variant-only until separate user validation justifies a
product decision.

## User journey

1. The visitor opens the public URL without an account.
2. The first screen offers:
   - `Try the sample`;
   - paste recipe text;
   - select one recipe image.
3. Sample mode loads a checked-in deterministic extraction fixture and makes no
   network request.
4. Text or image mode sends the source to the extraction endpoint after the
   visitor confirms the privacy notice.
5. The review screen shows every proposed recipe field beside its source
   evidence, confidence, and issues.
6. Missing or ambiguous values remain unresolved; the model must not invent
   them.
7. The visitor edits and confirms the recipe name, base yield, optional maximum
   batch yield, and every component.
8. The visitor enters a target production yield.
9. PrepBook maps the confirmed draft into domain objects and calls the existing
   exact calculator with the same `1000`-batch interactive bound as the shipping
   production setup screen.
10. The result shows batch decomposition, totals, per-batch quantities, manual
    lines, and warnings.
11. The visitor can open the existing production-sheet preview and download or
    print its PDF through the supported web platform behavior.

A first-time visitor must be able to complete the checked-in sample path in
under 90 seconds.

## Supported source inputs

### Sample

The sample is a rights-cleared synthetic croissant recipe.
It uses the same JSON draft contract as the live endpoint and contains at least
two review moments:

- one high-confidence quantity that can be confirmed without editing;
- one missing or ambiguous unit that blocks calculation until corrected.

The sample is always available, including when the extraction endpoint is down,
rate-limited, or unconfigured.

### Text

- UTF-8 recipe text.
- Maximum `20,000` Unicode scalar values.
- Empty or whitespace-only text is rejected in the browser and endpoint.

### Image

- Exactly one `image/jpeg`, `image/png`, or `image/webp` file, up to `32 MiB` as selected.
- Maximum uploaded size `3 MiB`, which keeps its base64 JSON request below the [Vercel Function `4.5 MB` payload limit](https://vercel.com/docs/functions/limitations#request-body-size); the endpoint enforces the same limit on the decoded bytes.
- The browser reduces a larger or wider image before upload (added 2026-09-14): an image at most `3 MiB` whose longest edge is at most `2,048` px is sent unchanged; otherwise it is scaled to a `2,048` px longest edge and encoded as JPEG at quality `0.85`, retried at `1,600` px / `0.80` and `1,280` px / `0.75` if still too large, and rejected after that. Transparency is flattened onto white and EXIF orientation is applied. The provider's high-detail mode spends at most `2,500` patches of `32` px, so nothing a `2,048` px edge discards would have reached the model.
- The browser reads the file into memory, reduces it if needed, shows the size it will send, and sends one data URL.
- The browser does not retain the file after reset or page close.

### Excluded inputs

The competition slice does not accept PDF, spreadsheet, document, HEIC, multiple
images, URLs, camera capture, or batch imports.
Those formats would add parsing, file retention, and review states that are not
needed to prove this workflow.

## AI responsibility

The model performs extraction only.
It may:

- identify a recipe name;
- identify a base yield and optional maximum batch yield;
- identify ingredient names, quantities, units, notes, and likely scaling
  behavior;
- copy concise source evidence for every proposed value;
- mark confidence as `high`, `medium`, or `low`;
- report why a value is ambiguous or missing.

It must not:

- calculate the requested production target;
- scale ingredient quantities;
- convert mass to volume;
- infer density;
- fabricate a missing number or unit;
- create sub-recipes;
- search the web;
- rewrite the recipe into a new recipe;
- mark any value as operator-confirmed.

The endpoint uses the Responses API with strict JSON Schema output.
The default model is `gpt-5.6-luna`, selected for a bounded extraction workload,
and can be changed only through the `OPENAI_MODEL` server environment variable.
The request uses `store: false`, no tools, and low reasoning effort.

## Extraction contract

The endpoint and Flutter client exchange JSON matching this shape:

```json
{
  "schemaVersion": 1,
  "sourceKind": "text",
  "recipe": {
    "name": {
      "value": "Croissant dough",
      "evidence": "Croissant dough",
      "confidence": "high",
      "issues": []
    },
    "baseYield": {
      "amount": {
        "value": "24",
        "evidence": "Makes 24",
        "confidence": "high",
        "issues": []
      },
      "unit": {
        "value": "piece",
        "evidence": "Makes 24",
        "confidence": "medium",
        "issues": []
      }
    },
    "maxBatchYield": null,
    "preparationNotes": [
      {
        "value": "Rest 20 minutes between folds.",
        "evidence": "Rest 20 minutes between folds.",
        "confidence": "high",
        "issues": []
      }
    ]
  },
  "components": [
    {
      "name": {
        "value": "Water",
        "evidence": "Water 480",
        "confidence": "high",
        "issues": []
      },
      "amount": {
        "value": "480",
        "evidence": "Water 480",
        "confidence": "high",
        "issues": []
      },
      "unit": {
        "value": null,
        "evidence": "Water 480",
        "confidence": "low",
        "issues": ["The source does not state a unit."]
      },
      "behavior": {
        "value": "proportional",
        "evidence": "Water 480",
        "confidence": "medium",
        "issues": []
      },
      "note": null
    }
  ]
}
```

Contract rules:

- `schemaVersion` is exactly `1`.
- `sourceKind` is `text` or `image` for live responses and `sample` for the
  checked-in fixture.
- Numeric quantities are decimal strings, never JSON numbers or binary
  floating-point values.
- An absent value is JSON `null`, not an empty string or guessed value.
- `issues` is always present and may be empty.
- `evidence` is copied from or narrowly describes the submitted source; it is
  never a general explanation.
- Component behavior is one of `proportional`, `perBatch`, `fixedOnce`,
  `manual`, or `null`.
- A `manual` proposal carries a null amount and unit.
- The API response contains no raw provider response, prompt, API key, or image
  data.

## Review model

Decoded extraction values are immutable evidence records.
The Flutter variant creates a separate immutable review draft that adds:

- the operator-edited value;
- whether the field was explicitly confirmed;
- validation issues produced locally;
- whether the value differs from the AI proposal.

Confidence is display metadata only.
A high-confidence value is not permission to calculate without review.
The review screen provides `Confirm all unambiguous fields`, but that action may
confirm only fields whose value is present, locally valid, and has no extraction
issue.
It never confirms null, unsupported, or inconsistent values.
A value the model flagged can still be confirmed one field at a time: that
confirmation records the reviewer's judgment against the source, and the
model's issue then no longer blocks calculation.
A null or locally invalid value cannot be confirmed either way.

Calculation remains disabled until all of these conditions hold:

- recipe name is non-empty and confirmed;
- base-yield amount is a positive decimal string and confirmed;
- base-yield unit resolves and is confirmed;
- optional maximum batch yield is either absent or a positive, confirmed,
  compatible quantity;
- at least one component exists;
- every component name and behavior is confirmed;
- every non-manual component has a positive confirmed amount and resolved,
  confirmed unit;
- every manual component has no numeric amount and is explicitly confirmed as
  manual;
- all local consistency issues are resolved.

## Supported unit resolution

The competition adapter resolves only a small explicit alias table.
It does not guess from an ingredient name.

| Input aliases                                 | Domain unit               |
| --------------------------------------------- | ------------------------- |
| `mg`, `milligram`, `밀리그램`                 | `Unit.milligram`          |
| `g`, `gram`, `grams`, `그램`                  | `Unit.gram`               |
| `kg`, `kilogram`, `kilograms`, `킬로그램`     | `Unit.kilogram`           |
| `ml`, `milliliter`, `milliliters`, `밀리리터` | `Unit.milliliter`         |
| `l`, `liter`, `liters`, `L`, `리터`           | `Unit.liter`              |
| `tsp`, `teaspoon`, `티스푼`                   | `Unit.teaspoon`           |
| `tbsp`, `tablespoon`, `테이블스푼`, `큰술`    | `Unit.tablespoon`         |
| `portion`, `portions`, `인분`                 | `Unit.portion`            |
| `piece`, `pieces`                             | `Unit.count('piece')`     |
| `ea`, `each`, `item`, `items`                 | `Unit.count('ea')`        |
| `개`                                          | `Unit.count('개')`        |
| `tray`, `trays`, `판`                         | `Unit.namedYield('tray')` |

Unknown text remains unresolved.
Count and yield-only units convert only to the identical symbol, exactly as the
existing domain requires.
A count unit therefore keeps the word the source used: `복숭아 4개` counts whole
peaches and `4 pieces` may count cuts of one, so the adapter never folds one
count word into another, and the review and target pickers offer each count
symbol separately.

## Deterministic mapping and calculation

After verification, `ChampionshipRecipeMapper` creates:

- one `Recipe` at revision `1`;
- one `Ingredient` for each distinct normalized component name;
- one `RecipeComponent` per reviewed component, preserving display order;
- stable demo identifiers derived from list order, not from model-generated
  identifiers;
- exact `Quantity` values parsed from decimal strings;
- no sub-recipe references.

The mapper injects the clock so tests and exported documents are deterministic.
It does not write a repository.

`ProductionCalculator(maxPlannedBatches: 1000)` performs all production math.
The variant then creates an in-memory `ProductionRun` containing the recipe,
ingredient snapshot, target yield, and result.
The run exists only to reuse the existing result and production-sheet contracts;
it is never persisted.

## Presentation

The variant is one responsive page with four visible phases:

1. Source
2. Review
3. Target
4. Result

One `ChampionshipDemoCubit` owns the phase and in-progress data above the
responsive layout branch.
Width changes must not restart extraction, clear edits, or recalculate a
completed result.
The existing `WindowWidthClass` thresholds remain authoritative:

- compact below `600` logical pixels;
- medium from `600` through `839`;
- expanded from `840`.

Compact mode uses one column.
Medium and expanded modes may place source evidence beside editable fields, and
result summary beside batch details, when the existing large-text fallback
permits two panes.
The page must remain usable at a text scale of `3.0`.

The result must visibly distinguish:

- AI proposal;
- operator-confirmed value;
- exact PrepBook calculation;
- any remaining domain warning.

## Endpoint and privacy boundary

`api/extract-recipe.mjs` is one Vercel Node.js Function.
It exposes `POST /api/extract-recipe` and rejects every other method.

Before calling the model it validates:

- `Content-Type: application/json`;
- request JSON shape;
- source kind;
- text length;
- image MIME type;
- decoded image size;
- configured API key;
- configured origin policy.

The endpoint:

- never writes source data to a database or filesystem;
- never logs request bodies, recipe text, image bytes, or model output;
- may log request id, status, latency, and error category;
- sends `store: false` to the provider;
- returns a stable error code and safe message;
- uses an abort timeout of `25` seconds;
- returns `Cache-Control: no-store`.

The configured origin is a browser-origin defense, not authentication. Before public deployment, a Vercel WAF rule rate-limits `POST /api/extract-recipe` so forged clients cannot turn the server-held provider key into unbounded access.

The browser copy must state the precise boundary:

- PrepBook does not persist the submitted source;
- the source is sent to the configured AI provider for extraction;
- provider retention and abuse-monitoring controls follow the provider account
  policy;
- visitors should use the sample instead of confidential or personal material.

The UI must not claim that the provider stores nothing.

## Failure behavior

- Unsupported source: reject before a network call.
- Endpoint unavailable or unconfigured: preserve the visitor's source and offer
  Retry and Sample actions.
- Timeout: cancel the request, preserve the source, and show a retryable error.
- Rate limit: show a retryable busy state without exposing provider details.
- Invalid provider output: reject the entire response; do not partially trust
  fields from malformed JSON.
- Stale response: ignore any extraction that finishes after the visitor resets
  or submits a newer source.
- Local validation failure: keep the review draft and focus the first unresolved
  field.
- Domain error: keep the verified draft and target so the visitor can correct
  them.
- PDF failure: keep the calculated run visible and allow the production sheet to
  be reopened.

## Deployment

The repository restores the Flutter `web/` target only for the competition
entrypoint.
The normal mobile flavors remain unchanged.

Vercel hosts:

- the static Flutter Web build;
- the single extraction function;
- no database or object storage.

The production deployment is built with the pinned Flutter toolchain and
handed to Vercel prebuilt, because Vercel's builders have no Flutter and its
Git integration cannot build this project; `vercel.json` turns that
integration off.
`.github/workflows/deploy-championship.yaml` runs the three commands below on
every push to `main` (production) and on manual dispatch from any branch
(preview), reading the Flutter pin from `main.yaml` and authenticating with the
`VERCEL_TOKEN`, `VERCEL_ORG_ID`, and `VERCEL_PROJECT_ID` repository secrets.
The same commands run by hand when a deployment must not wait for a merge:

```sh
vercel pull --yes --environment=production
vercel build --prod
vercel deploy --prebuilt --prod
```

The public URL must remain reachable without authentication from submission
through the end of judging on 2026-10-17.
The deployment has `OPENAI_API_KEY` and `OPENAI_MODEL` server-side environment
variables; neither value is compiled into Flutter assets.

## Non-goals

This variant does not add:

- a new default PrepBook product direction;
- accounts, login, payments, subscriptions, or analytics;
- cloud recipe storage, synchronization, or a hosted recipe library;
- general chat or recipe generation;
- AI scaling, AI unit conversion, or AI quantity correction;
- sub-recipe extraction;
- PDF, spreadsheet, document, URL, or multi-image import;
- OCR-provider routing or model-provider selection UI;
- recipe editing in the normal mobile library;
- production history for demo runs;
- inventory, costing, purchasing, nutrition, allergens, or staff workflows;
- App Store or Play Store release work for the competition;
- a second state-management library;
- changes to domain arithmetic or existing production semantics.

## Testing strategy

### Boundary tests

- Existing product entrypoints and units must not import
  `package:prep_book/championship/`.
- The competition unit may import Flutter, Bloc, `http`, the existing domain,
  export, localization, and responsive presentation contracts.
- The competition unit must not import persistence, SQLite, `dart:io`, or a
  provider SDK.

### Pure Dart tests

- Decode the checked-in extraction fixture.
- Reject schema versions other than `1`.
- Reject JSON numbers where decimal strings are required.
- Resolve every supported unit alias and reject unknown aliases.
- Keep null or ambiguous model fields unresolved.
- Refuse an unconfirmed field.
- Map a fully verified draft into exact domain objects.
- Prove the sample target produces the independently checked batch and quantity
  results.

### Endpoint tests

- Reject non-POST requests.
- Reject invalid content type and malformed JSON.
- Enforce text, MIME, and decoded-image limits.
- Assert the provider request uses the configured model, strict schema,
  `store: false`, no tools, and the expected timeout.
- Parse only `output_text` message content from a successful response.
- Map provider timeout, rate limit, malformed output, and configuration failure
  to stable public errors.
- Assert source data never reaches the logger fake.

### Cubit and widget tests

- Sample mode reaches review without an HTTP request.
- Text and image submissions expose loading, success, and retryable failure.
- A later submission supersedes an earlier response.
- Ambiguous unit blocks calculation.
- Confirming a corrected unit enables the next phase.
- Exact calculation produces the expected target, batch count, totals, and
  per-batch values.
- Widths `599`, `600`, `839`, and `840` use the existing width classes.
- Width and text-scale changes preserve source, review, target, and result.
- Keyboard-only navigation reaches every editable field and action.
- English and Korean copy has no visible overflow at text scale `3.0`.

### Runtime acceptance

- Fresh desktop Chrome session, no stored site data.
- Fresh mobile-width Chrome session.
- Safari desktop session.
- Sample flow with endpoint unavailable.
- Live text flow.
- Live image flow using rights-cleared synthetic content.
- Retry after one forced endpoint failure.
- Production-sheet preview and PDF download or print cancellation.
- Reload proves that the prior recipe is not restored.
- Browser network inspection shows no API key and no unexpected request.
- Vercel logs show no recipe text or image data.

## Acceptance criteria

- A public, no-login URL loads successfully in a fresh browser.
- The checked-in sample reaches an exact calculated result in under 90 seconds.
- Text and one supported image can produce a strict-schema review draft.
- Every proposal shows evidence, confidence, and issues.
- Missing or unsupported units block calculation until the visitor corrects and
  confirms them.
- The language model never calculates scaled production quantities.
- The existing exact calculator produces all totals and batch values.
- The existing production-sheet feature opens from the in-memory run.
- Reset and reload leave no recipe source in application storage.
- Endpoint and browser bundles contain no secret.
- The sample remains usable when live extraction fails.
- Existing iOS and Android development, staging, and production entrypoints
  compile and behave without the competition variant.
- `flutter analyze`, Bloc lint, endpoint tests, the full randomized Flutter test
  suite, web release build, and coverage gate pass.
- The public deployment remains available through 2026-10-17.

## Post-competition decision

Competition judging and voting are not product-market validation.
After the event, the variant remains isolated until direct kitchen-user tests
show all of the following:

- at least five operators import their own recipes;
- at least three prefer guarded import to manual entry;
- review plus correction is materially faster than manual entry;
- ambiguous units are reliably blocked before calculation;
- at least one generated production plan is used in real work.

If those conditions are not met, remove the live endpoint and competition
presentation while retaining the schema, fixtures, mapper tests, and lessons.
If they are met, write a new product design before integrating import into the
normal mobile workflow.
