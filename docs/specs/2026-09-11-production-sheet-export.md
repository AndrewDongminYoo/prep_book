# Production Sheet Export Design

## Status

Implemented locally on 2026-09-11.
Automated verification passed, and the Android Emulator covered every reachable committed-fixture scenario.
The oversized-section repeated-header case is verified by renderer tests and visual PDF inspection, but the committed runtime fixtures do not produce that state.
The development flavor also built, installed, launched, and rendered on iPhone and iPad Simulators without signing or CocoaPods errors.
The iOS interaction matrix is partial because the XcodeBuildMCP worker could not load its configured transport and no local Simulator touch automation tool was available.
No physical device was modified, no share action sent a file, no print action submitted a job, and no commit was pushed.

## Goal

PrepBook must turn one saved `ProductionRun` snapshot into an offline A4 PDF production sheet.
The operator can preview the sheet, switch between batch-oriented and total-oriented organization, share the generated PDF, or open the platform print service.

## Source requirements

The product design requires a one-page production sheet when the content remains readable.
It also requires total-oriented and batch-oriented organization, PDF sharing, platform printing, stored snapshot fidelity, and offline operation.
See `docs/notes/2026-09-06-prepbook-pro-design.md` under Core workflow, Share and print, Production history, and Architecture.

The `pdf` package provides a pure Dart PDF document model and multi-page widget layout.
The `printing` package provides Flutter preview, platform share, and platform print integration.
See <https://pub.dev/packages/pdf> and <https://pub.dev/packages/printing>.

## Scope

This change adds the export core and the Share and Print presentation flow.
The flow starts from the existing production result screen after the run has been saved.
The saved `ProductionRun` instance is the only production data source for the export.

The first version uses A4 portrait pages only.
It does not expose a paper-size or orientation selector.

## Architecture

The implementation uses this data flow:

`ProductionRun` → `ProductionSheetBuilder` → `ProductionSheet` → `ProductionSheetPdfRenderer` → PDF bytes → preview, share, or print.

Code under `lib/export/` owns the immutable production-sheet model, organization rules, section plan, filename policy, and PDF renderer.
This code can depend on pure Dart libraries, the existing domain layer, and the `pdf` package.
It must not import Flutter widgets, `dart:ui`, platform channels, the persistence layer, or the `printing` package.

Code under `lib/presentation/production_sheet/` owns the screen, localized-copy adapter, screen state, asset loading, and the thin platform adapter.
Only the platform adapter calls the `printing` package.
Widget tests can replace this adapter with a fake.

The existing production result screen opens the Share and Print route only when `ProductionResultStatus.saved` is active.
It passes `state.run` directly to the route.
The export flow must not reopen the snapshot from storage and must not recalculate it from the current recipe library.

## Determinism contract

The builder must produce the same `ProductionSheet` structure for the same `ProductionRun`, organization, and localized copy.
The renderer must produce the same visible content, section order, page breaks, and page count for the same sheet, A4 page format, and font bytes.
The renderer must not read the wall clock, random values, storage, network state, current recipes, or current ingredients.

Separate render calls do not have to produce byte-for-byte identical PDF files because the selected PDF library creates an internal document identifier.
After one render succeeds, the screen must retain those bytes in memory.
Preview, share, and print must receive that same `Uint8List` instance until the operator changes the organization or requests a retry.

## Production-sheet model

`ProductionSheetOrganization` has two values: `batch` and `total`.
The default value is `batch`.

`ProductionSheet` contains these values:

- The organization.
- The recipe name and revision from the snapshot.
- The requested target yield.
- The UTC creation time from the snapshot.
- The root batch count.
- Whether the saved run is a draft.
- Outstanding warnings in calculation order.
- Acknowledged warnings in calculation order.
- Production sections in depth-first component order.

Each `ProductionSheetSection` represents one recipe occurrence.
The root recipe is the first section.
Each expanded sub-recipe occurrence becomes a separate later section immediately after its parent component.
The section records its occurrence path, nesting depth, recipe name, target yield, batch plan, preparation notes, and component rows.

The same sub-recipe can occur at more than one path.
The builder must keep those occurrences as separate sections even when they reference the same recipe identifier.
The builder must not merge quantities from separate paths.

If an old snapshot does not contain a referenced recipe or ingredient name, the builder uses the stored identifier as the label.
If a referenced recipe object is absent, its occurrence has no preparation notes.
The builder must not read the current library to fill a snapshot gap.

The root section uses `ProductionRun.targetYield` as its target.
A nested section uses the displayed total of its parent sub-recipe component because the domain calculator used that displayed total to expand the nested result.
Each section uses the `BatchPlan` that is already present in its corresponding `ProductionResult`.
The builder must not derive a nested batch plan from the root batch plan.

## Batch-oriented organization

Batch-oriented organization is the default because the operator performs production one batch at a time.

Each section contains consecutive batch groups.
The builder can combine adjacent batches only when all of these values are equal:

- The batch yield.
- Every component's exact quantity.
- Every component's displayed quantity.
- The component order.

A combined group states the inclusive batch range and the per-batch yield.
Its table shows the amount used in each batch, not the whole-run total.
A remainder batch remains a separate group when its yield or any component quantity differs.

A `fixedOnce` component therefore has its amount in the first batch and zero in later batches because that is what `ScaledComponent.perBatch` stores.
A `manual` component shows that no calculated amount exists.
The builder must not distribute a manual value or a whole-run override across batches.

## Total-oriented organization

Total-oriented organization keeps the same depth-first section order.
Each section contains one component table that uses `ScaledComponent.total`.

The section depth and occurrence path preserve the nested structure.
A sub-recipe reference remains visible in its parent section, and the referenced recipe occurrence also receives its own section.

## Quantities and overrides

The displayed quantity is the primary calculated amount.
If the exact quantity differs from the displayed quantity, the row must also show the exact quantity.
The renderer must not calculate, round, convert, add, or divide domain quantities.
It formats only the `Quantity` and `ScaledQuantity` values that the snapshot already stores.

An operator override does not replace or rescale the calculated result.
The row must show the calculated value and the operator value together.
The operator value must carry a localized `whole run` label in both organization modes.

An override uses the existing `(recipeId, componentId)` key.
If the same recipe component appears through more than one occurrence path, each occurrence shows the shared whole-run override.
The builder must not invent an occurrence-specific override.

## Warnings and draft sheets

The builder preserves warning order from `ProductionRun.result.warnings`.
It separates warnings by membership in `ProductionRun.acknowledgedWarnings`.
It must not infer acknowledgement from whether a warning is blocking.

A saved run is a draft when `ProductionRun.isFinalizable` is false.
Every page of a draft PDF must show a visible `DRAFT` watermark.
The first page must show outstanding warnings before the first production section.
The first page must separate outstanding warnings from acknowledged warnings.

A finalizable run can still contain an outstanding non-blocking warning.
That warning remains in the outstanding group.
The PDF must not claim that all warnings are acknowledged merely because the run is finalizable.

## Page content

The first page summary contains these values:

- Recipe name.
- Recipe revision.
- Requested target yield.
- Snapshot creation time in UTC, formatted with the current app locale and an explicit `UTC` suffix.
- Root batch count.
- Organization name.

Each production section contains these values:

- Recipe name and nesting depth.
- Section target yield.
- Section batch count and batch yields.
- Ordered preparation notes.
- Ordered component rows.

Every page footer contains the root recipe name, the complete saved run ID, and `current page / total pages`.
The run ID remains visible when an unbounded recipe name is clipped to the footer's fixed line.
The PDF metadata title uses the root recipe name.
The PDF metadata creator and producer use `PrepBook`.
No metadata value may read the current clock.

## Pagination

The renderer targets one page but must add pages instead of reducing text below the minimum readable size.
The minimum body font size is `9` PDF points.
The renderer must use fixed margins, spacing, and font sizes for A4 portrait output.

The summary, warning block, and each production section use a keep-together-first policy.
If one block fits on a fresh page but not in the remaining space, the renderer moves the complete block to the next page.
Warning and section spacing participates in the keep-together decision and must not create a footer-only page.

If one block is taller than a fresh page, the renderer can split it only between bounded table rows.
It must never split one rendered row across pages.
It must repeat the section header, table header, and active batch heading after the split.
Summary text, warning messages, section names, preparation notes, component labels, component notes, and amount text must keep all text and split into deterministic bounded rows when one stored value cannot fit on a page.
Each row contains at most `500` Unicode code points and at most `40` lines.
The renderer must not impose a fixed document page limit on valid saved content.
Its debug-only runaway-layout guard must scale from the bounded row count.

The renderer must preserve section order across every page.
It must not move a later small section ahead of an earlier large section to fill unused space.

The implementation uses the `pdf` package's multi-page layout, `Inseparable` keep-together behavior, and repeatable table rows.
The renderer must include a regression test for a section that fits only on a fresh page and another regression test for one section that must span pages.

## Localization and fonts

The PDF uses the locale that is active when the operator opens the Share and Print screen.
The export core receives localized copy through a pure Dart interface.
It must not import Flutter-generated localization classes.

The app bundles `NotoSansKR[wght].ttf` as a Flutter asset for English and Korean output.
The source is the Google Fonts repository at commit `4efc2774c63917927efe769ca845def6bd6debae`.
The font file SHA-256 is `194018e6b2b293a7964f037b25c0249ce1418bc9ab3c971060a03aa57861e252`.
The bundled `OFL.txt` SHA-256 is `1c05c68c34f9708415aada51f17e1b0092d2cea709bf4a94cd38114f9e73d7d9`.

The app must bundle the corresponding SIL Open Font License text beside the font.
The repository keeps the pinned license bytes unchanged and disables Git whitespace diagnostics only for that exact asset through `.gitattributes` because the upstream file contains one trailing space.
The export flow must not use `PdfGoogleFonts`, download a font, or make any other network request.

## Filename

The filename format is `production-sheet-<recipe>-<UTC timestamp>.pdf`.
The timestamp format is `yyyyMMdd'T'HHmmss'Z'` and comes from `ProductionRun.createdAt.toUtc()`.

The recipe segment preserves Unicode letters and numbers.
The sanitizer replaces control characters and `/`, `\`, `:`, `*`, `?`, `"`, `<`, `>`, and `|` with `-`.
It replaces each whitespace run with `-`, collapses repeated hyphens, removes leading and trailing dots, spaces, and hyphens, and limits the segment to the first `80` Unicode code points.
It truncates the segment further when necessary so the complete filename does not exceed `255` UTF-8 bytes.
If the result is empty, the segment is `production-run`.

## Presentation flow

The production result screen shows one Share and Print action.
The action is absent or disabled until the run reaches `ProductionResultStatus.saved`.
The action remains available for a saved draft.

The Share and Print screen begins generation immediately.
It shows progress while the font asset, production-sheet model, and PDF bytes are being prepared.

After generation succeeds, the screen shows these controls:

- An A4 portrait PDF preview.
- A batch-oriented or total-oriented segmented control.
- A Share action.
- A Print action.

Changing the organization starts a new generation for the same saved snapshot.
The screen disables share and print until the new bytes are ready.
The selected organization remains visible during generation and after a failure.

At compact width, the controls and preview use one vertical screen.
At medium and expanded widths, the organization and actions use the first pane and the PDF preview uses the second pane when `usesMultiplePanesAt` permits it.
The screen must preserve the selected organization and current bytes when the window crosses a width boundary.

The organization control, Retry, Share, and Print must have localized visible labels and semantic button roles.
The layout must remain usable at `300` percent text scale without a Flutter overflow.

## Platform adapter

The production adapter loads the bundled font through Flutter's asset bundle.
It shares bytes through `Printing.sharePdf` and prints bytes through `Printing.layoutPdf`.
The print callback must return the bytes already held by the screen.
It must use A4 portrait and disable dynamic relayout.

The adapter returns whether the platform operation completed.
A `false` result is a cancellation and not an error.
An exception is a failure.

The adapter must not create an application-managed temporary file.
The screen holds the current PDF bytes in memory for the lifetime of the route.

## Failure behavior

If generation fails, the screen hides or disables preview, share, and print.
It shows a localized generation error and a Retry action.
Retry reruns generation with the same snapshot and selected organization.

If share or print throws, the route stays open and keeps the successful preview bytes.
It shows a localized error next to the action area.
The other action remains available.

If the platform share or print UI returns `false`, the screen treats the operation as cancelled.
It does not show a failure message.

The first implementation runs generation on the main isolate.
It does not add an isolate abstraction.
Runtime verification must use the largest committed export fixture to determine whether generation visibly blocks the interface.
An isolate is future work unless that measurement shows a user-visible stall.

## Dependencies and native integration

The implementation adds `pdf: ^3.13.0` and `printing: ^5.15.0`.
These versions match the repository's Dart `^3.12.0` and Flutter `^3.44.0` constraints.
The `printing` package supplies preview, share, and print, so the implementation must not add `share_plus` or another file-sharing dependency.

`printing` `5.15.0` includes Swift Package Manager support for iOS.
The implementation must preserve the repository's existing generated Flutter Swift package integration.
It must not switch the iOS project back to CocoaPods.

The manifest and regenerated `pubspec.lock` belong in the same dependency commit.

## Verification

Pure Dart tests must verify these properties:

- Batch-oriented output uses each section's own batch plan and per-batch quantities.
- Consecutive identical batches group together, and a different remainder stays separate.
- Total-oriented output uses stored totals.
- Exact and displayed values remain distinct when rounding changed a value.
- Overrides remain beside the calculated values and carry the whole-run label.
- Manual rows do not receive invented numeric values.
- Repeated sub-recipe occurrences remain separate and keep depth-first order.
- Warnings split into outstanding and acknowledged groups without changing order.
- Draft state follows `ProductionRun.isFinalizable`.
- Filename construction is deterministic and safe for English, Korean, invalid characters, an empty sanitized name, names longer than `80` code points, and the `255`-byte filename limit.
- The export boundary rejects Flutter, persistence, platform, network, and `printing` imports.

Renderer tests must verify these properties:

- The file starts with the PDF signature and uses A4 portrait pages.
- Korean and English strings are embedded without a font error.
- Every draft page contains the watermark.
- Every footer contains the root recipe, complete run ID, and correct page numbers.
- A section moves intact when it fits on a fresh page.
- Warning and section spacing does not create a footer-only page.
- An oversized section splits only at row boundaries and repeats its headers.
- Every continuation page identifies the active batch or batch range.
- An oversized preparation note spans pages without dropping its first or last text.
- An oversized component note spans pages without dropping its first or last text.
- An oversized component label spans pages without dropping its first or last text.
- An oversized summary recipe name spans pages without dropping its first or last text.
- An oversized warning message spans pages without dropping its first or last text.
- An oversized section name spans pages without dropping its first or last text.
- Oversized amount text spans pages without dropping its first or last text.
- A valid sheet can render more than `100` pages without hitting the debug-only runaway-layout guard.
- The same sheet input yields the same page count across two renders.

Layout regression tests use an uncompressed verbose test render and read the actual per-page drawing comments.
The production render remains compressed and does not include those diagnostics.

Visual PDF inspection must verify the draft watermark, localized text, footer text, section movement, row boundaries, and repeated headers against the rendered pages.

Flutter widget tests must verify these properties:

- Share and Print is unavailable before save and available after save, including for a saved draft.
- The screen starts in batch-oriented mode.
- Changing the organization regenerates the bytes without changing the snapshot.
- Preview, share, and print receive the same successful bytes and filename.
- Generation, share, and print failures remain recoverable.
- Platform cancellation does not show an error.
- Width transitions preserve organization and generated bytes.
- Korean and English labels render without overflow at `300` percent text scale.

Runtime verification must cover an iOS Simulator and an Android Emulator.
On each platform, verify preview rendering, batch and total switching, a Korean draft watermark, long multi-page output, opening and cancelling the share sheet, and opening and cancelling the print service.
The verification must not send a shared file and must not submit a print job.

The final local gates are `flutter pub get`, explicit-path `dart format`, `flutter analyze`, `dart run bloc_tools:bloc lint .`, scoped `trunk check`, `very_good test --coverage --test-randomize-ordering-seed random`, `git diff --check`, and final diff inspection.

## Non-goals

This change does not add production history UI.
It does not add backup, restore, spreadsheet migration, stored-run editing, paper-size selection, orientation selection, cloud storage, analytics, or network font loading.
It does not change calculation, rounding, batching, warning, override, persistence, or repository contracts.
It does not implement issue `#12`.
