# Championship Release CI Gate Implementation Plan

**Goal:** Make endpoint tests and the championship web release compilation required parts of the normal pull request and `main` CI gate.

**Architecture:** Reuse the existing Very Good Flutter runner through its `setup` input, and keep `vercel.json` as the release build command source of truth.

## Success criteria

1. The normal build job executes the API tests and release build → verify with the deployment contract test and the two real commands.
2. The CI command cannot drift from Vercel configuration → verify that the contract test derives the expected command from `vercel.json`.
3. Existing quality gates remain intact → verify the complete local gate and hosted CI.
4. CI cost does not gain a second Flutter runner → verify that `.github/workflows/main.yaml` adds only the reusable workflow's `setup` input.

## Task 1: Add the failing workflow contract

**Files:**

- Modify: `test/championship/deployment/vercel_config_test.dart`

Add a test that reads `.github/workflows/main.yaml` and `vercel.json`.
Extract the reusable workflow's multiline `setup` block and require exactly these commands in order:

```plaintext
npm run test:api
<vercel.json buildCommand>
```

Run the named test before changing the workflow and record the missing-setup failure.

```sh
flutter test test/championship/deployment/vercel_config_test.dart --plain-name "normal CI gates the endpoint and championship release build"
```

## Task 2: Wire the existing CI runner

**Files:**

- Modify: `.github/workflows/main.yaml`

Add a multiline `setup` value to the existing `build` job.
Run the API tests first and the exact Vercel release build command second.
Do not add a job, dependency, or workflow.

Rerun the named test, then execute the two gated commands locally.

```sh
npm run test:api
flutter build web --release --target lib/main_championship.dart --dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe --tree-shake-icons
```

## Task 3: Verify and review

**Files:**

- Verify: `.github/workflows/main.yaml`
- Verify: `test/championship/deployment/vercel_config_test.dart`
- Verify: `docs/specs/2026-09-14-championship-release-ci-gate.md`
- Verify: `docs/plans/2026-09-14-championship-release-ci-gate.md`

Run the scoped and repository gates.

```sh
dart format --output=none --set-exit-if-changed test/championship/deployment/vercel_config_test.dart
flutter analyze
dart run bloc_tools:bloc lint .
very_good test -j 4 --optimization --coverage --min-coverage 100 --report-on "lib" --show-uncovered --test-randomize-ordering-seed random
trunk check .github/workflows/main.yaml docs/specs/2026-09-14-championship-release-ci-gate.md docs/plans/2026-09-14-championship-release-ci-gate.md
```

Perform one inline adversarial review because the expected diff is small and does not touch application code.
Check command ordering, source-of-truth drift, workflow syntax, cost impact, and whether a failure blocks the existing build job.

## Task 4: Publish the pull request

Use concern-based semantic commits, push the branch, and open a pull request against `main`.
Observe current-head CI and hosted review within the public-repository budget.
Stop at merge readiness because this PR loop does not include merge authority.
