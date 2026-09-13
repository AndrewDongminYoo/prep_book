# AI Recipe Import Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> `superpowers:subagent-driven-development` (recommended) or
> `superpowers:executing-plans` to implement this plan task by task. Check each
> step only after its stated verification passes.

**Goal:** Publish an isolated Flutter Web competition variant that converts one
recipe text or image into an evidence-backed review draft, blocks unresolved
ambiguity, and delegates every production quantity to PrepBook's existing exact
calculator and production-sheet export.

**Architecture:** Competition Flutter code lives under `lib/championship/` and
starts from `lib/main_championship.dart`. Normal development, staging, and
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

The reusable seam is the guarded
`ExtractedRecipeDraft -> VerifiedRecipeDraft -> Recipe` mapping. Competition
copy, sample content, serverless transport, and submission presentation remain
variant-only until separate kitchen-user validation justifies a product change.

## Definition of Done

- [ ] A fresh unauthenticated browser opens the public demo.
- [ ] The checked-in sample completes without a network request.
- [ ] Sample, text, and one supported image reach the same review model.
- [ ] Every extracted value displays evidence, confidence, and issues.
- [ ] Missing or unsupported values block calculation until corrected and
      explicitly confirmed.
- [ ] The AI endpoint never scales quantities, converts units, infers density,
      or fabricates missing values.
- [ ] The existing exact calculator produces every total and batch value.
- [ ] The existing production-sheet flow opens from the in-memory run.
- [ ] Reset and reload leave no source, draft, or run in application storage.
- [ ] No API key appears in Flutter assets, browser requests, logs, or the
      repository.
- [ ] Normal Android and iOS development entrypoints still build.
- [ ] Analysis, Bloc lint, Flutter tests, Node tests, randomized coverage,
      boundary tests, and web release build pass.
- [ ] The public deployment remains available through 2026-10-17.

## Global constraints

- Keep `lib/main_development.dart`, `lib/main_staging.dart`, and
  `lib/main_production.dart` free of championship imports.
- Put all variant production Dart under `lib/championship/`.
- Support Flutter Web only for the championship entrypoint.
- Do not initialize SQLite or use persistence repositories in the variant.
- Keep source text, image bytes, drafts, and runs in memory only.
- Accept text up to `20,000` Unicode scalar values or one JPEG, PNG, or WebP image up to `3 MiB` decoded.
- Exclude PDF, spreadsheet, document, HEIC, URL, camera, and multi-image input.
- Keep sample mode available when the endpoint is absent, failing, or
  rate-limited.
- Use decimal strings throughout extraction and review. Do not introduce
  floating-point quantities.
- Require explicit operator confirmation before a value enters the domain.
- Never infer missing amount, unit, density, mass-to-volume conversion, or
  sub-recipe.
- Do not alter existing arithmetic, unit conversion, batch planning, warning, or
  PDF semantics.
- Call the provider with strict JSON Schema, no tools, low reasoning effort, and
  `store: false`.
- Keep `OPENAI_API_KEY` and `OPENAI_MODEL` server-side.
- Do not log submitted text, image data, extracted fields, or provider output.
- Return `Cache-Control: no-store` from the extraction endpoint.
- Treat `ALLOWED_ORIGIN` as browser-origin defense, not authentication, and require a Vercel WAF rate limit before public deployment.
- Preserve edits across retryable failures and responsive layout changes.
- Discard all state on Reset and browser reload.
- Reuse existing responsive thresholds at `599`, `600`, `839`, and `840` logical
  pixels.
- Keep English and Korean UI usable at text scale `3.0`.
- Maintain `100.0%` line coverage for reached Dart files.
- Run `trunk fmt` and `trunk check` only with explicit paths.
- Run at most one browser, simulator, emulator, Gradle, or Xcode job at a time.
- Do not open or merge a pull request without separate approval.

## Delivery order and cut line

| Date                     | Required outcome                                                     |
| ------------------------ | -------------------------------------------------------------------- |
| 2026-09-13               | Tasks 1 and 2: isolated web shell and deterministic sample pipeline. |
| 2026-09-14               | Task 3: strict extraction endpoint.                                  |
| 2026-09-15               | Task 4: Flutter transport and one-image input.                       |
| 2026-09-16 to 2026-09-17 | Tasks 5 and 6: reviewed flow and production sheet.                   |
| 2026-09-18               | Feature freeze, registration check, stable public URL.               |
| 2026-09-19               | Runtime acceptance, screenshots, and submission copy.                |
| 2026-09-20               | Final verification and submission.                                   |

If schedule pressure appears, remove scope in this order:

1. Live image input; retain text and sample.
2. Production-sheet download; retain exact on-screen results.
3. Presentation polish.

Never cut strict schema, evidence, explicit confirmation, exact calculation,
network-independent sample, privacy copy, or final verification.

## Planned file structure

```text
api/
  extract-recipe.mjs
  lib/
    extract-recipe-handler.mjs
    extract-recipe-handler_test.mjs
    recipe-draft-schema.mjs
assets/championship/sample_croissant_draft.json
lib/
  main_championship.dart
  championship/
    championship.dart
    cubit/
    import/
    input/
    model/
    sample/
    view/
test/championship/
web/
package.json
vercel.json
.vercelignore
```

---

## Task 1: Establish the isolated web boundary

**Files:** create `lib/main_championship.dart`, the initial
`lib/championship/` shell, `test/championship/championship_boundary_test.dart`,
`test/championship/view/championship_demo_page_test.dart`, and generated `web/`;
modify `.metadata` and `merry.yaml`.

- [x] **1.1 Write the failing boundary test.** Recursively scan `lib/app`,
      `lib/application`, `lib/domain`, `lib/export`, `lib/persistence`,
      `lib/presentation`, and the three normal entrypoints. Reject
      `package:prep_book/championship/` in those paths. Require
      `lib/championship/` to exist and reject `dart:io`, `package:sqflite`,
      persistence imports, repository interfaces, and `OPENAI_API_KEY` in variant
      production code. Reuse the complete-import-directive approach from
      `test/presentation/presentation_boundary_test.dart`.

  Run:

  ```sh
  flutter test test/championship/championship_boundary_test.dart
  ```

  Expected: RED because `lib/championship/` does not exist.

- [x] **1.2 Restore only the Flutter web host.** Run
      `flutter create --platforms=web .`. Inspect the complete diff. Permit `web/`
      and `.metadata`; reject unrelated native or product rewrites. Set title,
      manifest name, and description to PrepBook AI competition copy. Add no custom
      service worker or persistent cache.

- [x] **1.3 Write the failing shell widget test.** Pump `ChampionshipApp` at
      widths `390` and `900`. Assert title, boundary statement, four phase labels,
      Source as the current phase, preserved root state across resize, and no
      overflow at text scale `3.0`.

- [x] **1.4 Implement the smallest web shell.** Create a localized Material 3
      app and responsive placeholder page. The entrypoint calls `runApp` directly;
      it must not call normal `bootstrap`, initialize SQLite, or create product
      repositories. Add `merry dev championship` and `merry build
championship-web` commands.

- [x] **1.5 Verify and commit.** Run:

  ```sh
  flutter pub get
  flutter test test/championship/championship_boundary_test.dart \
    test/championship/view/championship_demo_page_test.dart
  flutter build web --release --target lib/main_championship.dart \
    --tree-shake-icons
  ```

  Inspect `build/web/index.html` and staged diff. Commit:

  ```sh
  git commit -m "feat(championship): establish isolated web variant"
  ```

---

## Task 2: Build the final deterministic sample pipeline

**Files:** create the sample JSON; extraction, review, verified, bundle, unit
resolver, verifier, mapper, run builder, and sample loader classes; mirror them
under `test/championship/`; modify `pubspec.yaml`, lockfile, and championship
barrel.

**Required interfaces:**

```dart
enum RecipeImportSourceKind { sample, text, image }
enum ExtractionConfidence { high, medium, low }
enum DraftScalingBehavior { proportional, perBatch, fixedOnce, manual }

final class ChampionshipSampleLoader {
  const ChampionshipSampleLoader({required AssetBundle bundle});
  Future<ExtractedRecipeDraft> load();
}

sealed class RecipeDraftVerification {
  const RecipeDraftVerification();
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

- [x] **2.1 Add one rights-cleared fixture.** Create version `1` sample JSON for
      `Croissant dough`: base `24 piece`, maximum batch `12 piece`, flour `1000 g`,
      butter `500 g`, water `480` with null unit and blocking issue, manual dusting
      flour, and one preparation note. Register it as an asset. Production and tests
      must load this exact file; do not duplicate the sample in Dart.

- [x] **2.2 Write strict decoder tests.** Assert exact fixture values and
      round-trip behavior. Reject schema version other than `1`, JSON numeric
      quantities, missing `issues`, unknown confidence/behavior, numeric manual
      amount, and unknown properties. Expected: RED before the model exists.

- [x] **2.3 Implement immutable extraction models.** Validate exact property
      sets, preserve evidence verbatim, keep absent values as null, and return
      unmodifiable issue and component collections.

- [x] **2.4 Test and implement explicit unit resolution.** Cover every alias in
      the design. Normalize trim and lowercase only. Reject `cup`, `oz`, and unknown
      units. Never infer from ingredient name.

- [x] **2.5 Test and implement review state.** No field starts confirmed.
      Editing clears confirmation. Bulk confirmation accepts only present, locally
      valid, issue-free values. The ambiguous water unit and every manual line
      require explicit operator action.

- [x] **2.6 Test and implement verification.** Reject blank names, non-positive
      yield, unsupported/incompatible units, empty components, unconfirmed
      behavior, invalid manual/non-manual quantities, and unresolved issues. Return
      `VerifiedRecipeDraft` only when every required value is confirmed. Do not
      construct domain objects here.

- [x] **2.7 Test and implement exact domain mapping.** Create stable ordered ids,
      parse with `Quantity.parse`, inject timestamps, and map to revision-1 `Recipe`,
      `Ingredient`, and `RecipeComponent` values. Never accept provider ids.

- [x] **2.8 Test and implement the run builder.** For `180 piece`, assert `15`
      batches and totals `7500 g` flour, `3750 g` butter, `3600 g` water, plus a
      manual line with null total. Test invalid decimal, zero target, unsupported or
      incompatible target unit, and more than `1000` batches. Construct an
      in-memory `ProductionRun`; call no application use case or repository.

- [x] **2.9 Prove the final sample path and commit.** Load through injected
      `AssetBundle`, create review state, correct water to `g`, confirm values,
      verify, map, and calculate. Prove zero HTTP/persistence calls. Run:

  ```sh
  flutter pub get
  flutter gen-l10n
  flutter test test/championship/model test/championship/import \
    test/championship/sample
  flutter test test/championship/championship_boundary_test.dart
  flutter analyze
  very_good test --coverage --test-randomize-ordering-seed random
  lcov --summary coverage/lcov.info
  ```

  Require `100.0%` reached Dart lines. Commit:

  ```sh
  git commit -m "feat(championship): add verified recipe draft pipeline"
  ```

---

## Task 3: Add the guarded extraction endpoint

**Files:** create `package.json`, `api/extract-recipe.mjs`, schema, handler, and
Node tests; modify `merry.yaml`.

**Accepted requests:** one exact JSON object for text or one for image, with
`sourceKind`, nullable `text`, nullable `imageDataUrl`, and locale `ko` or `en`.
Return the version `1` draft on success. Return only stable safe error codes:
`method_not_allowed`, `invalid_content_type`, `invalid_request`,
`unsupported_source`, `source_too_large`, `service_unconfigured`,
`service_busy`, `service_timeout`, `invalid_model_output`, or `service_failure`.

- [x] **3.1 Create the dependency-free Node test surface.** Use ESM and
      `node --test api/lib/extract-recipe-handler_test.mjs`; add no runtime package.

- [x] **3.2 Write failing input-validation tests.** Inject provider fetch,
      environment, logger, and timeout. Cover method, content type, malformed/extra
      JSON, empty/over-limit text, unsupported/over-limit image, locale, missing
      key, origin mismatch, and `Cache-Control: no-store`.

- [x] **3.3 Implement local validation.** Count text with `[...text].length`.
      Validate an anchored image data URL, decode only its base64 payload, enforce
      the `3 MiB` decoded limit, and reject invalid requests before provider access.

- [x] **3.4 Define one strict JSON Schema.** Set
      `additionalProperties: false` on every object, require all keys, keep
      quantities nullable strings, and close confidence/behavior enums. The
      instruction must say: use null instead of guessing; copy evidence; report
      ambiguity; do not calculate, scale, convert, infer density, search, or generate
      a new recipe.

- [x] **3.5 Test and implement the provider request.** POST to Responses API with
      configured model, strict `text.format`, `store: false`, low reasoning effort,
      no tools/files/background/streaming, and either text or one high-detail image.
      Bound output tokens and abort at `25` seconds, including provider body consumption. Parse only `output_text` message content and revalidate it before returning. Never return the raw provider response.

- [x] **3.6 Test and implement safe failures and logs.** Map timeout, `429`,
      provider failure, missing/malformed output, and unexpected exceptions.
      Permit logs to contain only request id, status, latency, and error category.
      Prove logs contain no source, image data, ingredient names, or output.

- [x] **3.7 Add endpoint entrypoint and command.** Export the configured POST
      handler and add `merry api test`. Run:

  ```sh
  npm run test:api
  node --check api/extract-recipe.mjs
  node --check api/lib/recipe-draft-schema.mjs
  node --check api/lib/extract-recipe-handler.mjs
  ```

- [x] **3.8 Inspect and commit.** Search staged files for `sk-`, environment
      assignments, source text, and image data. Commit:

  ```sh
  git commit -m "feat(championship): add guarded recipe extraction endpoint"
  ```

---

## Task 4: Connect Flutter text and one-image import

**Files:** add `http` and `file_picker`; create request, client, HTTP client,
image-picker interface/adapter, and focused tests.

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

- [x] **4.1 Add only transport dependencies.** Add compatible pinned `http` and
      `file_picker` versions, run `flutter pub get`, and inspect native plugin
      changes. Do not add a provider SDK to Flutter.

- [x] **4.2 Test and implement request values.** Cover blank/over-limit text,
      exact limits, MIME validation, exact JSON keys, and base64 generation only at
      serialization. Preserve original text except for blank validation.

- [x] **4.3 Test and implement the HTTP client.** Inject `http.Client` and URI.
      Assert one JSON POST with no authorization header. Apply `27` second client
      timeout. Decode success through `ExtractedRecipeDraft.fromJson`, map stable
      endpoint errors, and never auto-retry.

- [x] **4.4 Test and implement the picker.** Request one in-memory custom file
      with `jpg`, `jpeg`, `png`, or `webp`. Never use a filesystem path. Reject
      absent bytes, multiple files, MIME/extension mismatch, unsupported extension,
      and over-limit data. Cancellation returns null.

- [x] **4.5 Verify web and normal mobile builds.** Run sequentially:

  ```sh
  flutter test test/championship/import test/championship/input
  flutter test test/championship/championship_boundary_test.dart
  flutter build web --release --target lib/main_championship.dart \
    --tree-shake-icons
  flutter build apk --debug --flavor development \
    --target lib/main_development.dart
  flutter build ios --simulator --debug --flavor development \
    --target lib/main_development.dart
  ```

- [x] **4.6 Inspect and commit.** Commit:

  ```sh
  git commit -m "feat(championship): connect text and image import"
  ```

---

## Task 5: Implement the evidence-based four-phase workflow

**Files:** create Cubit/state, Source, Review, Target, Result, privacy/review
widgets, tests, and localizations; modify app/page/entrypoint.

The Cubit owns source, request generation, extracted/review/verified drafts,
target strings, failures, and optional run. It owns no `BuildContext`,
controller, focus node, or localized string.

- [ ] **5.1 Write the failing Cubit suite.** Cover sample without HTTP; text and
      image loading/success/failure; image cancellation; stale response rejection;
      Reset invalidation; edit clearing confirmation; ambiguous review blocking;
      corrected review reaching Target; Back preservation; exact calculation
      reaching Result; target failures staying in Target; duplicate calculation
      suppression; Result Back; and zero state changes from responsive resizing.

- [ ] **5.2 Implement stale-response-safe orchestration.** Increment one request
      generation for submission and Reset. Ignore late completion after mismatch.
      Preserve source on retryable failure. Never retry silently. `calculate()` may
      call only `ChampionshipRunBuilder`, never extraction.

- [ ] **5.3 Add English and Korean copy.** Cover phases, sample/input/privacy,
      loading/failures, evidence/confidence/issues, confirmation, units/behavior,
      target, exact result, batches, warnings, reset, and production sheet. Privacy
      copy must say that PrepBook does not persist input, live input is sent to the
      configured provider, provider controls apply, and confidential content should
      use the sample. Do not claim zero provider retention. Run `flutter gen-l10n`.

- [ ] **5.4 Test and implement Source.** No login. Sample requires no consent or
      HTTP. Live input requires explicit consent. Blank text cannot submit. Image
      metadata is shown without rendering the source image. Loading prevents
      duplicates. Failure preserves input and offers Retry and Sample. Verify
      keyboard order and compact text scale `3.0`.

- [ ] **5.5 Test and implement Review.** Every field shows proposal, evidence,
      confidence, extraction issues, local issues, current value, edited state, and
      confirmation. Use stable path keys. Manual lines have no amount input. Units
      come from the explicit resolver plus unresolved state. Color is not the sole
      status indicator. Resize must preserve edits and confirmations.

- [ ] **5.6 Test and implement Target.** Show verified recipe/base yield. Start
      with empty amount and compatible unit. Calculate only on button press. Back
      returns to identical review state.

- [ ] **5.7 Test and implement Result.** Show exact-calculation boundary, recipe,
      target, batch plan, stored totals, stored per-batch values, manual lines, and
      domain warnings. Read names from `ingredientSnapshot`; do not recalculate in
      widgets.

- [ ] **5.8 Wire production dependencies.** Create HTTP client, import client,
      picker, sample loader, verifier, and run builder in
      `main_championship.dart`. Resolve endpoint from
      `AI_IMPORT_ENDPOINT`, defaulting to `/api/extract-recipe`. Root lifecycle owns
      and closes HTTP client. Do not initialize SQLite.

- [ ] **5.9 Add the real sample integration test.** Drive sample -> bulk confirm
      -> correct/confirm water -> confirm manual dusting flour -> Target -> `180
piece` -> exact calculation. Assert `15` batches and checked totals. Assert
      zero import-client calls.

- [ ] **5.10 Verify and commit.** Run:

  ```sh
  flutter pub get
  flutter gen-l10n
  flutter test test/championship/cubit test/championship/view \
    test/championship/integration
  flutter test test/championship/championship_boundary_test.dart
  flutter analyze
  dart run bloc_tools:bloc lint .
  very_good test --coverage --test-randomize-ordering-seed random
  lcov --summary coverage/lcov.info
  ```

  Run explicit-path `trunk fmt` and `trunk check`. Commit:

  ```sh
  git commit -m "feat(championship): add evidence-based demo workflow"
  ```

---

## Task 6: Reuse production-sheet export and configure deployment

**Files:** modify Result/app/page/entrypoint; create `vercel.json`,
`.vercelignore`, and production-sheet integration tests.

- [ ] **6.1 Write the failing callback test.** Define
      `OpenChampionshipProductionSheet(BuildContext, ProductionRun)`. Assert the
      Result action passes the identical in-memory run. Cancellation or callback
      failure must preserve Result and the run.

- [ ] **6.2 Wire the existing launcher.** Create the existing
      `ProductionSheetLauncher` at the composition root and pass one callback to
      Result. Do not modify builder, PDF renderer, production-sheet Cubit, domain,
      or shipping result UI.

- [ ] **6.3 Verify web export manually.** Build/serve web, complete sample,
      inspect batch and total views, invoke download/print preview, and cancel before
      system print. Confirm no Flutter exception, discarded run, or unexpected
      request.

- [ ] **6.4 Add Vercel configuration.** Use local prebuilt deployment. Configure
      championship Flutter build, `build/web` output, `30` second endpoint duration,
      and SPA rewrite excluding `/api/`. Exclude native builds, tests, coverage,
      docs, environment files, PEM, and local output without excluding source,
      assets, API, Flutter metadata, or deployment config.

- [ ] **6.5 Run regressions.** Run:

  ```sh
  flutter analyze
  dart run bloc_tools:bloc lint .
  npm run test:api
  very_good test --coverage --test-randomize-ordering-seed random
  flutter build web --release --target lib/main_championship.dart \
    --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe \
    --tree-shake-icons
  flutter build apk --debug --flavor development \
    --target lib/main_development.dart
  flutter build ios --simulator --debug --flavor development \
    --target lib/main_development.dart
  lcov --summary coverage/lcov.info
  ```

  Run native builds sequentially.

- [ ] **6.6 Inspect and commit.** Expect no domain/export-internal or normal
      entrypoint changes. Commit:

  ```sh
  git commit -m "feat(championship): reuse production sheet and deploy web demo"
  ```

---

## Task 7: Harden, document, deploy, and prepare submission

**Files:** update README, CLAUDE, design, and this plan; create
`docs/notes/2026-09-20-ai-championship-submission.md`; change copy only when
runtime evidence proves a defect.

- [ ] **7.1 Correct repository status.** Update README so production-sheet
      export is no longer described as unimplemented. Add a championship section
      explaining optional variant, offline normal flavors, live-provider boundary,
      sample fallback, entrypoint/build command, and design/plan links. Add one
      narrow scope exception to CLAUDE without replacing the approved source of
      truth.

- [ ] **7.2 Run one final local gate at one commit.** Run:

  ```sh
  flutter pub get
  flutter gen-l10n
  merry check
  merry coverage
  npm run test:api
  flutter build web --release --target lib/main_championship.dart \
    --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe \
    --tree-shake-icons
  flutter build apk --debug --flavor development \
    --target lib/main_development.dart
  flutter build ios --simulator --debug --flavor development \
    --target lib/main_development.dart
  lcov --summary coverage/lcov.info
  ```

  Record exact results, counts, coverage, output paths, and non-failing warnings.

- [ ] **7.3 Configure secrets outside the repository.** Set
      `OPENAI_API_KEY`, approved `OPENAI_MODEL`, and final `ALLOWED_ORIGIN`
      interactively without echoing the key. Configure and verify a Vercel WAF rate limit for `POST /api/extract-recipe`. Search tracked and untracked files for key patterns before deployment.

- [ ] **7.4 Deploy prebuilt output.** Run:

  ```sh
  vercel pull --yes --environment=production
  vercel build --prod
  vercel deploy --prebuilt --prod
  ```

  Record final URL. Verify root/nested routes without authentication and verify
  `/api/extract-recipe` reaches the function.

- [ ] **7.5 Perform public runtime acceptance.** With synthetic source, verify
      Chrome sample with endpoint unavailable, live text, live PNG, mobile width,
      Safari, forced busy/retry, ambiguity blocking, exact `180 piece` result,
      production-sheet views, download/print cancellation, Reset, reload, empty
      browser storage, secret-free requests, and source-free function logs. Keep
      screenshots/PDF outside the repository.

- [ ] **7.6 Write the submission note.** Include Service, Problem, Solution, AI
      use, Deterministic safety boundary, Tools used, Privacy boundary, Demo script,
      Deployment/judging availability, Existing-service disclosure, and Verification
      evidence. Distinguish runtime AI from AI-assisted development. State that AI
      creates a review draft only and existing exact code calculates every quantity.
      Keep demo script under `90` seconds.

- [ ] **7.7 Record execution evidence.** Only after public acceptance, mark the
      design `Implemented and publicly verified` and append final commit, toolchain,
      commands/results, tests, coverage, builds, URL, browser matrix, artifact
      directory, and any `[PARTIAL]` item with consequence.

- [ ] **7.8 Run repository hygiene review.** Run:

  ```sh
  git diff --check origin/main...HEAD
  git status --short
  git diff --stat origin/main...HEAD
  git diff origin/main...HEAD
  ```

  Confirm no key, `.env`, real recipe, user image, generated PDF, screenshot,
  database, persisted run, Flutter provider SDK, normal-entrypoint variant
  import, or unrelated refactor.

- [ ] **7.9 Commit verified documentation.** Commit:

  ```sh
  git commit -m "docs(championship): record verified competition submission"
  ```

  Do not open or merge a pull request without separate approval.

## Completion criteria

Implementation is complete only when all seven tasks are committed, the final
local gates pass at the same commit, normal Android and iOS development builds
still pass, the public URL supports both no-network sample and live extraction,
unresolved values block calculation, all production quantities come from the
existing exact engine, production-sheet export opens from the in-memory run,
browser storage and function logs contain no submitted source, and deployment
availability through 2026-10-17 is recorded.

Competition judging is not product-market validation. After the event, keep this
variant isolated until direct kitchen-user testing shows:

- at least five operators import their own recipes;
- at least three prefer guarded import to manual entry;
- review plus correction is materially faster than manual entry;
- ambiguous units are reliably blocked before calculation;
- at least one generated plan is used in real work.

If those conditions fail, remove the live endpoint and competition presentation
while retaining schema, fixture, mapper tests, and lessons. If they pass, write a
new product design before integrating import into the normal mobile workflow.
