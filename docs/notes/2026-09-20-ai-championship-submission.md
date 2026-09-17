# AI Championship Submission Note

<!-- cspell:ignore extendedvaluekey udhj Rasd -->

## Status

The current production baseline is `main@51a85e29efce5b8ef97bbbcbf4f883f8190c1f12`.
The [main CI run](https://github.com/AndrewDongminYoo/prep_book/actions/runs/35132393769) and [production deployment run](https://github.com/AndrewDongminYoo/prep_book/actions/runs/35132393107) passed at that commit.
On 2026-09-17 KST, Chrome completed the public Sample to Result flow, rendered both production-sheet previews, and downloaded a readable PDF.
The observed sample flow made no extraction API or `unpkg.com` request.
The earlier live text and image checks remain recorded below with their original deployment context.
The remaining partial checks are Safari, an isolated browser-storage before-and-after comparison, direct print cancellation, and successful recovery after a forced rate limit.

The operator confirmed that Championship participation registration is complete on 2026-09-17.
The Wanted `My Project` page showed no registered task and offered `Register Project` on 2026-09-17 KST.
The task submission is `[INCOMPLETE]` at that check.
The [official FAQ](https://static.wanted.co.kr/ai-championship/2026/landing.html) sets the participation-registration deadline at 2026-09-18 23:59:59 KST and the task-submission deadline at 2026-09-20 23:59:59 KST.
The FAQ says that a saved draft does not count as final submission and that submitted tasks can be edited until the task-submission deadline.
The live submission form requires a representative image, title, one-line problem, AI use and result within 500 characters, at least one tool or stack tag, service URL, and at least one 16:9 screenshot.
It showed no required video field.

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

`[PARTIAL]` Reset and reload returned the application to Source.
Direct inspection found two localStorage keys, no IndexedDB databases, and no Cache Storage entries; sessionStorage changed from three keys to zero between observations.
One localStorage key was Vercel toolbar metadata, while `extendedvaluekey` had no match in repository source or generated output.
A fresh isolated browser context was unavailable, so the pass could not establish a clean before-and-after storage baseline or attribute the unknown key to the application.

## Cost protection

The production Vercel WAF has one active rule for `POST /api/extract-recipe`.
The rule limits each IP address to 5 requests per 60-second fixed window.
The sixth low-cost validation request returned HTTP `429` with `x-vercel-mitigated: deny`.
The active rule was re-read after the hardened deployment, and Vercel reported no draft or pending firewall changes.

## Deployment and judging availability

The [latest `deploy-championship` run](https://github.com/AndrewDongminYoo/prep_book/actions/runs/35132393107) succeeded for `main@51a85e29efce5b8ef97bbbcbf4f883f8190c1f12`.
The Vercel pull, build, and deploy steps passed, and the run assigned the production alias <https://prep-book-fawn.vercel.app>.
The [same-commit main CI run](https://github.com/AndrewDongminYoo/prep_book/actions/runs/35132393769) also passed.

Earlier acceptance found that Vercel also packaged three non-entrypoint files under `api/lib` as public Functions.
The hardened deployment prefixes those support filenames with `_`, and Vercel now reports only `api/extract-recipe` as a Function.
Public probes returned HTTP `404` for the three former routes and their three underscore-prefixed equivalents.
The intended endpoint returned HTTP `405`, `Allow: POST`, and `Cache-Control: no-store` for a deliberate `GET` probe.
The 2026-09-15 hardened deployment log query contained that one metadata-only `405` entry and no unexpected 5xx response.

The project must retain the public URL and required environment configuration through the judging end date of 2026-10-17.

## Existing-service disclosure

PrepBook's recipe domain, exact calculator, batch planner, and production-sheet export existed before this competition variant.
The competition work adds the isolated Flutter Web entrypoint, guarded AI extraction endpoint, strict draft schema, evidence-based human review, browser image reduction, and web deployment path.
The normal mobile product does not require the AI endpoint.
The operator confirmed that the mobile product was not a public service before the competition variant.
The [official FAQ](https://static.wanted.co.kr/ai-championship/2026/landing.html) requests a separate operating-period and revenue notice for a result that was already in service.

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

## Submission form draft

Title: `PrepBook AI Recipe Import`.

Problem: 사진·메시지로 받은 레시피를 옮겨 적는 과정은 느리고, 누락된 수량이나 단위를 AI가 임의로 채우면 생산 계획이 틀릴 수 있습니다.

AI use and result: OpenAI Responses API는 레시피 텍스트·이미지에서 원문 근거, 신뢰도, 확인할 문제를 포함한 구조화 초안만 만듭니다.
누락된 단위를 추측하지 않고 사용자가 검토·수정·확인하도록 합니다.
확인된 값은 기존 ProductionCalculator가 정확하게 계산합니다.
샘플에서는 180 piece를 12 piece씩 15배치로 계산하고 생산 지시서 PDF를 생성했습니다.
개발에는 OpenAI Codex를 사용했으며, 이는 런타임 AI와 구분됩니다.

The form offers `Vercel` as an accurate stack tag.
It does not offer separate `OpenAI Responses API`, `OpenAI Codex`, or `Flutter` tags, so the text names the AI tools.
Service URL: <https://prep-book-fawn.vercel.app>.

The following actual production screenshots are outside the repository under `~/Downloads/prepbook-championship-submission/`:

- Representative image: `cover-review-square-2026-09-17.jpg` (600×600).
- Screenshots: `source-16x9-2026-09-17.jpg`, `review-16x9-2026-09-17.jpg`, and `result-16x9-2026-09-17.jpg` (each 1600×900).

The form has not been filled, saved, or submitted.

## 2026-09-17 production recheck

| Check                     | Result     | Evidence                                                                                                                                                                                                                                                       |
| ------------------------- | ---------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Deployment and CI         | PASS       | Production alias and both GitHub Actions runs point to `main@51a85e29efce5b8ef97bbbcbf4f883f8190c1f12`.                                                                                                                                                        |
| Current checks            | PASS       | Main CI passed 1,118 Flutter tests, 56 API tests, analysis, and Bloc lint. A local `merry coverage` run passed 1,118 tests and measured 6,625 of 6,625 reached lines. The deploy build passed.                                                                 |
| Sample to Result          | PASS       | Chrome loaded the sample draft, corrected Water to `g`, confirmed the values, and displayed `180 piece` as 15 batches of 12 pieces.                                                                                                                            |
| Production-sheet previews | PASS       | Batch preview showed 12 pieces per batch. Total preview showed Flour 7,500 g, Butter 3,750 g, and Water 3,600 g.                                                                                                                                               |
| PDF dependency            | PASS       | Chrome requested `pdf.min.mjs` and `pdf.worker.min.mjs` from the public origin. Chrome recorded `200` for `pdf.min.mjs`, and direct HTTP requests returned `200` for both modules. The observed sample flow made zero `unpkg.com` and extraction API requests. |
| Share PDF                 | PASS       | Share downloaded `production-sheet-Croissant-dough-20260916T232651Z.pdf` outside the repository. It was 13,273 bytes, had one page, and passed `qpdf --check`.                                                                                                 |
| Return to Result          | PASS       | Back preserved the `180 piece` result and its 15 batches of 12 pieces.                                                                                                                                                                                         |
| Browser isolation         | PARTIAL    | The pass used a new Chrome tab. It did not establish a clean incognito profile or a storage baseline.                                                                                                                                                          |
| Task submission           | INCOMPLETE | Participation registration is operator-confirmed. The Wanted `My Project` page showed no registered task. The required image files and form copy are prepared outside the form.                                                                                |

Coverage is limited to measured Dart lines. It does not establish execution of excluded web or platform files.

## 2026-09-15 verification evidence

| Check                       | Result  | Evidence                                                                                                                                                                                                                                                                                                                                             |
| --------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Public unauthenticated load | PASS    | Chrome 152 opened the production alias at a desktop viewport.                                                                                                                                                                                                                                                                                        |
| Offline sample              | PASS    | The sample reached Review with zero `POST /api/extract-recipe` requests.                                                                                                                                                                                                                                                                             |
| Human review                | PASS    | Evidence, confidence, issues, and explicit confirmation controls were visible.                                                                                                                                                                                                                                                                       |
| Ambiguity block             | PASS    | Continue stopped at the missing water unit until the value was corrected to `g`.                                                                                                                                                                                                                                                                     |
| Exact target                | PASS    | `180 piece` produced 15 batches of 12 pieces.                                                                                                                                                                                                                                                                                                        |
| Live text                   | PASS    | One browser request returned HTTP `200` and reached Review with three components.                                                                                                                                                                                                                                                                    |
| Large live PNG              | PASS    | A 21,387,717-byte, 2400×1800 PNG became a 181,519-byte, 2048×1536 JPEG before upload. The request returned HTTP `200` and reached Review with three components.                                                                                                                                                                                      |
| Browser request secrets     | PASS    | Observed text and image requests had no `Authorization` header and no OpenAI key prefix.                                                                                                                                                                                                                                                             |
| Endpoint cache policy       | PASS    | Successful text and image responses returned `Cache-Control: no-store`.                                                                                                                                                                                                                                                                              |
| WAF limit                   | PASS    | Five validation requests returned `400`. The next request returned `429`.                                                                                                                                                                                                                                                                            |
| Forced busy UI              | PARTIAL | The `429` preserved input and exposed Retry and Sample. A later Retry displayed a timeout while function logs showed a `200` response, but browser-control instability prevented request correlation and a verified successful UI recovery.                                                                                                          |
| 390-pixel layout            | PASS    | Document and body width remained 390 pixels with no horizontal overflow. Primary controls remained usable.                                                                                                                                                                                                                                           |
| Reset and reload            | PARTIAL | Both returned to Source. Storage inspection found two localStorage keys, zero IndexedDB databases, zero Cache Storage entries, and conflicting sessionStorage counts; an isolated before-and-after baseline was unavailable.                                                                                                                         |
| Safari                      | PARTIAL | Safari 26.6.2 was installed, but WebDriver required the disabled `Allow remote automation` setting. The verification did not change that system setting.                                                                                                                                                                                             |
| Production-sheet views      | PASS    | The public batch preview displayed batches 1–15. The total preview displayed Flour 7500 g, Butter 3750 g, and Water 3600 g.                                                                                                                                                                                                                          |
| Preview network dependency  | FAIL    | Production commit `8a8e6c8` served both bundled modules, but `printing` received the bare `assets/js/` specifier and failed before it requested them. The corrected local release build used `./assets/js/`, received both modules from `127.0.0.1`, made no `unpkg.com` request, and rendered the preview. Production verification remains pending. |
| PDF download                | PASS    | The production Share action created `production-sheet-Croissant-dough-20260915T064613Z.pdf`. The file was 13,214 bytes, contained one A4 page, and passed `qpdf --check` with no syntax or stream encoding errors.                                                                                                                                   |
| Print dialog                | PARTIAL | Print was selected and Escape returned to the production sheet, but the macOS dialog was outside the browser capture and was not directly observed.                                                                                                                                                                                                  |
| Function route surface      | PASS    | Deployment `dpl_HmV9d59Giu5udhjGFtERasd9rY3w` contains only `api/extract-recipe`. The three former support routes and their underscore-prefixed equivalents returned `404`; deliberate `GET` returned `405`.                                                                                                                                         |
| Production logs             | PASS    | The initial 45-minute live-input window had no 5xx and zero source-shaped matches. The hardened deployment query contained one deliberate metadata-only `405` entry and no unexpected 5xx response.                                                                                                                                                  |
| Local API tests             | PASS    | The route-hygiene test failed against the old filenames, then `npm run test:api` passed 56 tests after the rename.                                                                                                                                                                                                                                   |
| Local code gate             | PASS    | The current branch's `merry check` formatted 218 files with zero changes, found zero analyze and Bloc lint issues, and passed 1,017 Flutter tests.                                                                                                                                                                                                   |
| Coverage and release builds | PASS    | The current branch's `merry coverage` passed 1,017 tests and reached 6,063 of 6,063 lines. Its championship web release build included the three vendored files with their recorded hashes. Earlier Android development debug and iOS development Simulator builds completed with their expected artifacts.                                          |

## Remaining release-candidate checks

- Complete one desktop Safari pass without changing security settings outside an approved session.
- Repeat the storage check in a fresh isolated browser context and compare all four storage surfaces before the Sample flow and after Reset and reload.
- Directly observe the print dialog opening and then cancel it.
- Verify one forced-busy Retry reaches Review after the WAF window resets.
- Keep the public URL available through 2026-10-17.
