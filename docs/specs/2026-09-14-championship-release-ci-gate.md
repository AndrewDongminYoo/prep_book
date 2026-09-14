# Championship Release CI Gate Specification

**Status:** Approved for implementation through the requested PR loop.

## Problem

The normal pull request and `main` workflow validates Flutter formatting, analysis, Bloc lint, tests, coverage, semantic PR structure, and spelling.
It does not execute the championship API tests or compile the championship web release entrypoint.
The deployment workflow performs the release build only after `vercel pull`, so a Vercel project-settings failure skips both the build and deployment steps.
This leaves endpoint and release-compilation regressions outside the required pull request gate.

## Scope

- Run `npm run test:api` in the existing reusable Flutter build job.
- Run the championship release build command from `vercel.json` in the same job.
- Add a repository test that fails when the normal workflow omits either command or drifts from the Vercel build command.
- Preserve the existing Flutter, semantic pull request, and spell-check jobs.

## Non-goals

- Do not change Vercel credentials, project linkage, deployment behavior, or repository secrets.
- Do not configure WAF rules or perform public runtime acceptance.
- Do not add another CI runner, dependency, build script, or workflow.
- Do not change application behavior, UI, API schemas, or provider configuration.

## Design

The `build` job already calls the pinned Very Good Flutter reusable workflow.
That workflow exposes a multiline `setup` input and executes it after dependency resolution on the same Flutter runner.
The caller supplies the endpoint test and release build commands through this input, which avoids a second Flutter SDK setup and keeps the current coverage job intact.

The deployment configuration remains the source of truth for the web build command.
The deployment contract test reads `vercel.json`, extracts `buildCommand`, and verifies that the normal CI setup block contains the API test followed by that exact command.

## Acceptance criteria

- The normal pull request and `main` workflow runs `npm run test:api` before the championship release build.
- The workflow uses the exact `vercel.json` `buildCommand` value.
- Removing either command makes the deployment contract test fail.
- No additional job, dependency, or workflow is introduced.
- The API tests and championship web release build pass locally.
- Dart formatting, Flutter analysis, Bloc lint, the full optimized Flutter test suite, and workflow lint pass.
- The pull request's current-head CI checks pass.

## Visual approval

Visual approval is not applicable because this milestone changes only CI configuration and its contract test.
It does not change rendered application or document output.
