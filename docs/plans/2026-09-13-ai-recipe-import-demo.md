# AI Recipe Import Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task by task. Keep the
> checklist current as work proceeds.

**Goal:** Publish an isolated Flutter Web competition variant that converts one
recipe text or image into an evidence-backed review draft, blocks unresolved
ambiguity, and delegates every production quantity to PrepBook's existing exact
calculator and production-sheet export.

**Architecture:** Competition Flutter code lives under `lib/championship/` and
starts from `lib/main_championship.dart`. The normal development, staging, and
production mobile entrypoints never import it. A single serverless endpoint uses
AI only to extract a strict versioned draft. The browser requires explicit human
confirmation, maps the verified draft into existing domain objects, calculates
with `ProductionCalculator(maxPlannedBatches: 1000)`, and creates one in-memory
`ProductionRun`. No demo data is persisted.

**Tech stack:** Dart 3.12, Flutter 3.44 or later, Material 3, `bloc`,
`flutter_bloc`, PrepBook domain and export units, `http`, `file_picker`, Node.js
Web APIs, OpenAI Responses API strict JSON Schema, Vercel Functions, Flutter
Test, and Node's built-in test runner.

**Design:** `docs/specs/2026-09-13-ai-recipe-import-demo.md`

## Scope decision

This is a competition variant, not a product pivot.

The approved first-release source of truth remains
`docs/notes/2026-09-06-prepbook-pro-design.md`. Its offline mobile product,
repository boundaries, and release priorities remain unchanged. This plan
creates one explicitly isolated exception for a public web demo.

The reusable output of this work is the guarded
`ExtractedRecipeDraft -> VerifiedRecipeDraft -> Recipe` boundary. Competition
landing copy, sample content, serverless transport, and submission-specific
presentation remain variant-only until direct kitchen-user validation supports
a separate product decision.

## Definition of Done

- [ ] A fresh unauthenticated browser can open the public demo.
- [ ] The checked-in sample completes without any network request.
- [ ] Sample, text, and one supported image reach the same review model.
- [ ] Every extracted value shows source evidence, confidence, and issues.
- [ ] Missing or unsupported values block calculation until corrected and
      explicitly confirmed.
- [ ] The AI endpoint never scales quantities, converts units, infers density,
      or fabricates missing values.
- [ ] The existing exact calculator produces all totals and batch values.
- [ ] The existing production-sheet flow opens from the in-memory run.
- [ ] Reset and reload leave no source, draft, or run in application storage.
- [ ] No API key appears in Flutter assets, browser requests, logs, or the
      repository.
- [ ] The normal Android and iOS development entrypoints still build.
- [ ] Static analysis, Bloc lint, Flutter tests, Node tests, randomized coverage,
      web release build, and repository boundary tests pass.
- [ ] The public deployment remains available through 2026-10-17.

## Global constraints

- Keep `lib/main_development.dart`, `lib/main_staging.dart`, and
  `lib/main_production.dart` free of championship imports.
- Put all variant production Dart under `lib/championship/`.
- Support Flutter Web only for the championship entrypoint.
- Do not initialize SQLite or use any persistence repository in the variant.
- Keep recipe source, image bytes, drafts, and runs in memory only.
- Accept text up to `20,000` Unicode scalar values or one JPEG, PNG, or WebP
  image up to `8 MiB` decoded.
- Do not accept PDF, spreadsheet, document, HEIC, URL, camera, or multi-image
  input in this milestone.
- Keep the sample available when the endpoint is absent, failing, or
  rate-limited.
- Use decimal strings in extraction and review models. Do not introduce
  floating-point quantities.
- Require explicit operator confirmation before a value enters the domain.
- Never infer a missing amount, unit, density, mass-to-volume conversion, or
  sub-recipe.
- Do not alter existing domain arithmetic, unit conversion, batch planning,
  warning, or PDF semantics.
- Call the provider with strict JSON Schema, no tools, low reasoning effort, and
  `store: false`.
- Keep `OPENAI_API_KEY` and `OPENAI_MODEL` server-side.
- Do not log submitted text, image data, extracted fields, or provider output.
- Return `Cache-Control: no-store` from the extraction endpoint.
- Preserve edits across retryable failures and responsive layout changes.
- Discard all in-memory state on Reset and browser reload.
- Reuse existing `WindowWidthClass` thresholds at `599`, `600`, `839`, and
  `840` logical pixels.
- Keep English and Korean UI usable at text scale `3.0`.
- Maintain `100.0%` line coverage for reached Dart files.
- Run `trunk fmt` and `trunk check` only with explicit paths.
- Run at most one browser, simulator, emulator, Gradle, or Xcode job at a time.
- Do not open or merge a pull request without separate operator approval.

## Delivery order and deadline cut line

| Date | Required outcome |
| --- | --- |
| 2026-09-13 | Tasks 1 and 2: isolated web shell and deterministic sample pipeline. |
| 2026-09-14 | Task 3: strict extraction endpoint. |
| 2026-09-15 | Task 4: Flutter transport and one-image input. |
| 2026-09-16 to 2026-09-17 | Tasks 5 and 6: complete reviewed flow and production sheet. |
| 2026-09-18 | Feature freeze, registration check, stable public URL. |
| 2026-09-19 | Runtime acceptance, screenshots, and submission copy. |
| 2026-09-20 | Final verification and submission. |

If schedule pressure appears, cut scope in this order:

1. Remove live image input while retaining text and sample.
2. Remove production-sheet download while retaining exact on-screen results.
3. Reduce presentation polish.

Never cut the strict schema, evidence display, explicit confirmation, exact
calculator boundary, network-independent sample, privacy copy, or final
verification.

## Planned file structure

```text
api/
  extract-recipe.mjs
  lib/
    extract-recipe-handler.mjs
    extract-recipe-handler_test.mjs
    recipe-draft-schema.mjs
assets/
  championship/
    sample_croissant_draft.json
lib/
  main_championship.dart
  championship/
    championship.dart
    cubit/
      championship_demo_cubit.dart
      championship_demo_state.dart
    import/
      championship_recipe_mapper.dart
      championship_run_builder.dart
      http_recipe_import_client.dart
      recipe_draft_verifier.dart
      recipe_import_client.dart
      recipe_import_request.dart
      unit_alias_resolver.dart
    input/
      file_picker_recipe_image_picker.dart
      recipe_image_picker.dart
    model/
      championship_recipe_bundle.dart
      extracted_recipe_draft.dart
      review_recipe_draft.dart
      verified_recipe_draft.dart
    sample/
      championship_sample_loader.dart
    view/
      championship_app.dart
      championship_demo_page.dart
      result_step.dart
      review_step.dart
      source_step.dart
      target_step.dart
      widgets/
        privacy_notice.dart
        review_field_card.dart
test/
  championship/
    championship_boundary_test.dart
    cubit/
    import/
    input/
    integration/
    model/
    sample/
    view/
web/
package.json
vercel.json
.vercelignore
```

---

## Task 1: Establish the isolated web boundary

**Files**

- Create: `test/championship/championship_boundary_test.dart`
- Create: `lib/championship/championship.dart`
- Create: `lib/championship/view/championship_app.dart`
- Create: `lib/championship/view/championship_demo_page.dart`
- Create: `lib/main_championship.dart`
- Create through Flutter tooling: `web/`
- Modify: `.metadata`
- Modify: `merry.yaml`
- Test: `test/championship/view/championship_demo_page_test.dart`

### Step 1.1: Write the failing boundary test

Create a test that recursively scans these protected paths and rejects the
literal `package:prep_book/championship/`:

```dart
const protectedRoots = <String>[
  'lib/app',
  'lib/application',
  'lib/domain',
  'lib/export',
  'lib/persistence',
  'lib/presentation',
  'lib/main_development.dart',
  'lib/main_staging.dart',
  'lib/main_production.dart',
];
```

The same test must require `lib/championship` to exist and reject these strings
inside championship production code:

```dart
const bannedCompetitionSubstrings = <String>[
  'dart:io',
  'package:sqflite',
  'prep_book/persistence/',
  'RecipeRepository',
  'IngredientRepository',
  'ProductionRunRepository',
  'OPENAI_API_KEY',
];
```

Use the complete-import-directive parsing pattern already used by
`test/presentation/presentation_boundary_test.dart`. Allow only Flutter, Bloc,
HTTP, file picker, championship, domain, export, localization, production-sheet,
and responsive presentation imports.

Run:

```sh
flutter test test/championship/championship_boundary_test.dart
```

Expected result: RED because `lib/championship` does not yet exist.

### Step 1.2: Restore only the Flutter web host

Run:

```sh
flutter create --platforms=web .
```

Inspect the complete diff before continuing. The command may add or update
`web/` and `.metadata`; it must not rewrite native product code or documentation.
Set the HTML title, manifest name, and description to PrepBook AI competition
copy. Do not add a custom service worker or persistent web cache.

### Step 1.3: Write the shell widget test

Pump `ChampionshipApp` at widths `390` and `900`. Assert:

- title and one-sentence boundary copy are visible;
- Source, Review, Target, and Result step labels are visible;
- the current phase is Source;
- resizing does not replace the app-level state owner;
- text scale `3.0` does not overflow.

Expected result: RED because the app shell does not exist.

### Step 1.4: Implement the smallest web shell

Create `ChampionshipApp` with Material 3 and existing English/Korean delegates.
Create one responsive page with static phase navigation and a placeholder source
card. Do not implement sample, endpoint, persistence, or calculation yet.

Create `lib/main_championship.dart` without calling the normal `bootstrap`:

```dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ChampionshipApp());
}
```

Add commands to `merry.yaml`:

```yaml
dev:
  championship:
    (description): Runs the competition web entrypoint in Chrome.
    (scripts): flutter run -d chrome --target lib/main_championship.dart

build:
  championship-web:
    (description): Builds the competition Flutter Web release.
    (scripts): flutter build web --release --target lib/main_championship.dart --tree-shake-icons
```

### Step 1.5: Verify and commit

Run:

```sh
flutter pub get
flutter test test/championship/championship_boundary_test.dart test/championship/view/championship_demo_page_test.dart
flutter build web --release --target lib/main_championship.dart --tree-shake-icons
```

Inspect `build/web/index.html` and the full staged diff.

Commit:

```sh
git commit -m "feat(championship): establish isolated web variant"
```

---

## Task 2: Build the final deterministic sample pipeline

**Files**

- Create: `assets/championship/sample_croissant_draft.json`
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/championship/model/extracted_recipe_draft.dart`
- Create: `lib/championship/model/review_recipe_draft.dart`
- Create: `lib/championship/model/verified_recipe_draft.dart`
- Create: `lib/championship/model/championship_recipe_bundle.dart`
- Create: `lib/championship/import/unit_alias_resolver.dart`
- Create: `lib/championship/import/recipe_draft_verifier.dart`
- Create: `lib/championship/import/championship_recipe_mapper.dart`
- Create: `lib/championship/import/championship_run_builder.dart`
- Create: `lib/championship/sample/championship_sample_loader.dart`
- Modify: `lib/championship/championship.dart`
- Test: matching files under `test/championship/model/`, `import/`, and `sample/`

### Public interfaces

```dart
enum RecipeImportSourceKind { sample, text, image }
enum ExtractionConfidence { high, medium, low }
enum DraftScalingBehavior { proportional, perBatch, fixedOnce, manual }

final class ExtractedField<T> {
  const ExtractedField({
    required this.value,
    required this.evidence,
    required this.confidence,
    required this.issues,
  });

  final T? value;
  final String evidence;
  final ExtractionConfidence confidence;
  final List<String> issues;
}

final class ExtractedRecipeDraft {
  factory ExtractedRecipeDraft.fromJson(Map<String, Object?> json);
  Map<String, Object?> toJson();
}

final class ChampionshipSampleLoader {
  const ChampionshipSampleLoader({required AssetBundle bundle});
  Future<ExtractedRecipeDraft> load();
}

sealed class RecipeDraftVerification {
  const RecipeDraftVerification();
}

final class InvalidRecipeDraft extends RecipeDraftVerification {
  const InvalidRecipeDraft(this.issues);
  final List<RecipeDraftIssue> issues;
}

final class ValidRecipeDraft extends RecipeDraftVerification {
  const ValidRecipeDraft(this.draft);
  final VerifiedRecipeDraft draft;
}

final class RecipeDraftVerifier {
  const RecipeDraftVerifier({this.units = const UnitAliasResolver()});
  final UnitAliasResolver units;
  RecipeDraftVerification verify(ReviewRecipeDraft draft);
}

final class ChampionshipRecipeMapper {
  const ChampionshipRecipeMapper({this.units = const UnitAliasResolver()});
  ChampionshipRecipeBundle map(
    VerifiedRecipeDraft draft, {
    required DateTime modifiedAt,
  });
}

final class ChampionshipRunBuilder {
  const ChampionshipRunBuilder({
    this.mapper = const ChampionshipRecipeMapper(),
    this.calculator = const ProductionCalculator(maxPlannedBatches: 1000),
  });

  ProductionRun build({
    required VerifiedRecipeDraft draft,
    required String targetAmount,
    required String targetUnit,
    required DateTime createdAt,
    required String runId,
  });
}
```

### Step 2.1: Add one rights-cleared fixture

Create a version `1` sample JSON matching the design contract:

- recipe: `Croissant dough`;
- base yield: `24 piece`;
- maximum batch yield: `12 piece`;
- flour: `1000 g`, proportional;
- butter: `500 g`, proportional;
- water: `480`, null unit, issue
  `The source does not state a unit.`;
- dusting flour: manual, null amount and unit;
- note: `Laminate cold; rest 20 minutes between folds.`

Add the fixture to Flutter assets. Tests and production sample mode must load the
same file; do not maintain a second hard-coded sample.

### Step 2.2: Write strict decoder tests

Assert the fixture decodes exactly and round-trips. Mutate the fixture and
expect `FormatException` for:

- schema version other than `1`;
- JSON numeric quantities instead of decimal strings;
- missing `issues`;
- unknown confidence or scaling behavior;
- a manual component with numeric amount;
- unrecognized top-level or nested properties.

Expected result: RED before the model exists.

### Step 2.3: Implement the versioned extraction model

Use exhaustive property-set validation and unmodifiable lists. Preserve evidence
verbatim. Keep absent values as `null`; never normalize them into guesses.

### Step 2.4: Test and implement explicit unit resolution

Cover every alias defined by the design. Normalize only trim and lowercase.
Reject unsupported aliases such as `cup`, `oz`, and `unknown scoop`.
Do not inspect ingredient names when resolving units.

### Step 2.5: Test and implement review state

`ReviewField<T>` keeps the proposed value, current value, evidence, confidence,
extraction issues, local issues, and confirmation state.

Required behavior:

- no extracted field starts confirmed;
- editing clears confirmation;
- bulk confirmation confirms only present, locally valid fields without
  extraction issues;
- ambiguous water remains unresolved;
- manual components require explicit manual confirmation;
- issue order follows visible field order.

### Step 2.6: Test and implement verification

Verification must reject:

- blank recipe name;
- zero or negative base yield;
- unsupported base unit;
- incompatible maximum batch yield;
- empty component list;
- blank component name;
- unconfirmed behavior;
- non-manual null amount or unit;
- manual numeric amount;
- unsupported component unit;
- any unresolved extraction issue.

It returns `VerifiedRecipeDraft` only after all required fields are explicitly
confirmed. It does not construct domain objects.

### Step 2.7: Test and implement exact domain mapping

Map verified values to one revision-1 `Recipe`, stable ordered `Ingredient`
entries, and ordered `RecipeComponent` values. Create identifiers from list
order; never accept model-provided ids. Parse amounts with `Quantity.parse`.
Inject timestamps.

Repeated normalized ingredient names may share one ingredient identity while
remaining separate components.

### Step 2.8: Test and implement the run builder

For target `180 piece`, independently assert:

```dart
expect(run.result.batchPlan.batchCount, 15);
expect(run.result.components[0].total!.displayed,
    Quantity.parse('7500', Unit.gram));
expect(run.result.components[1].total!.displayed,
    Quantity.parse('3750', Unit.gram));
expect(run.result.components[2].total!.displayed,
    Quantity.parse('3600', Unit.gram));
expect(run.result.components[3].total, isNull);
```

Also test invalid decimal, zero target, unknown unit, incompatible unit, and more
than `1000` planned batches.

Construct an in-memory `ProductionRun` with empty dependency snapshot,
overrides, and acknowledged warnings. Do not call an application use case or
repository.

### Step 2.9: Prove the sample path

Load the asset through an injected `AssetBundle`, create review state, explicitly
correct water to `g`, confirm required values, verify, map, and calculate.
The test must prove that this path makes no HTTP or persistence call.

### Step 2.10: Verify and commit

Run:

```sh
flutter pub get
flutter gen-l10n
flutter test test/championship/model test/championship/import test/championship/sample
flutter test test/championship/championship_boundary_test.dart
flutter analyze
very_good test --coverage --test-randomize-ordering-seed random
lcov --summary coverage/lcov.info
```

Expected coverage: `100.0%` reached Dart lines.

Commit:

```sh
git commit -m "feat(championship): add verified recipe draft pipeline"
```

---

## Task 3: Add the guarded extraction endpoint

**Files**

- Create: `package.json`
- Create: `api/extract-recipe.mjs`
- Create: `api/lib/recipe-draft-schema.mjs`
- Create: `api/lib/extract-recipe-handler.mjs`
- Create: `api/lib/extract-recipe-handler_test.mjs`
- Modify: `merry.yaml`

### Endpoint contract

Accept exactly one JSON shape:

```json
{
  "sourceKind": "text",
  "text": "...",
  "imageDataUrl": null,
  "locale": "ko"
}
```

or:

```json
{
  "sourceKind": "image",
  "text": null,
  "imageDataUrl": "data:image/png;base64,...",
  "locale": "en"
}
```

Return the version `1` extraction draft directly on success. Return stable safe
errors:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "The submitted recipe could not be processed."
  }
}
```

Allowed public codes:

```text
method_not_allowed
invalid_content_type
invalid_request
unsupported_source
source_too_large
service_unconfigured
service_busy
service_timeout
invalid_model_output
service_failure
```

### Step 3.1: Create the dependency-free Node test surface

Use ESM and Node's built-in test runner:

```json
{
  "name": "prep-book-championship-endpoint",
  "private": true,
  "type": "module",
  "scripts": {
    "test:api": "node --test api/lib/extract-recipe-handler_test.mjs"
  }
}
```

### Step 3.2: Write failing request-validation tests

Inject `fetchImpl`, environment values, logger, and timeout. Cover:

- non-POST request;
- wrong content type;
- malformed or extra-property JSON;
- empty or over-limit text;
- unsupported image MIME;
- decoded image above `8 MiB`;
- unsupported locale;
- absent API key;
- mismatched configured origin;
- `Cache-Control: no-store` on every response.

Expected result: RED before the handler exists.

### Step 3.3: Implement local validation

Count Unicode scalar values with `[...text].length`. Decode only the base64
payload after anchored data-URL validation. Accept only `image/jpeg`,
`image/png`, and `image/webp`, plus locales `ko` and `en`.

Do not send an invalid request to the provider.

### Step 3.4: Define one strict JSON Schema

Every object sets `additionalProperties: false` and lists all required keys.
Quantities are nullable strings, never JSON numbers. Confidence and behavior use
closed enums. Issue lists are always present.

Export one extraction instruction that includes:

- use null instead of guessing;
- copy concise evidence;
- report ambiguity;
- do not calculate a production target;
- do not scale, convert, infer density, search the web, or generate a new
  recipe.

### Step 3.5: Test and implement the provider request

Assert the request uses:

- `POST https://api.openai.com/v1/responses`;
- configured model from `OPENAI_MODEL`;
- strict `text.format` JSON Schema;
- `store: false`;
- low reasoning effort;
- no tools, files, background mode, or streaming;
- text input or one high-detail image input.

Use an AbortController with a `25` second timeout. Parse only `output_text`
message content. Validate parsed JSON again before returning it. Never return the
raw provider object.

### Step 3.6: Test and implement failure mapping

Map timeout, `429`, provider non-success, malformed output, missing output, and
unexpected exceptions to stable public codes. The logger may receive only:

```js
{
  requestId,
  status,
  latencyMs,
  errorCategory,
}
```

Tests must prove serialized logs do not include request text, image data,
ingredient names, or model output.

### Step 3.7: Add entrypoint and commands

`api/extract-recipe.mjs` exports the configured POST handler. Add
`merry api test` for `npm run test:api`.

Run:

```sh
npm run test:api
node --check api/extract-recipe.mjs
node --check api/lib/recipe-draft-schema.mjs
node --check api/lib/extract-recipe-handler.mjs
```

### Step 3.8: Commit

Search the staged diff for `sk-`, embedded environment assignments, recipe
source, and image data. Expect no match.

Commit:

```sh
git commit -m "feat(championship): add guarded recipe extraction endpoint"
```

---

## Task 4: Connect Flutter text and single-image import

**Files**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/championship/import/recipe_import_request.dart`
- Create: `lib/championship/import/recipe_import_client.dart`
- Create: `lib/championship/import/http_recipe_import_client.dart`
- Create: `lib/championship/input/recipe_image_picker.dart`
- Create: `lib/championship/input/file_picker_recipe_image_picker.dart`
- Test: matching files under `test/championship/import/` and `input/`

### Public interfaces

```dart
sealed class RecipeImportRequest {
  const RecipeImportRequest();
  Map<String, Object?> toJson(String locale);
}

abstract interface class RecipeImportClient {
  Future<ExtractedRecipeDraft> extract(
    RecipeImportRequest request, {
    required String locale,
  });
}

abstract interface class RecipeImagePicker {
  Future<SelectedRecipeImage?> pick();
}
```

### Step 4.1: Add only transport dependencies

Add pinned-compatible `http` and `file_picker` dependencies. Do not add an
OpenAI SDK to Flutter. Run `flutter pub get` and inspect native plugin changes.

### Step 4.2: Test and implement request values

Cover:

- blank and over-limit text rejection;
- exact `20,000` scalar text acceptance;
- exact `8 MiB` image acceptance and one-byte-over rejection;
- supported and unsupported MIME values;
- exact endpoint JSON keys;
- base64 generation only during serialization.

Keep original text content; trimming is only for blank validation.

### Step 4.3: Test and implement the HTTP client

Inject `http.Client` and endpoint URI. Assert one JSON POST with no authorization
header. Apply a `27` second client timeout. Decode success through
`ExtractedRecipeDraft.fromJson`. Map endpoint errors to local public failure
enums. Do not auto-retry.

### Step 4.4: Test and implement the image picker

Call file picker with one custom file, `withData: true`, and allowed extensions
`jpg`, `jpeg`, `png`, and `webp`. Never use a filesystem path.

Reject absent bytes, multiple returned files, extension/MIME mismatch,
unsupported extension, and over-limit bytes. Cancellation returns `null`.

### Step 4.5: Verify normal mobile compatibility

Run sequentially:

```sh
flutter test test/championship/import test/championship/input
flutter test test/championship/championship_boundary_test.dart
flutter build web --release --target lib/main_championship.dart --tree-shake-icons
flutter build apk --debug --flavor development --target lib/main_development.dart
flutter build ios --simulator --debug --flavor development --target lib/main_development.dart
```

### Step 4.6: Commit

```sh
git commit -m "feat(championship): connect text and image import"
```

---

## Task 5: Implement the evidence-based four-phase workflow

**Files**

- Create: `lib/championship/cubit/championship_demo_state.dart`
- Create: `lib/championship/cubit/championship_demo_cubit.dart`
- Create: `lib/championship/view/source_step.dart`
- Create: `lib/championship/view/review_step.dart`
- Create: `lib/championship/view/target_step.dart`
- Create: `lib/championship/view/result_step.dart`
- Create: `lib/championship/view/widgets/privacy_notice.dart`
- Create: `lib/championship/view/widgets/review_field_card.dart`
- Modify: `lib/championship/view/championship_app.dart`
- Modify: `lib/championship/view/championship_demo_page.dart`
- Modify: `lib/main_championship.dart`
- Modify: `lib/l10n/arb/app_en.arb`
- Modify: `lib/l10n/arb/app_ko.arb`
- Test: matching Cubit and widget tests under `test/championship/`

### State machine

```dart
enum ChampionshipDemoPhase { source, review, target, result }
enum ChampionshipImportStatus { idle, loading, failed }
enum ChampionshipCalculationStatus { idle, calculating, failed }
```

The Cubit owns source, current request generation, extracted draft, review draft,
verified draft, target strings, calculation failure, and optional run. It owns
no `BuildContext`, controller, focus node, or localized string.

### Step 5.1: Write failing Cubit tests

Cover the complete state machine:

- sample reaches Review without HTTP;
- text and image expose loading, success, and retryable failure;
- image cancellation preserves Source;
- second submission invalidates a late first response;
- Reset invalidates in-flight work and clears all state;
- edit clears confirmation;
- bulk confirmation leaves ambiguity unresolved;
- unresolved review remains in Review with ordered issues;
- corrected and confirmed review reaches Target;
- Back preserves data;
- valid target calculation reaches Result;
- invalid decimal, unsupported unit, incompatible unit, zero target, and batch
  limit remain in Target with data preserved;
- duplicate calculate taps invoke the builder once;
- Result Back returns to Target;
- responsive width changes require no Cubit event and cannot change state.

Use fixed clock and run-id callbacks.

### Step 5.2: Implement stale-response-safe orchestration

Increment one request generation for every submission and Reset. Capture it
before an awaited extraction and ignore completion when it no longer matches.
Do not silently replace user input. Do not automatically retry.

`calculate()` calls only `ChampionshipRunBuilder`. AI extraction is never called
from Target or Result.

### Step 5.3: Add localized copy

Add English and Korean strings for phase labels, sample, source input, privacy,
loading, failures, evidence, confidence, review controls, quantity fields,
behaviors, target, exact calculation, batch details, warnings, reset, and
production-sheet action.

Privacy copy must state:

- PrepBook does not persist the submitted source;
- live input is sent to the configured AI provider;
- provider account controls apply;
- confidential or personal content should use the sample instead.

Do not claim that the provider stores nothing.

Run `flutter gen-l10n`.

### Step 5.4: Test and implement Source

Requirements:

- no login;
- sample works without privacy consent or HTTP;
- live text/image requires explicit consent;
- blank text cannot submit;
- selected image shows filename and size, not the source image;
- loading prevents duplicate submission;
- failure preserves source and offers Retry and Sample;
- keyboard navigation reaches all actions;
- compact text scale `3.0` does not overflow.

### Step 5.5: Test and implement Review

Every field card shows proposed value, evidence, confidence, extraction issues,
local issues, current value, edited state, and explicit confirmation.

Use stable keys derived from a `RecipeDraftPath`. Manual lines have no amount
input. Unit selection contains only explicit aliases plus unresolved state.
Confidence is never a substitute for confirmation and is not communicated by
color alone.

Compact mode uses one column. Medium/expanded mode may place evidence beside
editing when the large-text fallback allows. Resize tests must prove that edits
and confirmations survive layout changes.

### Step 5.6: Test and implement Target

Show the verified recipe and base yield. Initialize the target unit to the
verified base-yield unit and leave amount empty. Calculation occurs only after a
button press, not per keystroke.

### Step 5.7: Test and implement the initial Result

Show:

- `Exact PrepBook calculation`;
- `AI did not calculate these quantities`;
- recipe and target;
- batch count and remainder;
- component totals;
- per-batch values;
- manual-review lines;
- existing domain warnings.

Read display names from `run.ingredientSnapshot`. Render stored domain results;
do not recalculate in widgets.

### Step 5.8: Wire dependencies at the composition root

Create HTTP client, import client, image picker, sample loader, verifier, and run
builder in `main_championship.dart`. Resolve the same-origin endpoint from:

```dart
const String.fromEnvironment(
  'AI_IMPORT_ENDPOINT',
  defaultValue: '/api/extract-recipe',
)
```

The root owns and closes `http.Client`. Do not initialize SQLite or normal
application repositories.

### Step 5.9: Add the sample vertical-slice integration test

Drive the real fixture through:

```text
Try sample
-> Confirm all unambiguous
-> set Water unit to g
-> confirm Water
-> confirm manual Dusting flour
-> Continue
-> target 180 piece
-> Calculate exactly
```

Assert the final `ProductionRun` contains `15` batches and independently checked
totals. Assert the import client recorded zero calls.

### Step 5.10: Verify and commit

Run:

```sh
flutter pub get
flutter gen-l10n
flutter test test/championship/cubit test/championship/view test/championship/integration
flutter test test/championship/championship_boundary_test.dart
flutter analyze
dart run bloc_tools:bloc lint .
very_good test --coverage --test-randomize-ordering-seed random
lcov --summary coverage/lcov.info
```

Run explicit-path `trunk fmt` and `trunk check` over changed Dart, ARB, YAML, and
Markdown files.

Commit:

```sh
git commit -m "feat(championship): add evidence-based demo workflow"
```

---

## Task 6: Reuse production-sheet export and configure deployment

**Files**

- Modify: `lib/championship/view/result_step.dart`
- Modify: `lib/championship/view/championship_app.dart`
- Modify: `lib/championship/view/championship_demo_page.dart`
- Modify: `lib/main_championship.dart`
- Create: `vercel.json`
- Create: `.vercelignore`
- Test: `test/championship/view/result_step_test.dart`
- Test: `test/championship/integration/production_sheet_integration_test.dart`

### Step 6.1: Write the production-sheet callback test

Pass a callback rather than subclassing the existing final launcher:

```dart
typedef OpenChampionshipProductionSheet = Future<void> Function(
  BuildContext context,
  ProductionRun run,
);
```

Assert the Result action passes the identical in-memory `ProductionRun` instance.
Assert cancellation or callback failure leaves Result and its run visible.

Expected result: RED before the action is wired.

### Step 6.2: Wire the existing export feature

At the composition root, create the existing production-sheet launcher and pass
a callback through the app/page/result boundary. Do not modify:

- `ProductionSheetBuilder`;
- `ProductionSheetPdfRenderer`;
- existing production-sheet Cubit;
- shipping production-result presentation.

The variant must reuse those contracts exactly.

### Step 6.3: Verify web export manually

Build and serve:

```sh
flutter build web --release --target lib/main_championship.dart \
  --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe \
  --tree-shake-icons
python3 -m http.server 8080 --directory build/web
```

Complete the sample flow, open batch and total production-sheet views, invoke
browser download or print preview, and cancel before submitting a system print
job. Confirm the run remains visible and no unexpected request occurs.

### Step 6.4: Add Vercel configuration

Use local prebuilt deployment. `vercel.json` must define:

- Flutter web build command for `lib/main_championship.dart`;
- `build/web` output;
- `30` second endpoint max duration;
- SPA rewrite excluding `/api/`.

`.vercelignore` excludes native build trees, tests, coverage, docs, environment
files, PEM files, and local build artifacts while retaining source, assets, API,
Flutter metadata, and deployment config.

### Step 6.5: Run regression gates

Run:

```sh
flutter analyze
dart run bloc_tools:bloc lint .
npm run test:api
very_good test --coverage --test-randomize-ordering-seed random
flutter build web --release --target lib/main_championship.dart \
  --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe \
  --tree-shake-icons
flutter build apk --debug --flavor development --target lib/main_development.dart
flutter build ios --simulator --debug --flavor development --target lib/main_development.dart
lcov --summary coverage/lcov.info
```

Run Android and iOS builds sequentially.

### Step 6.6: Commit

Inspect the diff. Expect no modification to domain arithmetic, export internals,
or normal product entrypoints.

Commit:

```sh
git commit -m "feat(championship): reuse production sheet and deploy web demo"
```

---

## Task 7: Harden, document, deploy, and prepare submission

**Files**

- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/specs/2026-09-13-ai-recipe-import-demo.md`
- Modify: this plan
- Create: `docs/notes/2026-09-20-ai-championship-submission.md`
- Modify ARB files only for copy defects proven by runtime acceptance

### Step 7.1: Correct repository status

Update README so it no longer describes production-sheet export as
unimplemented. Verify every status statement against the current tree before
writing it.

Add an `AI Championship variant` section that states:

- this is an optional guarded-import web variant;
- normal mobile flavors remain offline and backend-free;
- live source is sent to the configured AI provider only after explicit action;
- sample mode is network-independent;
- the entrypoint and build command;
- links to the design and plan.

Add one narrow exception to `CLAUDE.md` immediately after the scope fence. Do not
replace the approved source-of-truth designation.

### Step 7.2: Run one final local gate at a single commit

Run exactly:

```sh
flutter pub get
flutter gen-l10n
merry check
merry coverage
npm run test:api
flutter build web --release --target lib/main_championship.dart \
  --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe \
  --tree-shake-icons
flutter build apk --debug --flavor development --target lib/main_development.dart
flutter build ios --simulator --debug --flavor development --target lib/main_development.dart
lcov --summary coverage/lcov.info
```

Record command results, test counts, coverage, output paths, and non-failing tool
warnings. Do not describe a warning as fixed unless its owning change is on this
branch.

### Step 7.3: Configure secrets outside the repository

Set production environment values interactively:

```text
OPENAI_API_KEY=<secret>
OPENAI_MODEL=<approved extraction model>
ALLOWED_ORIGIN=<final production origin>
```

Do not echo the API key into shell history. Search tracked and untracked files
for key patterns before deployment.

### Step 7.4: Build and deploy prebuilt output

Run:

```sh
vercel pull --yes --environment=production
vercel build --prod
vercel deploy --prebuilt --prod
```

Record the final production URL. Verify root and nested routes without
authentication and verify `/api/extract-recipe` reaches the function.

### Step 7.5: Perform public runtime acceptance

Use synthetic rights-cleared source only. Verify:

1. Desktop Chrome fresh profile, sample flow with endpoint unavailable.
2. Desktop Chrome live text extraction.
3. Desktop Chrome live PNG extraction under `8 MiB`.
4. Mobile-width Chrome at `390` logical pixels.
5. Desktop Safari.
6. Forced busy failure followed by successful Retry.
7. Ambiguous water unit blocks calculation.
8. Target `180 piece` produces `15` batches and checked totals.
9. Production-sheet batch and total views render.
10. Download or print UI opens and cancellation preserves the run.
11. Reset clears all in-memory state.
12. Reload restores nothing.
13. Browser storage contains no recipe source, extraction response, key, or run.
14. Browser requests contain no key or unexpected third-party destination.
15. Function logs contain no source text, ingredient name, image data, or model
    output.

Save screenshots and synthetic PDF outside the repository in one recorded
temporary directory.

### Step 7.6: Write the submission note

Create:

```markdown
# PrepBook AI Championship Submission

## Service
## Problem
## Solution
## AI use
## Deterministic safety boundary
## Tools used
## Privacy boundary
## Demo script
## Deployment and judging availability
## Existing-service disclosure
## Verification evidence
```

The note must distinguish runtime AI from AI-assisted development tools. It must
state that AI creates a review draft only and that the existing exact calculator
produces every scaled quantity. The demo script must fit within `90` seconds.
The existing-service disclosure must accurately separate the pre-existing mobile
core from the new competition variant.

### Step 7.7: Record execution evidence

Only after public acceptance passes, change the design status to
`Implemented and publicly verified` and append an `Execution Evidence` section
to this plan with:

- final commit SHA;
- toolchain versions;
- commands and exit results;
- test counts and coverage;
- Android, iOS, and web build results;
- public URL;
- browser matrix;
- temporary artifact directory;
- any partial verification explicitly marked `[PARTIAL]` and its consequence.

### Step 7.8: Run repository hygiene review

Run:

```sh
git diff --check origin/main...HEAD
git status --short
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
```

Confirm the branch contains no API key, `.env`, real recipe, user image,
generated PDF, screenshot, database, persisted run, provider SDK in Flutter,
normal-entrypoint championship import, or unrelated refactor.

### Step 7.9: Commit verified documentation

```sh
git commit -m "docs(championship): record verified competition submission"
```

Do not open or merge a pull request without separate approval.

## Completion criteria

Implementation is complete only when all seven tasks are committed, the final
local gates pass at the same commit, normal Android and iOS development builds
still pass, the public URL supports both no-network sample and live extraction,
unresolved values demonstrably block calculation, all production quantities
come from the existing exact engine, production-sheet export opens from the
in-memory run, browser storage and function logs contain no submitted source,
and deployment availability through 2026-10-17 is recorded.

Competition judging and voting are not product-market validation. After the
event, keep this variant isolated until direct kitchen-user testing shows all of
the following:

- at least five operators import their own recipes;
- at least three prefer guarded import to manual entry;
- review plus correction is materially faster than manual entry;
- ambiguous units are reliably blocked before calculation;
- at least one generated production plan is used in real work.

If those conditions fail, remove the live endpoint and competition presentation
while retaining the schema, fixture, mapper tests, and lessons. If they pass,
write a new product design before integrating import into the normal mobile
workflow.
