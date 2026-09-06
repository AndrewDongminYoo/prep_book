# PrepBook Pro: Production Recipe Scaling Design

## Status

Approved in conversation on 2026-09-06.

## Summary

PrepBook Pro is a paid, offline-first mobile and tablet application for owners and head chefs of small restaurants and bakeries. A user selects a saved production recipe, enters today's target yield, reviews the calculated batches and exceptional ingredients, and produces a practical production sheet in under 30 seconds.

The first release solves one job: reliable production-volume and recipe scaling. It does not attempt to become inventory, purchasing, costing, payroll, point-of-sale, or team-collaboration software.

## Product decision

Three approaches were considered:

1. A quick multiplier that scales an ad hoc ingredient list.
2. A production-run tool backed by saved recipes, batch rules, sub-recipes, rounding, and printable output.
3. A daily planner that combines many recipes and aggregates all ingredients and station work.

The product will use approach 2. A quick multiplier does not provide enough value over a spreadsheet to justify an upfront purchase. The daily planner is a possible later expansion, but would pull the first release into inventory and operations management before demand is proven.

## Target customer

The purchaser and primary operator is one owner or head chef at a small restaurant or bakery. The first release assumes one operator per local recipe library. Staff members receive exported or printed production sheets; they do not require accounts.

The launch price hypothesis is KRW 19,000 or USD 14.99 as a one-time purchase. The core application must remain useful without an account, subscription, or network connection.

## Product promise

> Select the standard recipe and enter today's quantity; receive an executable production sheet within 30 seconds.

## Core workflow

1. The user selects a recipe from the library.
2. The user enters a target yield expressed in the recipe's production unit.
3. The application calculates the scale ratio, batch decomposition, proportional ingredients, per-batch ingredients, fixed ingredients, sub-recipes, and rounding warnings.
4. The user reviews and, where necessary, temporarily overrides calculated quantities.
5. The application saves an immutable production-run snapshot.
6. The user views, shares, or prints a one-page production sheet organized by totals or by batch.

## Release scope

### Included

- Create, edit, duplicate, archive, search, and categorize recipes.
- Define a base yield and optional maximum batch yield for each recipe.
- Express a yield as portions, item count, mass, or volume.
- Add ingredients and sub-recipes as recipe components.
- Assign proportional, per-batch, fixed-once, or manual scaling behavior to each component.
- Configure display rounding increments per component.
- Calculate a production run deterministically using exact decimal arithmetic.
- Review totals, individual batches, nested sub-recipes, warnings, and temporary overrides.
- Preserve an immutable snapshot for each production run.
- Generate and share or print a one-page PDF production sheet.
- Export and restore a portable recipe-library backup.
- Run the complete workflow offline.
- Support responsive phone, tablet, landscape, and split-window layouts.

### Excluded

- Ingredient prices, recipe cost, margins, or menu profitability.
- Inventory counts, stock deduction, purchasing, suppliers, or purchase orders.
- Staff accounts, roles, assignments, read receipts, chat, or real-time collaboration.
- Scheduling, payroll, point-of-sale, or restaurant-management integrations.
- Daily multi-recipe ingredient aggregation.
- Automatic mass-to-volume conversion.
- AI recipe generation or AI-based quantity correction.
- General-purpose Excel or PDF import exposed to end users.
- Cloud accounts, synchronization, or a required backend.

## Domain model

### Recipe

- Stable identifier.
- Name and optional category.
- Base yield containing an exact decimal amount and a yield unit.
- Optional maximum batch yield in the same unit dimension as the base yield.
- Ordered component list.
- Ordered preparation notes.
- Revision number and modification timestamp.
- Archived state.

A saved edit creates a new recipe revision. Existing production-run snapshots retain the old revision values.

### Ingredient

- Stable identifier.
- Canonical display name.
- Optional category.
- Default display unit.

Ingredients are reusable library entries. The first release does not attach price, stock, supplier, density, or nutrition data.

### Component

A component references either an ingredient or another recipe and contains:

- Exact decimal base quantity.
- Display unit.
- Scaling behavior.
- Optional positive rounding increment.
- Optional operator note.
- Display order.

### ProductionRun

- Stable identifier and creation timestamp.
- Recipe identifier and revision.
- Full recipe and dependency snapshot used for the calculation.
- Requested target yield.
- Derived scale ratio and batch decomposition.
- Calculated quantities before and after display rounding.
- Temporary operator overrides with original calculated values preserved.
- Warnings acknowledged by the operator.

Changing or deleting a recipe does not modify a stored production run.

### ImportDraft

The development-only migration tool produces an import draft containing:

- Source filename and template-adapter identifier.
- Candidate recipes, ingredients, components, units, and notes.
- Source sheet, row, and cell coordinates for traceability.
- Validation errors and warnings.
- Original unrecognized values.

Only a reviewed, valid draft can be promoted into initial application data or test fixtures.

## Quantity and unit model

All quantities use exact decimal values. Binary floating-point values are prohibited in domain calculations. Rounding occurs only when applying an explicit component rule or formatting a result for display.

Supported unit dimensions are:

- Mass: mg, g, kg.
- Volume: ml, L, teaspoon, tablespoon.
- Count: item, sheet, bag, and other named count units.
- Yield-only units: portion and recipe-defined named output units.

Automatic conversion is allowed only within a compatible dimension with a defined conversion. The system must not infer density or automatically convert mass to volume. A component may retain its original unit without conversion.

Free-form quantities such as "to taste" or "as needed" are represented as manual components rather than numeric zeroes.

## Scaling semantics

For a recipe with base yield `B` and target yield `T`, the proportional ratio is `T / B`. Both values must be positive and dimensionally compatible.

If maximum batch yield `M` is defined, the run is decomposed into `floor(T / M)` full batches plus one remainder batch when required. Without `M`, the run contains one batch.

Component behavior is defined as follows:

- `proportional`: multiply the base component quantity by `T / B`.
- `perBatch`: multiply the configured base per-batch quantity by the number of batches. A non-empty remainder counts as a batch.
- `fixedOnce`: include the configured quantity once for the entire production run.
- `manual`: do not produce a numeric result until the operator supplies one; expose a blocking review warning but allow the run to be saved after review.

A positive rounding increment rounds the final display quantity upward to the nearest increment by default. The unrounded value remains visible and stored. The operator may override the rounded result for the current production run without changing the recipe.

## Sub-recipes

A recipe component may reference the output of another recipe. The parent component quantity determines the target yield passed into the referenced recipe. The same scaling and batch rules are then applied recursively.

The result view initially keeps sub-recipes collapsed. The operator can expand them into their ingredients and batches or retain them as a single preparation item on the production sheet.

The recipe dependency graph must be acyclic. Direct and indirect cycles are rejected before a recipe revision can be saved. Missing or archived dependencies block a new production run while leaving historical snapshots readable.

## Responsive interaction design

Responsive behavior is based on current window width, not device type. This supports phones, tablets, landscape rotation, iPad multitasking, and Android split-screen mode with one rule set.

### Compact width

- Use one primary pane and step-based navigation.
- Present recipe selection, production setup, results, and export as separate screens.
- Avoid horizontally scrolling data tables.
- Keep the target yield and primary action visible above the keyboard when possible.
- Use sticky result summaries and sectioned ingredient lists.

### Medium and expanded width

- Use a navigation rail where space permits.
- Show the recipe library and recipe detail as a master-detail pair.
- Show production setup and the live calculated result side by side.
- Keep warnings and overrides near the affected component instead of in a detached dialog.
- Allow the production-sheet preview to occupy the secondary pane.

The layout must adapt continuously when the window changes size. Navigation state, entered target yield, overrides, and scroll position must survive a width-class transition. Touch targets must be at least 48 logical pixels, text must respect platform scaling, and all actions must have labeled alternatives to gestures.

## Screens

### Recipe library

- Search and category filters.
- Recent recipes first by default.
- Base yield and unit visible in each row.
- Production Run is the dominant action.
- Create, duplicate, edit, and archive are secondary actions.

### Recipe editor

- Base yield and optional maximum batch yield.
- Ordered ingredients and sub-recipes.
- Scaling behavior and rounding controls exposed per component.
- Inline validation before save.
- Dependency-cycle validation before commit.

### Production setup

- Target amount and compatible yield unit.
- Predicted number and sizes of batches.
- Clear comparison against the base recipe.
- Continue is disabled for invalid or dimensionally incompatible input.

### Production result

- Total quantities and batch-by-batch quantities.
- Collapsible sub-recipes.
- Unrounded and rounded values where they differ.
- Inline manual-item and override controls.
- Warnings remain visible until acknowledged.
- Saving creates the immutable production-run snapshot.

### Share and print

- Preview one-page production sheet.
- Toggle total-oriented or batch-oriented organization.
- Generate PDF, invoke the platform share sheet, or print through the platform print service.

### Production history

- Show recipe name, revision, target yield, date, and warning state.
- Reopen and re-export the stored snapshot.
- Do not silently recalculate using the current recipe revision.

## Architecture

The application is implemented in Flutter for iOS and Android. It contains the following isolated units:

- Presentation: responsive screens, navigation, forms, and view state.
- Application: use cases for recipe revision management, production execution, history, backup, and export.
- Domain: pure Dart quantity, unit, batch, dependency, rounding, and scaling logic.
- Persistence: repository interfaces backed by transactional SQLite storage.
- Export: production-sheet document model and PDF rendering.
- Migration: a development-only Dart command that maps known spreadsheet templates into `ImportDraft` objects and invokes the same domain validation as the app.

The domain module does not depend on Flutter, persistence, PDF generation, files, or network access. A production run is computed before persistence; the snapshot and its acknowledgement state are committed in one transaction.

## Storage and backup

The first release stores recipes, revisions, ingredients, and production snapshots in a local SQLite database. No network request is required at startup or during production execution.

The user can export a portable application backup through the system file picker and restore it explicitly. Restore validates the archive schema and all domain invariants before changing the current library. A failed restore leaves the existing database unchanged. The backup format is versioned for future migrations.

A backend is intentionally deferred. Evidence required to add synchronization is repeated customer demand to use the same library across a phone and a kitchen tablet. If implemented later, local data remains authoritative for offline work and synchronization is an optional paid service with its own recurring-cost model.

## Initial data migration

Existing recipe spreadsheets use a small number of similar templates. The migration tool therefore uses two or three explicit template adapters rather than a generic spreadsheet parser.

Each adapter maps known sheets and columns into an import draft. Unknown fields are retained with coordinates and surfaced for review; the tool never silently guesses. PDF and document copies are reference material for manual comparison, not machine-import sources in the first release.

Five to ten diverse, rights-cleared recipes become deterministic domain fixtures. Proprietary recipes from a previous workplace must not be bundled or distributed without permission; they may be anonymized and structurally altered for private testing.

## Error handling

- Missing, zero, or negative base yield blocks production execution.
- A target yield incompatible with the recipe's yield dimension blocks continuation.
- Undefined conversions remain in their source unit or require explicit correction; they are never guessed.
- A sub-recipe cycle blocks saving the recipe revision and identifies the dependency path.
- Missing or archived dependencies block new production runs but do not damage historical snapshots.
- Manual components produce explicit review warnings and require acknowledgement before the run is finalized.
- Import failures identify the adapter, sheet, row, column, and original value when available.
- PDF failure does not discard the saved production run and can be retried.
- Database writes use transactions; a failed write preserves the previous state.
- Backup restore validates into temporary storage and swaps only after successful validation.

## Testing strategy

### Domain unit tests

- A target equal to the base yield returns unchanged proportional quantities.
- Proportional scaling is deterministic for integer and decimal ratios.
- Batch decomposition produces correct full and remainder batches.
- Per-batch, fixed-once, and manual components follow their defined semantics.
- Rounding preserves the exact unrounded quantity and applies the configured increment.
- Compatible unit conversions are reversible within defined precision.
- Incompatible unit conversions are rejected.
- Nested sub-recipes calculate recursively.
- Direct and indirect dependency cycles are rejected.

### Property and invariant tests

- Positive valid inputs never produce negative quantities.
- Scaling a proportional-only recipe by `x` and then by `y` matches scaling by `x * y` before display rounding.
- Recipe edits cannot alter serialized historical production snapshots.
- A failed restore cannot change the current database.

### Fixture tests

- Five to ten anonymized real recipes cover mixed units, count rounding, sub-recipes, maximum batch size, non-proportional ingredients, and manual notes.
- Adapter output is compared with manually reviewed expected import drafts.
- The calculated output for each target scenario is independently checked against the source spreadsheet.

### Application and UI tests

- Complete the select, target, review, save, and export workflow offline.
- Validate recipe editing and dependency errors.
- Verify PDF content with deterministic document-model and golden tests.
- Resize across compact, medium, and expanded widths without losing in-progress state.
- Exercise phone portrait, phone landscape, tablet portrait, tablet landscape, and split-window widths.
- Verify keyboard navigation, semantic labels, text scaling, and minimum touch targets.

## Definition of done

- A first-time operator can produce and save a production sheet from a bundled sample in 30 seconds or less during usability testing.
- All approved fixture recipes calculate exactly as their manually verified expectations.
- Proportional, per-batch, fixed-once, manual, rounding, and nested-recipe behaviors are supported.
- Recipe creation, editing, duplication, archiving, search, and revision history work offline.
- A stored production run remains unchanged after its source recipe is edited or archived.
- A production sheet can be viewed, shared as PDF, and printed.
- A recipe library can be exported and restored without data loss.
- Compact and expanded layouts pass the defined resize and accessibility tests.
- No account, server, costing, inventory, purchasing, staff-management, or AI feature is required or present.

## Future extensions and entry criteria

- Daily multi-recipe planning: add only after customers regularly create several production runs together and manually aggregate them.
- Costing and profitability: add only after ingredient-price maintenance is validated as a frequent owner workflow.
- Cloud synchronization: add only after repeated phone-and-tablet cross-device demand; charge separately to cover recurring operations.
- Staff distribution: add only after PDF or print handoff proves insufficient.
- End-user spreadsheet import: add only after multiple customers possess recurring, structurally similar migration needs.
