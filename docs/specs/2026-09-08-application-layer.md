# Application Layer Specification

**Status:** draft, awaiting approval.
**Authority:** `docs/notes/2026-09-06-prepbook-pro-design.md` is the product source of truth.
This document specifies one of its six units and does not restate its scope decisions.

## Purpose

Turn the domain's calculations and the persistence layer's storage into the operations a screen invokes, so that the presentation unit holds view state and nothing else.

The design document assigns this unit "use cases for recipe revision management, production execution, history, backup, and export".
Two of those five are blocked on units that do not exist yet, so this document specifies the first three and says where the other two attach.

## Scope

In scope:

- Recipe revision management: saving an edit as a new revision, duplicating, archiving and restoring, listing and searching the library, and deleting an ingredient that nothing uses.
- Production execution: resolving a recipe's dependency closure, calculating a run, recording acknowledgements and overrides, and committing the snapshot.
- History: listing stored runs and reopening one.

Out of scope, deliberately:

- **Backup and restore.** They need the system file picker, which is a platform dependency this unit does not otherwise have, and validate-then-swap restore needs a second database. The persistence layer already left the one affordance they require: `openPrepBookDatabase` takes a path rather than resolving one. Add them as a use case in the change that adds the file-picker dependency.
- **Export.** The design document's "Export" unit owns the production-sheet document model and PDF rendering. A use case that hands a `ProductionRun` to that unit belongs here, but there is nothing to hand it to yet.
- **View state.** Loading spinners, form drafts, selected tabs, and error presentation belong to the presentation unit. A use case returns a value or throws; it never holds state between calls.

## What this unit may depend on

`lib/application/` may import `lib/domain/` and the repository interfaces in `lib/persistence/repositories.dart`.

It may **not** import `lib/persistence/sqflite/`, `package:sqflite`, `package:sqflite_common_ffi`, or any Flutter library.
Depending on the interfaces rather than their implementation is what lets every use case be tested against in-memory fakes, with no database and no `sqflite_common_ffi` harness.

This is narrower than the domain's purity rule and is enforced the same way, by a test rather than by review.
`test/application/application_boundary_test.dart` checks every `import`/`export` directive under `lib/application/` against an allowlist: `package:prep_book/domain/`, `package:prep_book/persistence/repositories.dart`, `package:prep_book/application/` siblings, and `package:meta/`.
`dart:` imports are permitted here, unlike in the domain — a use case may need `dart:async`.

## Terminology

**Use case** — one operation a screen invokes, as one class with one public method.
**Library** — the stored set of recipes, at their latest revision.
**Dependency closure** — a recipe together with every recipe reachable from it through `Recipe.subRecipeIds`, transitively.
**In-flight run** — a calculated `ProductionRun` that has not been saved yet.

## Shape of a use case

One class per use case, taking its repositories as constructor arguments and exposing a single method.
Grouping several operations into a service class is rejected: a screen that saves a recipe would then also be handed archiving and deletion, and the constructor would name repositories the screen never uses.

```dart
final class ArchiveRecipe {
  const ArchiveRecipe(this._recipes);
  final RecipeRepository _recipes;
  Future<void> call(String recipeId, {required bool isArchived}) => ...;
}
```

`call` rather than a named method, so an invocation reads as the operation rather than as a method on an object.
A use case holds no mutable state, so every one of them is `const`-constructible.

## Recipe revision management

**`SaveRecipeRevision`** takes a `Recipe` carrying the edited content and writes it as the next revision.
The revision number is not supplied by the caller: it is `(await findLatest(id))?.revision ?? 0`, plus one.
A caller that supplies its own revision would race a parallel edit into overwriting one, and `saveRevision` refuses to update an existing row, so the failure would surface as a storage error rather than as the conflict it is.

Before writing, the recipe's dependency closure is loaded and validated with `RecipeDependencyGraph.assertResolvable`, which throws `RecipeCycleError` naming the path, or `MissingDependencyError`.
Validating before the write is what the design document's acyclic-graph invariant requires; validating after would leave the rejected revision stored.

Two details of that validation are easy to get wrong and are specified rather than left to the implementer.
`assertResolvable` reads its root out of the map it was constructed with and reports a root that is absent as a missing dependency, so the map must contain the recipe being saved under its own id.
`ProductionCalculator.calculate` injects the root for its own graph; nothing injects it here.

And the recipe being saved is not stored yet, so the map must hold the **edited** recipe under that id, never the stored revision of it.
The walk therefore seeds its visited set with the edited recipe before following `subRecipeIds`, which keeps a cycle that runs back through the root — an edit to A that references a stored B which already references A — resolving to the edit rather than to the superseded revision that has no such reference.

**`DuplicateRecipe`** reads the latest revision of a recipe and writes a copy under a new id at revision 1.
The copy's name is the caller's, not a derived one: naming policy is a product decision and a screen can show the operator a prefilled field.

**`ArchiveRecipe`** sets or clears the archived flag on every revision, which is what `setArchived` already does.

**`ListLibrary`** returns the latest revision of every recipe.
**`SearchLibrary`** filters that list by a case-insensitive substring of the recipe name.
It is an in-memory filter over `listLatestRevisions` rather than a SQL query, because the library is a single restaurant's recipes and the query surface stays smaller for it.
If a profile ever shows the filter mattering, it moves into the persistence layer as a query and this use case keeps its signature.

**`DeleteIngredient`** does not delete an ingredient that recipes still use.
It calls `listLatestRevisionsUsingIngredient` first and returns those recipes; the ingredient is removed only when that list is empty.
A screen that wants to delete anyway calls it again with `force: true`, so that the operator's confirmation is a second decision rather than a flag the first call already carried.
The repository deliberately refuses nothing, so this rule lives here and nowhere else.

## Production execution

**`StartProductionRun`** resolves the dependency closure, calculates, and returns an unsaved `ProductionRun`.

The closure is built by walking `Recipe.subRecipeIds` from the root, loading each id with `findLatest`, and recursing into what it returns.
Only the latest revision of a dependency is used, matching what `listLatestRevisionsUsingIngredient` already assumes about which revision is current.
A recipe that has already been loaded is not visited again, so a diamond dependency is loaded once and a cycle terminates the walk rather than hanging; the cycle is then reported by `assertResolvable`, not by the walk.
An id the repository answers `null` for is left out of the index, and `ProductionCalculator.calculate` raises `MissingDependencyError` naming it — the walk does not invent an error the domain already owns.

The run's id and `createdAt` are supplied by injected collaborators rather than generated inline, so a test can assert an exact snapshot.
The design document requires the snapshot to be computed before persistence, which this satisfies by returning a value the caller has not stored yet.

**`AcknowledgeWarning`** and **`ApplyOverride`** return `run.acknowledge(...)` and `run.override(...)`.
They exist as use cases even though each is one domain call, because the presentation unit must not reach past this layer into the domain to mutate a run; a later rule about which overrides are permitted has one place to go.

**`SaveProductionRun`** commits an in-flight run through `ProductionRunRepository.save`, which already writes the snapshot and its acknowledgement and override state in one transaction.
It does not call `recordAcknowledgement` or `recordOverride` for a run being saved for the first time; those two exist for state recorded against a run that is already stored.
Saving a run that is not `isFinalizable` is permitted and is not this layer's decision to refuse: the design document makes acknowledgement a precondition of finalizing a run, and a screen that saves a draft is not finalizing it.

## History

**`ListProductionHistory`** returns `listSummaries`, newest first, which the repository already orders.
**`OpenProductionRun`** returns `findById`, or `null` when the run is gone.

A stored run is never recalculated against the current recipe. Both use cases return what was stored.

## Error handling

Domain errors propagate unchanged.
`RecipeCycleError`, `MissingDependencyError`, `IncompatibleYieldUnitError`, and `InvalidTargetYieldError` all name what a screen has to tell the operator, and rewrapping them would only lose the detail.

`CorruptDatabaseError` propagates unchanged as well. It is not an operator error and this layer cannot repair it.

This unit introduces no error type of its own.
The one outcome that is neither a success nor an exception — an ingredient still in use — is returned as a value, because the caller's next step is to show the recipes and ask.

## Testing strategy

Every use case is tested against in-memory fakes of the three repository interfaces, with no database.
The fakes live in `test/application/fakes.dart` and implement the interfaces directly rather than being generated.

The suite covers, at minimum:

- A saved edit becomes revision N+1 and leaves revision N readable.
- A recipe whose components form a cycle is rejected before anything is written, and the rejection names the path.
- An edit that introduces a cycle only through the edited content is rejected. The stored revision of that recipe does not reference the sub-recipe, and the sub-recipe already references it, so a validation that read the stored revision would accept the edit.
- A dependency closure that reaches the same sub-recipe through two paths loads it once.
- A run computed from a recipe that is later edited still reads back with the revision it was computed from.
- Deleting an ingredient two recipes use returns both recipes and removes nothing; the forced call removes it.
- A search matches case-insensitively and returns latest revisions only.

Because the fakes make failure easy to stage, each test that asserts a rejection also asserts that the store is unchanged — a rejection that wrote first would otherwise pass.

## Decisions recorded here, with no prior precedent

- **The revision number is computed by this layer, not supplied by the caller.** The alternative puts a read-modify-write in every screen.
- **`DeleteIngredient` returns blockers instead of throwing.** An in-use ingredient is an expected answer to a question, not a failure.
- **A use case is one class with `call`.** Rejected the service-class grouping for the constructor-surface reason given above.
- **The boundary is enforced by a test, not by review.** The domain layer already established that a layering rule nobody can accidentally break is worth a test file.

## Definition of done

- Every use case above exists, with the boundary test passing.
- `flutter analyze` clean and the suite at 100 percent coverage, which the CI gate requires.
- No file under `lib/application/` imports Flutter, `sqflite`, or a repository implementation.
- The `counter` sample is untouched. It is deleted in the change that adds the first real screen, per CLAUDE.md, and that change belongs to the presentation unit.
