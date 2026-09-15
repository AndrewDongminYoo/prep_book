# AI Championship Submission Note

## Status

Submission candidate evidence was collected on 2026-09-15 against the production application at commit `ca428e9566a5aa811d8e3755190c3ea33256301c`.
The core sample, live text, live image, review, and calculation paths passed in Chrome.
The remaining partial checks are Safari, direct browser-storage inspection, public production-sheet download and print cancellation, successful recovery after a forced rate limit, and production verification of the hardened Function route surface.

## Service

PrepBook AI Recipe Import is a no-login Flutter Web competition variant.
It converts one recipe text or image into a review draft and sends confirmed values to PrepBook's existing production calculator.

Public URL: <https://prep-book-fawn.vercel.app>

The normal iOS and Android application remains offline-first and does not import the competition variant.

## Problem

Small kitchens often receive recipes as messages, photographs, and printouts.
Manual entry is slow, but silent AI inference is unsafe when a quantity or unit is missing.

## Solution

The competition variant separates interpretation from calculation.
AI proposes a structured draft with evidence, confidence, and issues.
The operator must correct and confirm each value before calculation.
PrepBook then uses its existing exact arithmetic, batch planning, and production-sheet code.

## AI use

### Runtime AI

The serverless endpoint sends one text source or one reduced image to the configured OpenAI model through the Responses API.
The request uses a strict JSON Schema, `store: false`, no tools, and a bounded timeout.
The model can extract only a review draft.

### AI-assisted development

OpenAI Codex assisted implementation, tests, runtime acceptance, and documentation.
CodeRabbit provided automated pull-request review.
Runtime AI is separate from these development tools.

## Deterministic safety boundary

The model must not:

- Scale quantities.
- Convert units.
- Infer density.
- Invent missing values.
- Create the production result.

The application blocks unresolved or unconfirmed fields.
Only the existing `ProductionCalculator` creates totals and batch quantities.

## Tools used

- Flutter 3.47.4 and Dart 3.13.3 for the web and mobile application.
- Node.js 24.20.0 for the serverless endpoint tests.
- OpenAI Responses API for runtime extraction.
- Vercel Functions and Vercel WAF for hosting and rate limiting.
- GitHub Actions for reproducible production deployment.
- Flutter Test, Bloc lint, and Node's built-in test runner for automated checks.

## Privacy boundary

The public variant has no account and does not open the mobile SQLite database.
Sample mode uses a checked-in synthetic fixture and does not call the extraction endpoint.
Live input requires explicit consent before transmission.
Source text, reduced image bytes, drafts, and runs stay in memory in the application design.

The browser request metadata contained no `Authorization` header and no OpenAI key prefix.
The production environment contains encrypted or sensitive entries named `OPENAI_API_KEY`, `OPENAI_MODEL`, and `ALLOWED_ORIGIN`.
The verification did not read their values.
The endpoint returned `Cache-Control: no-store` for successful live requests.

A repository scan used a planted key-shaped negative control before the real scan.
The real tracked-and-untracked scan found zero OpenAI key-shaped values.
A production-log scan used planted source-shaped values before the real scan.
The real scan found zero matches for the submitted synthetic recipe text, ingredient phrases, image markers, or provider identifiers.

`[PARTIAL]` Reset and reload returned the application to Source, but the browser connection did not expose origin storage APIs for direct inspection.

## Cost protection

The production Vercel WAF has one active rule for `POST /api/extract-recipe`.
The rule limits each IP address to 5 requests per 60-second fixed window.
The sixth low-cost validation request returned HTTP `429` with `x-vercel-mitigated: deny`.
The draft was published, and Vercel reported no pending firewall changes.

## Deployment and judging availability

The [`deploy-championship` run](https://github.com/AndrewDongminYoo/prep_book/actions/runs/34857049687) succeeded on attempt 3 for `main@ca428e9566a5aa811d8e3755190c3ea33256301c`.
The `vercel pull`, `vercel build --prod`, and `vercel deploy --prebuilt --prod` steps all passed.
Vercel reported deployment `dpl_FTssHCs8kpiHDRs4YQX75LNxN27V` as `READY`, with the public alias assigned to production.

Acceptance found that Vercel also packaged three non-entrypoint files under `api/lib` as public Functions.
Direct probes returned HTTP `500` for the handler, schema, and test routes.
The current branch prefixes those support filenames with `_`, and a local `vercel build --prod` now outputs only `api/extract-recipe` as a Function.
Production must be redeployed and the three former routes must return `404` before this route-surface check passes.

The project must retain the public URL and required environment configuration through the judging end date of 2026-10-17.

## Existing-service disclosure

PrepBook's recipe domain, exact calculator, batch planner, and production-sheet export existed before this competition variant.
The competition work adds the isolated Flutter Web entrypoint, guarded AI extraction endpoint, strict draft schema, evidence-based human review, browser image reduction, and web deployment path.
The normal mobile product does not require the AI endpoint.

## Demo script

Target duration: 85 seconds.

1. `0–8s`: Open the public URL and state the boundary: "AI interprets the source. PrepBook calculates the production plan."
2. `8–18s`: Start the synthetic sample and explain that this path makes no extraction request.
3. `18–35s`: Show evidence, confidence, and the ambiguous water unit that blocks progress.
4. `35–48s`: Correct the water unit, confirm the remaining values, and continue.
5. `48–60s`: Enter `180 piece` and show `15` batches of `12 piece`.
6. `60–70s`: Open the batch and total production views.
7. `70–80s`: Return to Source and show text and image import with the privacy boundary.
8. `80–85s`: Close with the deterministic calculation and no-persistence boundary.

## Verification evidence

| Check                       | Result  | Evidence                                                                                                                                                                                                                                    |
| --------------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Public unauthenticated load | PASS    | Chrome 152 opened the production alias at a desktop viewport.                                                                                                                                                                               |
| Offline sample              | PASS    | The sample reached Review with zero `POST /api/extract-recipe` requests.                                                                                                                                                                    |
| Human review                | PASS    | Evidence, confidence, issues, and explicit confirmation controls were visible.                                                                                                                                                              |
| Ambiguity block             | PASS    | Continue stopped at the missing water unit until the value was corrected to `g`.                                                                                                                                                            |
| Exact target                | PASS    | `180 piece` produced 15 batches of 12 pieces.                                                                                                                                                                                               |
| Live text                   | PASS    | One browser request returned HTTP `200` and reached Review with three components.                                                                                                                                                           |
| Large live PNG              | PASS    | A 21,387,717-byte, 2400×1800 PNG became a 181,519-byte, 2048×1536 JPEG before upload. The request returned HTTP `200` and reached Review with three components.                                                                             |
| Browser request secrets     | PASS    | Observed text and image requests had no `Authorization` header and no OpenAI key prefix.                                                                                                                                                    |
| Endpoint cache policy       | PASS    | Successful text and image responses returned `Cache-Control: no-store`.                                                                                                                                                                     |
| WAF limit                   | PASS    | Five validation requests returned `400`. The next request returned `429`.                                                                                                                                                                   |
| Forced busy UI              | PARTIAL | The `429` preserved input and exposed Retry and Sample. A later Retry displayed a timeout while function logs showed a `200` response, but browser-control instability prevented request correlation and a verified successful UI recovery. |
| 390-pixel layout            | PASS    | Document and body width remained 390 pixels with no horizontal overflow. Primary controls remained usable.                                                                                                                                  |
| Reset and reload            | PARTIAL | Both returned to Source. Direct storage inspection was unavailable.                                                                                                                                                                         |
| Safari                      | PARTIAL | Safari 26.6.2 was installed, but WebDriver required the disabled `Allow remote automation` setting. The verification did not change that system setting.                                                                                    |
| Production sheet and PDF    | PARTIAL | This public pass did not complete preview, download-size, or print-cancellation checks.                                                                                                                                                     |
| Function route surface      | PARTIAL | Production returned `500` for three unintended `api/lib` routes. The local prebuilt output now contains only `api/extract-recipe`; a production redeploy and public `404` checks remain.                                                    |
| Production logs             | PARTIAL | The initial 45-minute window contained four `200` and fifteen intentional validation `400` responses, with no 5xx and zero source-shaped matches. Later route-surface probes produced three known diagnostic `500` responses.               |
| Local API tests             | PASS    | The route-hygiene test failed against the old filenames, then `npm run test:api` passed 56 tests after the rename.                                                                                                                          |
| Local code gate             | PASS    | `merry check` formatted 217 files with zero changes, found zero analyze and Bloc lint issues, and passed 1,016 Flutter tests.                                                                                                               |
| Coverage and release builds | PASS    | `merry coverage` passed 1,016 tests and reached 6,063 of 6,063 lines. Web release, Android development debug, and iOS development Simulator builds completed with their expected artifacts.                                                 |

## Remaining release-candidate checks

- Complete one desktop Safari pass without changing security settings outside an approved session.
- Inspect localStorage, sessionStorage, IndexedDB, and Cache Storage directly after Reset and reload.
- Verify public production-sheet batch and total views.
- Verify a non-zero PDF download and open then cancel the print dialog.
- Verify one forced-busy Retry reaches Review after the WAF window resets.
- Deploy the underscore-prefixed support modules and verify the three former public Function routes return `404`.
- Keep the public URL available through 2026-10-17.
