# AI Recipe Import Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish an isolated Flutter Web competition variant that turns one recipe text or image into an evidence-backed review draft, blocks unresolved ambiguity, and uses PrepBook's existing exact calculator and production-sheet export for every production quantity.

**Architecture:** All competition-only Flutter code lives under `lib/championship/` and starts from `lib/main_championship.dart`; the normal mobile entrypoints never import it. A single Vercel Function converts text or one image to a strict versioned JSON draft, while local verification maps only operator-confirmed decimal strings and units into existing domain objects. Calculation and PDF generation remain in the existing domain and export units, and no demo data is persisted.

**Tech Stack:** Dart 3.12, Flutter 3.44 or later, Material 3, `bloc` and `flutter_bloc`, PrepBook domain and export units, `http` 1.6.0, `file_picker` 11.0.3, Node.js Web APIs, OpenAI Responses API strict JSON Schema, Vercel Functions, Flutter and Node built-in tests.

**Spec:** `docs/specs/2026-09-13-ai-recipe-import-demo.md`

## Global Constraints

- Treat this work as an isolated competition variant, not a pivot of the normal PrepBook product.
- Keep `lib/main_development.dart`, `lib/main_staging.dart`, and `lib/main_production.dart` free of imports from `package:prep_book/championship/`.
- Put all variant Flutter implementation under `lib/championship/` and start it from `lib/main_championship.dart`.
- Support Flutter Web only for the competition entrypoint.
- Do not open SQLite, name a persistence repository, or write recipe, image, draft, run, or PDF data to application storage.
- Keep sample mode fully functional without an API key or network request.
- Accept only text up to `20,000` Unicode scalar values or one JPEG, PNG, or WebP image up to `8 MiB` decoded.
- Do not accept PDF, spreadsheet, document, HEIC, URL, camera, or multi-image input.
- Use AI only to produce the version `1` extraction draft defined by the spec.
- Use decimal strings in every extraction and review model; never introduce `double` or a JSON numeric quantity.
- Never infer a missing amount, missing unit, density, mass-to-volume conversion, or sub-recipe.
- Require explicit operator confirmation before any imported value enters the domain.
- Use `ProductionCalculator(maxPlannedBatches: 1000)` for every competition calculation.
- Keep the existing exact arithmetic, unit conversion, batch decomposition, warning, and PDF semantics unchanged.
- Build the production sheet from an in-memory `ProductionRun`; never save that run.
- Send provider requests with strict JSON Schema, no tools, low reasoning effort, and `store: false`.
- Keep `OPENAI_API_KEY` and `OPENAI_MODEL` server-side; neither may appear in Flutter assets, JavaScript bundles, logs, tests, or documentation examples.
- Do not log submitted recipe text, image bytes, extracted fields, or provider output.
- Use `Cache-Control: no-store` on the extraction response.
- Preserve the visitor's source and edits across retryable failures and width changes, but discard them on Reset and browser reload.
- Reuse the existing responsive width classes at `599`, `600`, `839`, and `840` logical pixels.
- Keep English and Korean UI usable at a text scale of `3.0`.
- Maintain `100` percent line coverage for reached Dart files.
- Resolve packages before formatting because this repository's formatter configuration comes from a resolved package.
- Run `trunk fmt` and `trunk check` only with explicit paths.
- Run at most one browser, simulator, emulator, Gradle, or Xcode job at a time.
- Keep the public deployment reachable without authentication through 2026-10-17.

## File Structure

Competition Flutter files:

| File | Responsibility |
| --- | --- |
| `lib/main_championship.dart` | Competition-only composition root. |
| `lib/championship/championship.dart` | Public competition barrel used by the entrypoint. |
| `lib/championship/model/extracted_recipe_draft.dart` | Strict version `1` decoded extraction evidence model. |
| `lib/championship/model/review_recipe_draft.dart` | Operator-editable immutable review state and confirmation flags. |
| `lib/championship/model/verified_recipe_draft.dart` | Fully confirmed values allowed to enter the domain. |
| `lib/championship/model/championship_recipe_bundle.dart` | One mapped recipe and its ingredient snapshot. |
| `lib/championship/import/recipe_import_request.dart` | Text and image request values with local size validation. |
| `lib/championship/import/recipe_import_client.dart` | Replaceable extraction transport interface. |
| `lib/championship/import/http_recipe_import_client.dart` | Same-origin HTTP implementation and public error mapping. |
| `lib/championship/import/unit_alias_resolver.dart` | Explicit source-unit alias table from the spec. |
| `lib/championship/import/recipe_draft_verifier.dart` | Confirmation and local consistency gate. |
| `lib/championship/import/championship_recipe_mapper.dart` | Verified draft to exact `Recipe`, `Ingredient`, and component values. |
| `lib/championship/import/championship_run_builder.dart` | Target validation, exact calculation, and in-memory run construction. |
| `lib/championship/input/recipe_image_picker.dart` | Narrow picker interface returning one in-memory supported image. |
| `lib/championship/input/file_picker_recipe_image_picker.dart` | `file_picker` implementation with MIME and decoded-size checks. |
| `lib/championship/sample/championship_sample.dart` | Checked-in sample source and draft loader. |
| `lib/championship/cubit/championship_demo_cubit.dart` | Source, extraction, review, target, calculation, reset, and stale-request coordination. |
| `lib/championship/cubit/championship_demo_state.dart` | Immutable four-phase page state. |
| `lib/championship/view/championship_app.dart` | Localized Material application shell. |
| `lib/championship/view/championship_demo_page.dart` | Responsive phase host and progress navigation. |
| `lib/championship/view/source_step.dart` | Sample, text, image, and privacy controls. |
| `lib/championship/view/review_step.dart` | Evidence, confidence, issues, editing, and confirmation. |
| `lib/championship/view/target_step.dart` | Target amount and compatible unit entry. |
| `lib/championship/view/result_step.dart` | Exact result, warnings, batches, reset, and production-sheet action. |

Serverless and deployment files:

| File | Responsibility |
| --- | --- |
| `api/extract-recipe.mjs` | Vercel `POST` entrypoint. |
| `api/lib/recipe-draft-schema.mjs` | Strict JSON Schema and extraction instructions. |
| `api/lib/extract-recipe-handler.mjs` | Input validation, provider request, output parsing, timeout, and safe errors. |
| `api/lib/extract-recipe-handler_test.mjs` | Dependency-injected endpoint contract tests. |
| `package.json` | ESM declaration and Node endpoint test command; no runtime dependency is required. |
| `vercel.json` | Local Flutter web build, static output, function duration, and SPA routing. |
| `.vercelignore` | Excludes native build trees, tests, coverage, and private development artifacts from deployment upload. |
| `web/` | Flutter-generated web host files, edited only for title, description, and theme metadata. |

Fixtures and tests mirror the competition responsibilities under
`test/championship/`.
The one public sample lives at
`assets/championship/sample_croissant_draft.json`; tests load that exact file
rather than maintaining a second copy.

---

### Task 1: Variant boundary, web target, and deterministic baseline

**Files:**

- Create: `test/championship/championship_boundary_test.dart`
- Create: `lib/championship/championship.dart`
- Create: `lib/championship/sample/championship_sample.dart`
- Create: `lib/championship/view/championship_app.dart`
- Create: `lib/championship/view/championship_demo_page.dart`
- Create: `lib/main_championship.dart`
- Create: `test/championship/sample/championship_sample_test.dart`
- Create: `test/championship/view/championship_demo_page_test.dart`
- Create through Flutter tooling: `web/favicon.png`
- Create through Flutter tooling: `web/icons/Icon-192.png`
- Create through Flutter tooling: `web/icons/Icon-512.png`
- Create through Flutter tooling: `web/icons/Icon-maskable-192.png`
- Create through Flutter tooling: `web/icons/Icon-maskable-512.png`
- Create through Flutter tooling: `web/index.html`
- Create through Flutter tooling: `web/manifest.json`
- Modify: `.metadata`
- Modify: `merry.yaml`

**Interfaces:**

- Consumes: Existing `Recipe`, `Ingredient`, `RecipeComponent`, `Quantity`, `ProductionCalculator`, `ProductionRun`, Material theme, localization delegates, and responsive width helpers.
- Produces: `ChampionshipSample.buildRun`, `ChampionshipApp`, and the runnable `lib/main_championship.dart` web entrypoint.

Define the temporary baseline interface exactly as follows; Task 2 keeps the
public `buildRun` behavior while replacing its direct fixture construction with
the final verified-draft pipeline:

```dart
final class ChampionshipSample {
  const ChampionshipSample();

  ProductionRun buildRun({
    required Quantity targetYield,
    required DateTime createdAt,
    required String runId,
  });
}
```

- [ ] **Step 1: Write the failing competition-boundary test**

Create `test/championship/championship_boundary_test.dart` with two independent
gates.
The first recursively scans these protected roots and rejects the literal
`package:prep_book/championship/`:

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

The second requires `lib/championship` to exist, scans every Dart source under
it, and allows only these URI prefixes:

```dart
const allowedCompetitionUriPrefixes = <String>[
  'dart:async',
  'dart:convert',
  'dart:typed_data',
  'package:bloc/',
  'package:file_picker/',
  'package:flutter/',
  'package:flutter_bloc/',
  'package:http/',
  'package:meta/',
  'package:prep_book/championship/',
  'package:prep_book/domain/',
  'package:prep_book/export/',
  'package:prep_book/l10n/',
  'package:prep_book/presentation/production_sheet/',
  'package:prep_book/presentation/responsive/',
];
```

Reject these raw substrings inside competition production sources:

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

Reuse the complete-directive and raw-denylist approach already used by
`test/presentation/presentation_boundary_test.dart`; do not weaken the existing
presentation guard.

- [ ] **Step 2: Run the boundary test and verify RED**

Run:

```sh
flutter test test/championship/championship_boundary_test.dart
```

Expect failure with `lib/championship does not exist, so nothing was checked.`

- [ ] **Step 3: Restore the Flutter web host files**

Run:

```sh
flutter create --platforms=web .
```

Inspect `.metadata` and every generated `web/` path.
Confirm that the command does not rewrite Android, iOS, macOS, Dart, test, or
product documentation files.
Set the page title and manifest name to `PrepBook AI` and the description to
`Verified recipe import and deterministic production scaling.`
Do not add a service worker customization or offline cache in this competition
slice.

- [ ] **Step 4: Write the failing sample calculation test**

Create `test/championship/sample/championship_sample_test.dart`.
Build the sample at a target of `180` pieces and assert:

```dart
expect(run.recipe.name, 'Croissant dough');
expect(run.targetYield, Quantity.parse('180', Unit.count('piece')));
expect(run.result.batchPlan.batchCount, 15);
expect(run.result.components[0].total!.displayed,
    Quantity.parse('7500', Unit.gram));
expect(run.result.components[1].total!.displayed,
    Quantity.parse('3750', Unit.gram));
expect(run.result.components[2].total!.displayed,
    Quantity.parse('3600', Unit.gram));
expect(run.result.components[3].total, isNull);
expect(run.ingredientSnapshot.values.map((value) => value.name),
    containsAll(<String>['Flour', 'Butter', 'Water', 'Dusting flour']));
```

- [ ] **Step 5: Run the sample test and verify RED**

Run:

```sh
flutter test test/championship/sample/championship_sample_test.dart
```

Expect a compile failure because `ChampionshipSample` does not exist.

- [ ] **Step 6: Implement the smallest exact sample run**

Create the competition barrel and sample factory.
Use a base yield of `24` pieces, maximum batch yield of `12` pieces, and these
components in order:

```dart
('Flour', '1000', Unit.gram, ScalingBehavior.proportional)
('Butter', '500', Unit.gram, ScalingBehavior.proportional)
('Water', '480', Unit.gram, ScalingBehavior.proportional)
('Dusting flour', null, null, ScalingBehavior.manual)
```

Use stable ids `championship-sample`, `ingredient-000` through
`ingredient-003`, and `component-000` through `component-003`.
Calculate with:

```dart
const ProductionCalculator(maxPlannedBatches: 1000)
```

Construct the returned `ProductionRun` from the exact passed `createdAt`,
`runId`, recipe, ingredient snapshot, target, and result.
Do not call an application use case or repository.

- [ ] **Step 7: Write the failing baseline page test**

Pump `ChampionshipApp` at `390` logical pixels.
Tap `Try the sample`, enter `180`, and tap `Calculate exactly`.
Assert the page shows:

```text
15 batches
Flour
7.5 kg
Butter
3.75 kg
Water
3.6 kg
Manual review
```

Resize to `900` logical pixels and assert the result remains visible and no new
run id is created.

- [ ] **Step 8: Implement the baseline page and entrypoint**

`ChampionshipApp` provides English and Korean delegates, Material 3, and one
`ChampionshipDemoPage`.
The baseline page holds only view state required to prove the vertical slice:
one sample button, one target text field, one calculate button, and one result
summary.
Keep `ChampionshipSample` and the clock/run-id callbacks injectable so the test
uses fixed values.

Create `lib/main_championship.dart` with no `bootstrap` call:

```dart
import 'package:flutter/widgets.dart';
import 'package:prep_book/championship/championship.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChampionshipApp(
      sample: const ChampionshipSample(),
      clock: DateTime.now,
      runId: () => 'championship-${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
}
```

The later tasks replace the time-based production callbacks at the composition
root with focused wrapper classes; do not put time reads in the domain mapper.

- [ ] **Step 9: Add explicit championship workflow commands**

Add these entries to `merry.yaml` without changing the existing defaults:

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

- [ ] **Step 10: Verify the baseline**

Run:

```sh
flutter pub get
flutter test test/championship/championship_boundary_test.dart test/championship/sample/championship_sample_test.dart test/championship/view/championship_demo_page_test.dart
flutter build web --release --target lib/main_championship.dart --tree-shake-icons
```

Expect all tests to pass and `build/web/index.html` to exist.
Open the build through a local HTTP server, complete the sample path, and confirm
DevTools shows no network request after the initial static assets load.

- [ ] **Step 11: Commit the deterministic baseline**

Stage only the Task 1 paths.
Inspect the generated web metadata and complete staged diff.
Commit with:

```sh
git commit -m "feat(championship): add deterministic web demo baseline"
```

### Task 2: Versioned extraction model, review gate, and domain mapping

**Files:**

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
- Modify: `lib/championship/sample/championship_sample.dart`
- Modify: `lib/championship/championship.dart`
- Create: `test/championship/model/extracted_recipe_draft_test.dart`
- Create: `test/championship/import/unit_alias_resolver_test.dart`
- Create: `test/championship/import/recipe_draft_verifier_test.dart`
- Create: `test/championship/import/championship_recipe_mapper_test.dart`
- Create: `test/championship/import/championship_run_builder_test.dart`
- Modify: `test/championship/sample/championship_sample_test.dart`

**Interfaces:**

- Consumes: Version `1` JSON from the spec and the existing domain constructors.
- Produces: Evidence records, review records, a verified draft, exact unit resolution, `ChampionshipRecipeBundle`, and `ChampionshipRunBuilder.build`.

Define these public types and signatures:

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

  final int schemaVersion;
  final RecipeImportSourceKind sourceKind;
  final ExtractedRecipe recipe;
  final List<ExtractedRecipeComponent> components;
}

final class ReviewRecipeDraft {
  factory ReviewRecipeDraft.fromExtracted(ExtractedRecipeDraft draft);

  final ReviewField<String> name;
  final ReviewQuantity baseYield;
  final ReviewQuantity? maxBatchYield;
  final List<ReviewField<String>> preparationNotes;
  final List<ReviewRecipeComponent> components;
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

final class ChampionshipRecipeBundle {
  const ChampionshipRecipeBundle({
    required this.recipe,
    required this.ingredients,
  });
  final Recipe recipe;
  final Map<String, Ingredient> ingredients;
}

final class ChampionshipRecipeMapper {
  const ChampionshipRecipeMapper({this.units = const UnitAliasResolver()});
  final UnitAliasResolver units;
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

- [ ] **Step 1: Add the exact sample extraction fixture**

Create `assets/championship/sample_croissant_draft.json` matching the spec's
version `1` contract.
Use:

- recipe name `Croissant dough`;
- base yield `24 piece`;
- maximum batch yield `12 piece`;
- flour `1000 g`, proportional;
- butter `500 g`, proportional;
- water `480` with a null unit and issue `The source does not state a unit.`;
- dusting flour with null amount and unit, manual;
- preparation note `Laminate cold; rest 20 minutes between folds.`

Set `sourceKind` to `sample`.
Add the JSON path to the existing `flutter.assets` list in `pubspec.yaml` and run
`flutter pub get`.

- [ ] **Step 2: Write failing strict decoder tests**

Load the committed JSON file and assert every value, evidence string,
confidence, issue, and component order.
Add separate tests that mutate the JSON and expect `FormatException` for:

- `schemaVersion: 2`;
- a numeric `480` instead of string `"480"`;
- absent `issues`;
- unknown confidence;
- unknown behavior;
- a manual component with a numeric amount;
- an additional unrecognized top-level property.

Run:

```sh
flutter test test/championship/model/extracted_recipe_draft_test.dart
```

Expect a compile failure because the decoder does not exist.

- [ ] **Step 3: Implement the immutable decoder and JSON round trip**

Use exhaustive local parsing helpers that require the exact property sets from
the spec.
Return unmodifiable issue, note, and component lists.
Keep decimal values as strings.
Do not trim or normalize `evidence`; it must preserve the provider response for
review.
`toJson` must produce a map that decodes back to an equal field-by-field value,
but value equality is required only in tests and need not be added to every
production model.

Run the decoder tests and expect GREEN.

- [ ] **Step 4: Write failing unit-resolution tests**

For every alias row in the spec, assert the exact `Unit` value.
Also assert:

```dart
expect(const UnitAliasResolver().resolve(' G '), Unit.gram);
expect(const UnitAliasResolver().resolve('unknown scoop'), isNull);
expect(const UnitAliasResolver().resolve('cup'), isNull);
expect(const UnitAliasResolver().resolve('oz'), isNull);
```

Run the focused test and expect a compile failure.

- [ ] **Step 5: Implement the explicit unit alias table**

Normalize by Unicode-aware trim and lowercase only.
Do not singularize arbitrary words, parse prefixes, or inspect ingredient names.
Map aliases exactly as listed in the spec.
Return newly created `Unit.count('piece')` and `Unit.namedYield('tray')` values
for their named-unit aliases; their structural equality makes those values safe.

Run the unit tests and expect GREEN.

- [ ] **Step 6: Write failing review and verification tests**

Create a review draft from the fixture.
Assert no extracted value starts confirmed.
Call the review helper that confirms all unambiguous locally valid fields and
assert the water unit stays unconfirmed.
Verify and expect `InvalidRecipeDraft` naming the water-unit path.
Set water to `g`, explicitly confirm it, verify again, and assert a
`ValidRecipeDraft` whose decimal strings and display order match the fixture.

Add failures for:

- blank recipe name;
- zero and negative base yield;
- unsupported base unit;
- maximum batch yield incompatible with the base yield;
- empty component list;
- blank component name;
- unconfirmed behavior;
- non-manual null amount;
- manual numeric amount;
- unsupported component unit;
- any extraction issue on an unconfirmed field.

- [ ] **Step 7: Implement review records and the verification gate**

`ReviewField<T>` stores `proposedValue`, current `value`, evidence, confidence,
extraction issues, local issues, and `isConfirmed`.
Editing a field sets `isConfirmed` to `false` and recalculates local issues.
The bulk-confirm action confirms only non-null, locally valid fields with no
extraction issue.

`RecipeDraftVerifier.verify` walks fields in UI order and returns all issues in
that same order.
It returns `ValidRecipeDraft` only when every condition in the spec's review
gate passes.
No verifier method constructs a domain object.

Run the verifier tests and expect GREEN.

- [ ] **Step 8: Write failing mapper and run-builder tests**

Map the corrected valid fixture at `DateTime.utc(2026, 9, 13, 5)`.
Assert:

```dart
expect(bundle.recipe.id, 'championship-recipe');
expect(bundle.recipe.revision, 1);
expect(bundle.recipe.baseYield, Quantity.parse('24', Unit.count('piece')));
expect(bundle.recipe.maxBatchYield,
    Quantity.parse('12', Unit.count('piece')));
expect(bundle.recipe.components.map((value) => value.id), <String>[
  'component-000',
  'component-001',
  'component-002',
  'component-003',
]);
expect(bundle.ingredients.keys, <String>[
  'ingredient-000',
  'ingredient-001',
  'ingredient-002',
  'ingredient-003',
]);
```

Build a run for `180 piece` and repeat the independently checked batch and total
assertions from Task 1.
Assert an unknown target unit, incompatible target, zero target, and more than
`1000` planned batches return the existing domain failures without translation
inside the mapper.

- [ ] **Step 9: Implement exact mapping and calculation**

Normalize ingredient identity by first occurrence of case-insensitive trimmed
name, so repeated `Sugar` lines share one ingredient but keep separate component
ids.
Create ids from deterministic zero-padded order; never accept an id from JSON.
Use `Quantity.parse`, `ScalingBehavior`, and existing constructors.
Map `fixedOnce` from `fixed_once` and the remaining behaviors by exact enum
name.

`ChampionshipRunBuilder` resolves the target unit with the same alias resolver,
maps the verified draft, calls its injected calculator, and constructs an
in-memory `ProductionRun` with:

```dart
dependencySnapshot: const {},
overrides: const {},
acknowledgedWarnings: const {},
```

Pass the mapped ingredient map as `ingredientSnapshot`.

- [ ] **Step 10: Route the sample through the final draft path**

Change `ChampionshipSample.buildRun` to load/decode the committed fixture, apply
one explicit sample correction (`Water` unit becomes `g`), confirm the review
draft, verify it, and call `ChampionshipRunBuilder`.
The sample may not maintain a second direct `Recipe` definition after this step.

Run all Task 2 tests plus Task 1 sample and page tests.
Expect the same visible and numeric result as before.

- [ ] **Step 11: Verify boundaries, formatting, and coverage**

Run:

```sh
flutter pub get
flutter gen-l10n
flutter test test/championship/model test/championship/import test/championship/sample
flutter test test/championship/championship_boundary_test.dart
flutter analyze
very_good test --coverage --test-randomize-ordering-seed random
```

Confirm reached Dart lines remain at `100.0%`.

- [ ] **Step 12: Commit the verified-draft core**

Stage only the Task 2 paths and regenerated lockfile.
Inspect the sample JSON and mapping tests in the staged diff.
Commit with:

```sh
git commit -m "feat(championship): add verified recipe draft mapping"
```

### Task 3: Guarded serverless extraction endpoint

**Files:**

- Create: `package.json`
- Create: `api/extract-recipe.mjs`
- Create: `api/lib/recipe-draft-schema.mjs`
- Create: `api/lib/extract-recipe-handler.mjs`
- Create: `api/lib/extract-recipe-handler_test.mjs`
- Create: `vercel.json`
- Create: `.vercelignore`
- Modify: `merry.yaml`

**Interfaces:**

- Consumes: One JSON request containing `{sourceKind, text, imageDataUrl, locale}` and server environment variables.
- Produces: `POST /api/extract-recipe`, strict version `1` JSON, stable public error bodies, and a dependency-injected handler factory.

Use these server interfaces:

```js
export function createExtractRecipeHandler({
  fetchImpl = fetch,
  apiKey = process.env.OPENAI_API_KEY,
  model = process.env.OPENAI_MODEL || 'gpt-5.6-luna',
  allowedOrigin = process.env.ALLOWED_ORIGIN || '',
  logger = console,
  timeoutMs = 25_000,
} = {})

export const POST = createExtractRecipeHandler();
```

The success body is the extraction draft itself.
Every failure body is:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "The submitted recipe could not be processed."
  }
}
```

Use only these public codes:

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

- [ ] **Step 1: Add the Node test surface**

Create `package.json`:

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

No npm runtime dependency is required; use the built-in Fetch, AbortController,
Request, Response, and test APIs.

- [ ] **Step 2: Write failing request-validation tests**

Use `node:test` and `node:assert/strict`.
Inject a fake `fetchImpl` that fails the test when validation should stop before
provider access.
Cover:

- GET returns `405` and `method_not_allowed`;
- non-JSON content type returns `415`;
- malformed JSON returns `400`;
- unknown source kind returns `400`;
- empty text returns `400`;
- text at `20,001` Unicode scalar values returns `413`;
- unsupported image MIME returns `415`;
- image above `8 * 1024 * 1024` decoded bytes returns `413`;
- absent API key returns `503`;
- mismatched configured origin returns `403` with `invalid_request`;
- every response carries `Cache-Control: no-store`.

Run `npm run test:api` and expect a module-not-found failure.

- [ ] **Step 3: Implement exact request parsing and validation**

Accept exactly one of these request shapes:

```js
{
  sourceKind: 'text',
  text: '...',
  imageDataUrl: null,
  locale: 'ko'
}
```

```js
{
  sourceKind: 'image',
  text: null,
  imageDataUrl: 'data:image/png;base64,...',
  locale: 'en'
}
```

Reject additional top-level properties.
Count text with `[...text].length`.
Validate the image data URL with an anchored expression, decode only its base64
payload with `Buffer.from(payload, 'base64')`, and compare the decoded byte
length to `8 MiB`.
Accept only locale `ko` or `en`.
Compare `Origin` only when `allowedOrigin` is non-empty; allow no-origin requests
for focused tests and command-line smoke checks.

Run validation tests and expect GREEN.

- [ ] **Step 4: Define the strict JSON Schema without duplicated field rules**

In `api/lib/recipe-draft-schema.mjs`, create helpers for nullable strings,
confidence, issues, evidence fields, quantities, and components.
Every object must set `additionalProperties: false` and list every property in
`required`.
The root must set:

```js
export const recipeDraftSchema = {
  type: 'object',
  additionalProperties: false,
  required: ['schemaVersion', 'sourceKind', 'recipe', 'components'],
  properties: {
    schemaVersion: { const: 1 },
    sourceKind: { enum: ['text', 'image'] },
    recipe: recipeSchema,
    components: {
      type: 'array',
      minItems: 1,
      maxItems: 100,
      items: componentSchema,
    },
  },
};
```

For amount and unit fields, `value` is `{type: ['string', 'null']}`.
For name and note fields, use the same nullable shape and let local verification
reject required nulls.
For behavior, allow the four spec values plus null.
Keep issue items non-empty strings and limit arrays to `20` entries.

Export one `extractionInstructions` string that states every AI responsibility
and prohibition from the spec, including `Use null instead of guessing.` and
`Do not calculate a production target.`

- [ ] **Step 5: Write failing provider-request tests**

Inject a provider fake that records URL, headers, and decoded body, then returns
one Responses API message with an `output_text` content item containing the
sample JSON.
Assert the request:

```js
assert.equal(url, 'https://api.openai.com/v1/responses');
assert.equal(body.model, 'gpt-5.6-luna');
assert.equal(body.store, false);
assert.deepEqual(body.reasoning, { effort: 'low' });
assert.equal(body.tools, undefined);
assert.equal(body.text.format.type, 'json_schema');
assert.equal(body.text.format.name, 'prepbook_recipe_draft');
assert.equal(body.text.format.strict, true);
assert.deepEqual(body.text.format.schema, recipeDraftSchema);
```

For text, assert one `input_text` source item.
For image, assert one `input_image` item whose `image_url` is the submitted data
URL and whose detail is `high`.
Assert the bearer header uses only the injected fake key.

- [ ] **Step 6: Implement the provider call and output parser**

Create one AbortController per invocation and clear its timer in `finally`.
Send the developer instruction and one user message through the Responses API.
Do not use background mode, streaming, tools, files, or provider storage.

Extract text only by walking:

```js
response.output
  -> item.type === 'message'
  -> item.content
  -> content.type === 'output_text'
  -> content.text
```

Join multiple output-text parts in order, parse JSON, and validate it against the
same structural expectations before returning it.
At minimum, re-check version, root property set, source kind, field object
property sets, nullable-string quantities, confidence values, issue arrays, and
component behavior.
Never return the raw provider object.

- [ ] **Step 7: Write and implement safe failure mapping**

Test and map:

- AbortError to `504 service_timeout`;
- provider `429` to `503 service_busy`;
- provider non-OK response to `502 service_failure`;
- absent output text, invalid JSON, or invalid contract to
  `502 invalid_model_output`;
- unexpected exceptions to `500 service_failure`.

Inject a logger fake and assert every call contains only:

```js
{
  requestId,
  status,
  latencyMs,
  errorCategory
}
```

Assert serialized log arguments never contain the submitted text, data URL,
fixture ingredient names, or provider output.

- [ ] **Step 8: Add the Vercel entrypoint and deployment configuration**

Create `api/extract-recipe.mjs`:

```js
import { createExtractRecipeHandler } from './lib/extract-recipe-handler.mjs';

export const POST = createExtractRecipeHandler();
```

Create `vercel.json`:

```json
{
  "$schema": "https://openapi.vercel.sh/vercel.json",
  "buildCommand": "flutter build web --release --target lib/main_championship.dart --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe --tree-shake-icons",
  "outputDirectory": "build/web",
  "functions": {
    "api/extract-recipe.mjs": {
      "maxDuration": 30
    }
  },
  "rewrites": [
    {
      "source": "/((?!api/).*)",
      "destination": "/index.html"
    }
  ]
}
```

Create `.vercelignore` containing:

```text
.git
.dart_tool
.idea
.vscode
android
ios
macos
test
coverage
docs
build
*.pem
.env*
```

Do not exclude `lib`, `web`, `assets`, `api`, `pubspec.yaml`, `pubspec.lock`,
`analysis_options.yaml`, `l10n.yaml`, `package.json`, or `vercel.json`.

- [ ] **Step 9: Add API commands and run the complete endpoint gate**

Add to `merry.yaml`:

```yaml
api:
  test:
    (description): Runs the competition extraction endpoint contract suite.
    (scripts): npm run test:api
```

Run:

```sh
npm run test:api
node --check api/extract-recipe.mjs
node --check api/lib/recipe-draft-schema.mjs
node --check api/lib/extract-recipe-handler.mjs
```

Expect all commands to exit `0`.

- [ ] **Step 10: Commit the guarded endpoint**

Stage only the Task 3 files.
Search the staged diff for `sk-`, `OPENAI_API_KEY=`, fixture source text inside
logs, and raw image payloads; expect no match.
Commit with:

```sh
git commit -m "feat(championship): add guarded recipe extraction endpoint"
```

### Task 4: Flutter transport and single-image input

**Files:**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Create: `lib/championship/import/recipe_import_request.dart`
- Create: `lib/championship/import/recipe_import_client.dart`
- Create: `lib/championship/import/http_recipe_import_client.dart`
- Create: `lib/championship/input/recipe_image_picker.dart`
- Create: `lib/championship/input/file_picker_recipe_image_picker.dart`
- Modify: `lib/championship/championship.dart`
- Create: `test/championship/import/recipe_import_request_test.dart`
- Create: `test/championship/import/http_recipe_import_client_test.dart`
- Create: `test/championship/input/file_picker_recipe_image_picker_test.dart`
- Modify: `test/championship/championship_boundary_test.dart`

**Interfaces:**

- Consumes: Endpoint JSON, `http.Client`, and `file_picker` bytes.
- Produces: Validated text/image requests, `RecipeImportClient`, public client failures, and `RecipeImagePicker`.

Use these signatures:

```dart
sealed class RecipeImportRequest {
  const RecipeImportRequest();
  Map<String, Object?> toJson(String locale);
}

final class TextRecipeImportRequest extends RecipeImportRequest {
  factory TextRecipeImportRequest(String text);
  final String text;
}

final class ImageRecipeImportRequest extends RecipeImportRequest {
  factory ImageRecipeImportRequest({
    required String filename,
    required String mediaType,
    required Uint8List bytes,
  });
  final String filename;
  final String mediaType;
  final Uint8List bytes;
}

abstract interface class RecipeImportClient {
  Future<ExtractedRecipeDraft> extract(
    RecipeImportRequest request, {
    required String locale,
  });
}

enum RecipeImportFailureCode {
  invalidRequest,
  sourceTooLarge,
  serviceUnconfigured,
  serviceBusy,
  serviceTimeout,
  invalidModelOutput,
  serviceFailure,
}

final class RecipeImportFailure implements Exception {
  const RecipeImportFailure(this.code);
  final RecipeImportFailureCode code;
}

final class HttpRecipeImportClient implements RecipeImportClient {
  HttpRecipeImportClient({
    required http.Client client,
    required Uri endpoint,
    this.timeout = const Duration(seconds: 27),
  });
}

final class SelectedRecipeImage {
  const SelectedRecipeImage({
    required this.filename,
    required this.mediaType,
    required this.bytes,
  });
}

abstract interface class RecipeImagePicker {
  Future<SelectedRecipeImage?> pick();
}
```

- [ ] **Step 1: Add pinned transport and picker dependencies**

Add:

```yaml
dependencies:
  file_picker: ^11.0.3
  http: ^1.6.0
```

Run `flutter pub get` and inspect native plugin resolution.
Do not add an OpenAI provider SDK to Flutter.

- [ ] **Step 2: Write failing request-value tests**

Assert:

- text trims only for emptiness checks but preserves submitted content;
- empty text fails;
- exactly `20,000` Unicode scalar values succeeds;
- `20,001` fails;
- JPEG, PNG, and WebP images at exactly `8 MiB` succeed;
- one byte above the limit fails;
- unsupported MIME fails;
- text JSON contains text and null image;
- image JSON contains a correctly prefixed data URL and null text;
- decimal or ingredient semantics are not inspected at this boundary.

Run the test and expect a compile failure.

- [ ] **Step 3: Implement the request values**

Throw `ArgumentError` for programmer construction errors.
Use `base64Encode(bytes)` only inside `toJson`, so state and tests hold bytes,
not a second long-lived encoded copy.
Return exact endpoint keys from the spec.

Run request tests and expect GREEN.

- [ ] **Step 4: Write failing HTTP client tests**

Inject a mocktail `http.Client`.
Assert one POST to the injected URI with JSON content type, no authorization
header, no cache header, and the exact locale.
Return the sample JSON and assert it decodes.

Cover public endpoint codes, malformed success JSON, non-JSON response, socket
or client exception, and the client-side timeout.
Assert the client never retries automatically; retry belongs to the Cubit after
the visitor acts.

- [ ] **Step 5: Implement the HTTP client**

Encode with `jsonEncode`, call the injected client, and apply the `27` second
client timeout, two seconds longer than the server abort.
On `200`, require a JSON object and decode through
`ExtractedRecipeDraft.fromJson`.
Map endpoint error codes exhaustively to `RecipeImportFailureCode`; map unknown
or malformed errors to `serviceFailure`.
Do not expose provider messages to the UI.

Run the client tests and expect GREEN.

- [ ] **Step 6: Write failing image-picker adapter tests**

Wrap `FilePicker.platform` behind an injected narrow function so tests do not
open a real chooser.
Cover:

- cancellation returns null;
- one PNG with bytes returns `SelectedRecipeImage`;
- absent bytes fails as invalid request;
- multiple returned files use none and fail rather than silently selecting the
  first;
- extension and MIME disagreement fails;
- unsupported extension fails;
- over-limit bytes fail locally.

- [ ] **Step 7: Implement the one-file picker**

Call:

```dart
pickFiles(
  type: FileType.custom,
  allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
  allowMultiple: false,
  withData: true,
)
```

Derive MIME only from the normalized extension using the fixed map:

```dart
jpg, jpeg -> image/jpeg
png       -> image/png
webp      -> image/webp
```

Never use a filesystem path.
Keep only the filename, MIME, and bytes.

- [ ] **Step 8: Verify boundary and native compatibility**

Run:

```sh
flutter test test/championship/import/recipe_import_request_test.dart test/championship/import/http_recipe_import_client_test.dart test/championship/input/file_picker_recipe_image_picker_test.dart
flutter test test/championship/championship_boundary_test.dart
flutter build web --release --target lib/main_championship.dart --tree-shake-icons
flutter build apk --debug --flavor development --target lib/main_development.dart
flutter build ios --simulator --debug --flavor development --target lib/main_development.dart
```

Run the Android and iOS builds sequentially after checking system load.
Expect the existing normal entrypoint to compile with the added plugin and no
code import from the competition unit.

- [ ] **Step 9: Commit transport and picker integration**

Stage only Task 4 paths.
Inspect `pubspec.lock` and generated native plugin changes, if any.
Commit with:

```sh
git commit -m "feat(championship): connect text and image import"
```

### Task 5: Evidence-based review workflow and responsive page

**Files:**

- Create: `lib/championship/cubit/championship_demo_state.dart`
- Create: `lib/championship/cubit/championship_demo_cubit.dart`
- Create: `lib/championship/view/source_step.dart`
- Create: `lib/championship/view/review_step.dart`
- Create: `lib/championship/view/target_step.dart`
- Create: `lib/championship/view/widgets/review_field_card.dart`
- Create: `lib/championship/view/widgets/privacy_notice.dart`
- Modify: `lib/championship/view/championship_app.dart`
- Modify: `lib/championship/view/championship_demo_page.dart`
- Modify: `lib/main_championship.dart`
- Modify: `lib/l10n/arb/app_en.arb`
- Modify: `lib/l10n/arb/app_ko.arb`
- Create: `test/championship/cubit/championship_demo_cubit_test.dart`
- Create: `test/championship/view/source_step_test.dart`
- Create: `test/championship/view/review_step_test.dart`
- Create: `test/championship/view/championship_demo_page_test.dart`

**Interfaces:**

- Consumes: `RecipeImportClient`, `RecipeImagePicker`, sample fixture, verifier,
  and immutable review models.
- Produces: One four-phase Cubit and accessible localized source/review/target
  UI whose state survives responsive branch changes.

Define state and commands:

```dart
enum ChampionshipDemoPhase { source, review, target, result }
enum ChampionshipImportStatus { idle, loading, failed }

final class ChampionshipDemoState {
  const ChampionshipDemoState({
    this.phase = ChampionshipDemoPhase.source,
    this.importStatus = ChampionshipImportStatus.idle,
    this.sourceText = '',
    this.selectedImage,
    this.reviewDraft,
    this.verificationIssues = const [],
    this.targetAmount = '',
    this.targetUnit = '',
    this.run,
    this.failureCode,
    this.requestGeneration = 0,
  });
}

final class ChampionshipDemoCubit extends Cubit<ChampionshipDemoState> {
  ChampionshipDemoCubit({
    required RecipeImportClient importClient,
    required RecipeImagePicker imagePicker,
    required ChampionshipSample sample,
    required RecipeDraftVerifier verifier,
    required ChampionshipRunBuilder runBuilder,
    required DateTime Function() clock,
    required String Function() runId,
  });

  Future<void> loadSample();
  void sourceTextChanged(String value);
  Future<void> submitText({required String locale});
  Future<void> pickAndSubmitImage({required String locale});
  void reviewFieldChanged(RecipeDraftPath path, String? value);
  void reviewFieldConfirmationChanged(RecipeDraftPath path, bool confirmed);
  void confirmAllUnambiguous();
  void continueFromReview();
  void targetChanged({required String amount, required String unit});
  void calculate();
  void back();
  void reset();
}
```

Task 6 implements the final `calculate` result transition; in this task it
verifies the review and advances to Target without yet opening PDF controls.

- [ ] **Step 1: Write failing Cubit state-machine tests**

Use fakes for every dependency and fixed clock/run-id callbacks.
Cover:

- initial source phase;
- sample reaches review without calling import client;
- valid text emits loading then review;
- image cancellation keeps source phase;
- supported image emits loading then review;
- endpoint failure preserves source and exposes retryable code;
- a second submission increments `requestGeneration` and a later completion
  from the first request is ignored;
- reset increments generation, clears source/image/review/target/result, and
  ignores an in-flight completion;
- editing clears confirmation for that field;
- bulk confirm leaves ambiguous water unresolved;
- Continue from Review stays put and emits ordered issues while water is
  unresolved;
- correcting and confirming water advances to Target;
- Back preserves edits;
- width changes require no Cubit command and therefore cannot change state.

Run and expect a compile failure.

- [ ] **Step 2: Implement the immutable state and Cubit through Target**

Use one monotonically increasing integer generation.
Capture it before each awaited extraction and compare it after completion.
Do not attempt to cancel `http.Client`; stale-result rejection is sufficient
for this single request flow.

The Cubit owns no `BuildContext`, controller, focus node, or localized string.
It stores only public failure codes and structured issues.
`continueFromReview` calls the verifier once and stores the returned ordered
issues or verified draft.
Keep the verified draft in state separately from the editable review draft once
Target is reached.

Run Cubit tests and expect GREEN.

- [ ] **Step 3: Add the exact localization surface**

Add English and Korean values, descriptions, and ICU placeholders for these
keys:

```text
championshipTitle
championshipTagline
championshipStepSource
championshipStepReview
championshipStepTarget
championshipStepResult
championshipTrySample
championshipPasteRecipe
championshipRecipeTextLabel
championshipRecipeTextHint
championshipExtractText
championshipChooseImage
championshipSelectedImage
championshipPrivacyTitle
championshipPrivacyBody
championshipPrivacyConsent
championshipExtractionInProgress
championshipExtractionFailed
championshipRetry
championshipUseSampleInstead
championshipEvidence
championshipConfidence
championshipConfidenceHigh
championshipConfidenceMedium
championshipConfidenceLow
championshipIssues
championshipProposedValue
championshipConfirmedValue
championshipConfirm
championshipConfirmAllUnambiguous
championshipNeedsReview
championshipRecipeName
championshipBaseYield
championshipMaximumBatchYield
championshipComponent
championshipAmount
championshipUnit
championshipBehavior
championshipBehaviorProportional
championshipBehaviorPerBatch
championshipBehaviorFixedOnce
championshipBehaviorManual
championshipPreparationNotes
championshipContinueToTarget
championshipTargetAmount
championshipTargetUnit
championshipCalculateExactly
championshipBack
championshipReset
```

The privacy body must say that PrepBook does not persist the source, that live
input is sent to the configured AI provider, that provider controls apply, and
that confidential or personal content should use the sample instead.
Do not claim zero provider retention.
Run `flutter gen-l10n`.

- [ ] **Step 4: Write failing source-step widget tests**

Pump compact and expanded widths with a real Cubit and fakes.
Assert:

- privacy consent is required before live text or image submission;
- sample is available without consent;
- text submit is disabled for blank input;
- selected image metadata is shown without rendering the full source image;
- loading disables duplicate submissions but Reset remains available;
- failure shows Retry and Sample actions;
- keyboard Tab order reaches sample, text, consent, extract, and image controls;
- text scale `3.0` at `390` pixels has no overflow.

- [ ] **Step 5: Implement the source phase**

Use a multiline `TextField`, labeled Material buttons, one consent checkbox, and
one non-modal failure panel.
The source phase may show either text or selected image metadata, never both as
active source.
Selecting text clears image state; selecting an image clears text only after a
successful selection.
Do not auto-submit on selection.

- [ ] **Step 6: Write failing review-step widget tests**

Pump the uncorrected sample review and assert:

- each field shows proposal, evidence, confidence, and issues;
- water has no selected unit and has a visible blocking issue;
- `Confirm all unambiguous` confirms flour and butter but not water;
- Continue focuses or scrolls to water and remains on Review;
- editing water to `g` clears its confirmation;
- confirming water and manual dusting allows Target;
- manual line renders no amount input;
- compact uses one column;
- expanded places evidence beside edit controls when large-text fallback allows;
- resize compact -> expanded -> compact preserves exact edits and confirmations;
- text scale `3.0` has no overflow.

- [ ] **Step 7: Implement the review phase**

Give every field a stable `ValueKey` from `RecipeDraftPath`.
Keep text controllers inside stateful field widgets and synchronize them from
immutable state without overwriting active edits.
Use dropdowns only for the explicit supported unit aliases and four behaviors;
include an `Unresolved` null state.

Show AI confidence visually and in semantics, but do not use color alone.
Show `Edited` when current value differs from the proposal.
Render extraction issues and local issues separately.

- [ ] **Step 8: Write and implement the Target phase**

Tests must assert the verified recipe name and base yield are visible, target
amount begins empty, target unit begins with the verified base-yield unit, and
Back returns to the same review state.

The target phase accepts only a decimal string and a unit from the explicit
alias resolver.
It does not calculate on each keystroke.
The Calculate button calls the Cubit once; Task 6 supplies the completed result
behavior.

- [ ] **Step 9: Wire production dependencies at the competition entrypoint**

Create one `http.Client`, one `HttpRecipeImportClient`, and one
`FilePickerRecipeImagePicker` at `main_championship.dart`.
Resolve the endpoint with:

```dart
Uri.base.resolve(
  const String.fromEnvironment(
    'AI_IMPORT_ENDPOINT',
    defaultValue: '/api/extract-recipe',
  ),
)
```

Pass production instances to `ChampionshipApp`, which creates the Cubit above
`LayoutBuilder`.
Close the HTTP client from an app-owned lifecycle object when the root widget is
disposed.
Do not initialize SQLite or call `bootstrap`.

- [ ] **Step 10: Run focused and static gates**

Run:

```sh
flutter pub get
flutter gen-l10n
flutter test test/championship/cubit/championship_demo_cubit_test.dart test/championship/view/source_step_test.dart test/championship/view/review_step_test.dart test/championship/view/championship_demo_page_test.dart
flutter test test/championship/championship_boundary_test.dart
flutter analyze
dart run bloc_tools:bloc lint .
```

Run explicit-path formatting and Trunk checks over changed Dart, ARB, YAML, and
Markdown paths.
Expect every command to pass.

- [ ] **Step 11: Commit the review workflow**

Stage only Task 5 files and generated lock changes already owned by the branch.
Inspect Korean and English copy side by side.
Commit with:

```sh
git commit -m "feat(championship): add evidence-based review workflow"
```

### Task 6: Exact result and existing production-sheet integration

**Files:**

- Create: `lib/championship/view/result_step.dart`
- Modify: `lib/championship/cubit/championship_demo_cubit.dart`
- Modify: `lib/championship/cubit/championship_demo_state.dart`
- Modify: `lib/championship/view/championship_demo_page.dart`
- Modify: `lib/championship/view/target_step.dart`
- Modify: `lib/championship/view/championship_app.dart`
- Modify: `lib/main_championship.dart`
- Modify: `lib/l10n/arb/app_en.arb`
- Modify: `lib/l10n/arb/app_ko.arb`
- Create: `test/championship/view/result_step_test.dart`
- Modify: `test/championship/cubit/championship_demo_cubit_test.dart`
- Modify: `test/championship/view/championship_demo_page_test.dart`
- Create: `test/championship/integration/sample_vertical_slice_test.dart`

**Interfaces:**

- Consumes: Verified draft, target strings, `ChampionshipRunBuilder`, existing
  `ProductionRun`, and existing `ProductionSheetLauncher`.
- Produces: Completed Result phase, exact batch presentation, domain-error
  correction path, and one production-sheet callback.

`ChampionshipApp` and the page receive this callback rather than subclassing the
existing final launcher:

```dart
typedef OpenChampionshipProductionSheet = Future<void> Function(
  BuildContext context,
  ProductionRun run,
);
```

The production composition root supplies:

```dart
final productionSheet = const ProductionSheetLauncher(
  platform: PrintingProductionSheetPlatform(),
);

openProductionSheet: (context, run) =>
    productionSheet.open(context, run: run),
```

- [ ] **Step 1: Extend Cubit tests for exact calculation**

From a verified sample review, set target `180 piece`, call `calculate`, and
assert one Result state containing the run with:

```dart
expect(run.result.batchPlan.batchCount, 15);
expect(run.result.batchPlan.fullBatchCount, 15);
expect(run.result.batchPlan.remainderYield, isNull);
expect(run.result.components[0].total!.displayed,
    Quantity.parse('7500', Unit.gram));
expect(run.result.components[0].perBatch, hasLength(15));
expect(run.result.components[0].perBatch.first!.displayed,
    Quantity.parse('500', Unit.gram));
```

Assert repeated `calculate` taps while calculating produce one builder call.
Assert unknown unit, incompatible unit, invalid decimal, zero target, and batch
limit keep the visitor in Target with a stable local failure code and preserve
all review data.
Assert correcting the target then succeeds.
Assert Back from Result returns to Target and Reset clears the run.

- [ ] **Step 2: Implement the calculation transition**

Add `ChampionshipCalculationStatus { idle, calculating, failed }` and a stable
UI failure enum for invalid decimal, unsupported unit, incompatible unit, target
not positive, target too large, and unexpected domain failure.

Call the synchronous run builder in a guarded Cubit method.
Do not invoke the extraction client.
Do not store or serialize the run.
Keep domain error matching exhaustive for existing relevant error types and map
all other `DomainError` values to the safe unexpected-domain category.

Run Cubit tests and expect GREEN.

- [ ] **Step 3: Add localized result copy**

Add English and Korean values for:

```text
championshipExactCalculation
championshipAiDidNotCalculate
championshipBatchCount
championshipBatch
championshipBatchRange
championshipTotals
championshipPerBatch
championshipManualReview
championshipOutstandingWarnings
championshipOpenProductionSheet
championshipCalculationFailed
championshipTargetInvalid
championshipTargetUnitUnsupported
championshipTargetUnitIncompatible
championshipTargetTooLarge
championshipStartOver
```

Use ICU placeholders for batch numbers, ranges, quantities, and warning counts.
Run `flutter gen-l10n`.

- [ ] **Step 4: Write failing result widget tests**

Pump a fixed run and assert:

- `Exact PrepBook calculation` is visible;
- `AI did not calculate these quantities` is visible;
- recipe, target, and `15 batches` are visible;
- totals use existing `readableQuantity` formatting;
- each component shows total and per-batch amounts;
- the manual line shows Manual review, not zero;
- domain warnings remain visible;
- production-sheet action passes the identical `ProductionRun` instance;
- compact text scale `3.0` has no overflow;
- expanded layout shows summary and component details in separate panes without
  creating a second run.

- [ ] **Step 5: Implement the exact result phase**

Read names from `run.ingredientSnapshot`; fall back to the component id only
when a snapshot entry is absent.
Group consecutive identical per-batch displayed values using the same visual
rule as the existing production result screen, but do not recalculate totals or
copy private presentation helpers.
The displayed total must be the stored `ScaledQuantity.total.displayed`.

Use expansion controls for batch details at compact width and visible secondary
pane details at expanded width.
Use labeled controls and semantic quantities.

- [ ] **Step 6: Wire the existing production-sheet feature**

Pass one callback from `main_championship.dart` through `ChampionshipApp` and
`ChampionshipDemoPage` to `ResultStep`.
Do not modify `ProductionSheetBuilder`, `ProductionSheetPdfRenderer`,
`ProductionSheetCubit`, or the shipping production-result screen.

The callback receives the exact in-memory run and opens the existing production
sheet.
On browser share/download/print cancellation, keep the Result phase and run.
On PDF generation failure, let the existing production-sheet page show its own
retryable failure.

- [ ] **Step 7: Add the complete vertical-slice integration test**

In `test/championship/integration/sample_vertical_slice_test.dart`, use the real
sample loader, decoder, review draft, verifier, mapper, calculator, and run
builder.
Use only fakes for HTTP, image picker, clock, run id, and production-sheet open.

Drive:

```text
Try sample
-> Confirm all unambiguous
-> set Water unit to g
-> confirm Water
-> confirm manual Dusting flour
-> Continue
-> target 180 piece
-> Calculate exactly
-> Open production sheet
```

Assert the final callback receives the run with the independently checked
values.
Assert the import client recorded zero calls.

- [ ] **Step 8: Verify existing export code on web**

Run focused tests, then:

```sh
flutter build web --release --target lib/main_championship.dart --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe --tree-shake-icons
python3 -m http.server 8080 --directory build/web
```

In one Chrome session, complete sample calculation, open the production-sheet
page, switch batch/total organization, and invoke download or print preview.
Cancel before submitting an operating-system print job.
Confirm no Flutter exception and no unexpected network call.
Stop the server and browser job.

- [ ] **Step 9: Run regression and coverage gates**

Run:

```sh
flutter analyze
dart run bloc_tools:bloc lint .
npm run test:api
very_good test --coverage --test-randomize-ordering-seed random
lcov --summary coverage/lcov.info
```

Expect `100.0%` reached Dart line coverage and no existing mobile/export test
regression.

- [ ] **Step 10: Commit exact result and export reuse**

Stage only Task 6 files.
Inspect the diff for any change under `lib/domain/`, `lib/export/`, or the
shipping production-result feature; expect none.
Commit with:

```sh
git commit -m "feat(championship): calculate and export verified runs"
```

### Task 7: Deployment hardening, documentation, and submission verification

**Files:**

- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `docs/specs/2026-09-13-ai-recipe-import-demo.md`
- Modify: `docs/plans/2026-09-13-ai-recipe-import-demo.md`
- Create: `docs/notes/2026-09-20-ai-championship-submission.md`
- Modify if runtime evidence requires copy-only corrections: `lib/l10n/arb/app_en.arb`
- Modify if runtime evidence requires copy-only corrections: `lib/l10n/arb/app_ko.arb`

**Interfaces:**

- Consumes: Final local gates, production Vercel environment, public deployment,
  and runtime evidence.
- Produces: Accurate repository status, explicit scope exception, stable public
  URL, submission narrative, demo script, and recorded verification evidence.

- [ ] **Step 1: Correct the existing README status before adding variant copy**

Update the pre-release status so it no longer says export is unimplemented.
State that domain, persistence, application, responsive presentation, and
production-sheet export are implemented, while migration and release packaging
remain pending where still true at execution time.
Verify each status statement against the tree before writing it.

- [ ] **Step 2: Document the competition variant without redefining the product**

Add a README section named `AI Championship variant` containing:

- the one-sentence guarded-import description;
- the competition entrypoint and web build command;
- the fact that normal mobile flavors remain offline and backend-free;
- the fact that live source is sent to the configured AI provider only after
  explicit action;
- the sample's network-independent behavior;
- links to the new spec and plan.

In `CLAUDE.md`, add a narrow exception immediately after the scope fence:

```text
The only approved exception is the isolated 2026 AI Championship variant in
`lib/championship/`, governed by
`docs/specs/2026-09-13-ai-recipe-import-demo.md`. It must not be imported by the
normal product entrypoints or used to widen first-release scope by analogy.
```

Do not alter the approved source-of-truth designation.

- [ ] **Step 3: Run the final local quality gate at one commit**

Run exactly:

```sh
flutter pub get
flutter gen-l10n
merry check
merry coverage
npm run test:api
flutter build web --release --target lib/main_championship.dart --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe --tree-shake-icons
flutter build apk --debug --flavor development --target lib/main_development.dart
flutter build ios --simulator --debug --flavor development --target lib/main_development.dart
lcov --summary coverage/lcov.info
```

Run native builds sequentially.
Record test counts, reached lines, build output paths, and any non-failing tool
warnings in the plan's Execution Evidence section.
Do not describe a warning as fixed unless its owning change is in this branch.

- [ ] **Step 4: Configure production secrets without writing them to the repo**

Using the linked Vercel project, add:

```text
OPENAI_API_KEY=<secret value entered interactively>
OPENAI_MODEL=gpt-5.6-luna
ALLOWED_ORIGIN=<the final production origin>
```

Use Vercel environment commands or dashboard secret input that does not echo the
key into shell history.
After configuration, run a repository search for `sk-` and the actual origin's
secret-bearing environment output; expect no secret in tracked or untracked
files.

- [ ] **Step 5: Build and deploy the prebuilt production output**

Run:

```sh
vercel pull --yes --environment=production
vercel build --prod
vercel deploy --prebuilt --prod
```

Capture the production URL from the deploy command.
Open the URL in a fresh unauthenticated browser and confirm the root route and a
manually entered nested route both serve the Flutter app while
`POST /api/extract-recipe` reaches the function.

Do not switch to a remote Flutter build merely to simplify deployment; the plan
pins local Flutter and uploads Vercel's prebuilt output.

- [ ] **Step 6: Perform public runtime acceptance**

Use rights-cleared synthetic source only.
Verify and record:

1. Desktop Chrome fresh profile, sample flow with the endpoint deliberately
   unavailable.
2. Desktop Chrome live text extraction.
3. Desktop Chrome live PNG extraction under `8 MiB`.
4. Mobile-width Chrome at `390` logical pixels.
5. Desktop Safari.
6. Forced provider `429` or endpoint fake producing the public busy error, then
   successful Retry.
7. Water unit ambiguity blocks calculation until corrected and confirmed.
8. Target `180 piece` produces `15` batches and the checked totals.
9. Production-sheet batch and total previews render.
10. Download or print UI opens and cancels without discarding the run.
11. Reset clears source, draft, target, and result.
12. Reload does not restore any prior source.
13. Browser storage inspection contains no recipe source, extraction response,
    API key, or run.
14. Browser network inspection contains no unexpected third-party request and
    no API key.
15. Vercel function logs contain no recipe text, ingredient name, image data,
    or model output.

Save screenshots and exported synthetic PDF outside the repository in one
recorded temporary directory.

- [ ] **Step 7: Create the exact submission note**

Create `docs/notes/2026-09-20-ai-championship-submission.md` with these sections
and fill them from verified evidence, not aspiration:

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

The `AI use` section must name the configured model and say it extracts a
review draft only.
The `Deterministic safety boundary` section must name the existing exact
calculator and say every scaled quantity comes from it.
The `Tools used` section must distinguish runtime AI from AI-assisted
development tools.
The `Existing-service disclosure` section must accurately describe PrepBook's
pre-existing mobile core and the newly added competition variant so the
organizer can be notified separately as required.
The Demo script must fit in `90` seconds and use the synthetic sample.

- [ ] **Step 8: Update design status and execution evidence**

After every gate and public acceptance item passes, change the spec status to
`Implemented and publicly verified on 2026-09-20`.
Add `## Execution Evidence` to this plan with:

- final commit SHA;
- exact commands and exit results;
- Flutter and Node versions;
- Flutter and API test counts;
- coverage summary;
- Android and iOS build results;
- public production URL;
- browser/device matrix;
- temporary artifact directory;
- any partial verification clearly marked `[PARTIAL]` with its consequence.

Do not mark the design implemented before these facts exist.

- [ ] **Step 9: Review final scope and repository hygiene**

Run:

```sh
git diff --check origin/main...HEAD
git status --short
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
```

Confirm the branch contains no:

- API key or `.env` file;
- real or proprietary recipe;
- uploaded user image;
- generated PDF;
- screenshot;
- Vercel project metadata with a secret;
- database file;
- production-run history;
- provider SDK inside Flutter;
- normal entrypoint import of the competition unit;
- unrelated architecture refactor.

- [ ] **Step 10: Commit verified documentation**

Stage only Task 7 documentation and any copy corrections proven by runtime
acceptance.
Inspect the staged diff and submission claims.
Commit with:

```sh
git commit -m "docs(championship): record verified competition submission"
```

Do not open or merge a pull request as part of this plan unless the operator
separately approves that repository action.

## Completion Criteria

Implementation is complete only when all seven tasks are committed, the final
local gates pass at the same commit, the normal Android and iOS development
entrypoints still build, the no-network sample and live text/image paths both
work from the public URL, unresolved values demonstrably block calculation, the
existing exact engine produces every production number, the existing
production-sheet feature opens from the in-memory run, public logs and browser
storage contain no submitted source, and the deployment is committed to remain
available through 2026-10-17.

The deadline cut line is strict:

1. Tasks 1 and 2 establish the shippable deterministic sample.
2. Tasks 3 through 5 add the judged AI workflow.
3. Task 6 proves existing calculator and PDF reuse.
4. Task 7 hardens and submits.

If schedule pressure appears, remove live image input before weakening review,
calculation boundaries, sample reliability, privacy copy, or verification.
Do not replace strict schema or explicit confirmation with a faster free-form
chat path.
