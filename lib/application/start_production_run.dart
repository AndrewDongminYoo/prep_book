import 'dart:math';

import 'package:prep_book/application/dependency_closure.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

/// Supplies the identifier a new production run is stored under.
///
/// Injected rather than generated inline so a test can assert an exact
/// snapshot; the app binds it to [RandomRunIdSource].
abstract interface class RunIdSource {
  /// A new, unused run identifier.
  String next();
}

/// The [RunIdSource] the app runs on: 128 random bits, written as 32
/// lowercase hexadecimal digits.
///
/// A stored run's identifier is a `TEXT PRIMARY KEY` written by a bare
/// insert, so a repeated value throws rather than replacing the row. It
/// therefore has to be unique across launches, across devices, and across a
/// database restored from a backup onto a second device — which rules out
/// anything counted, and rules out a timestamp, since two runs saved inside
/// one millisecond are exactly what a busy morning produces.
///
/// No package was added for this. A version 4 UUID is 122 random bits and a
/// dash layout; `dart:math`'s [Random.secure] supplies the bits, and the
/// layout carries no meaning here because nothing outside this app ever
/// parses a run identifier. The project's rule is to justify a dependency
/// before taking it, and the standard library already answers this one.
///
/// The optional constructor argument exists so a test can drive an exact
/// identifier out of a source it controls; nothing in the app passes one,
/// and the default is the platform's cryptographic generator rather than
/// a seeded one.
final class RandomRunIdSource implements RunIdSource {
  /// Creates the source, drawing from [random] when one is given.
  RandomRunIdSource([Random? random]) : _random = random ?? Random.secure();

  final Random _random;

  /// How many 32-bit draws make one identifier.
  static const _draws = 4;

  /// The exclusive bound of one draw: `nextInt` accepts 2^32 itself.
  static const int _drawBound = 1 << 32;

  /// Hexadecimal digits one 32-bit draw is written in, so a small draw is
  /// padded rather than shortening the identifier. Without the padding a
  /// draw of zero would contribute one digit instead of eight, and two
  /// different pairs of draws could then spell the same identifier.
  static const _drawDigits = 8;

  @override
  String next() => [
    for (var draw = 0; draw < _draws; draw++)
      _random.nextInt(_drawBound).toRadixString(16).padLeft(_drawDigits, '0'),
  ].join();
}

/// Supplies the current instant, for the same reason as [RunIdSource].
abstract interface class Clock {
  /// The current instant.
  DateTime now();
}

/// Calculates a production run without storing it.
///
/// The design document requires the snapshot to be computed before
/// persistence; returning an unsaved value is how that is satisfied. The
/// caller reviews it, records acknowledgements and overrides, and then
/// passes it to `SaveProductionRun`.
final class StartProductionRun {
  /// Creates the use case.
  const StartProductionRun(this._recipes, this._ids, this._clock);

  final RecipeRepository _recipes;
  final RunIdSource _ids;
  final Clock _clock;

  /// Scales [recipeId] to [targetYield].
  ///
  /// Throws [MissingDependencyError] when the recipe or one of its
  /// sub-recipes is not stored, [RecipeCycleError] when the stored graph has
  /// a cycle, and the domain's own yield errors for a target the recipe
  /// cannot take. None is rewrapped: each already names what the operator
  /// has to be told.
  ///
  /// [maxPlannedBatches] bounds how many batches any one recipe in the run
  /// — the root, and every sub-recipe expanded under it — may be split
  /// into, and a target that crosses it raises [BatchLimitExceededError].
  /// A call argument rather than a constructor one, and unbounded by
  /// default, because the bound belongs to the caller's situation rather
  /// than to the run: a screen that blocks on the calculation has to cap
  /// it, and a caller that can wait has no reason to.
  Future<ProductionRun> call({
    required String recipeId,
    required Quantity targetYield,
    int? maxPlannedBatches,
  }) async {
    final root = await _recipes.findLatest(recipeId);
    // Both arguments match on purpose: `MissingDependencyError` renders
    // "recipe X is not in the index" in that case, which is the wording the
    // domain chose for an absent root rather than a dangling reference. Its
    // own "reports a missing root as absent, not self-referencing" test
    // pins that message.
    if (root == null) throw MissingDependencyError(recipeId, recipeId);

    final closure = await resolveDependencyClosure(_recipes, root);
    final result = ProductionCalculator(
      maxPlannedBatches: maxPlannedBatches,
    ).calculate(recipe: root, targetYield: targetYield, recipeIndex: closure);

    // `dependencySnapshot` documents every recipe the calculation depended
    // on, and `ProductionRun.recipe` already holds the root — so the root
    // is dropped here rather than persisted twice for no reader. `closure`
    // itself keeps the root, because `recipeIndex` above needs it to
    // validate the graph and resolve self-references during expansion.
    final dependencies = {...closure}..remove(root.id);

    return ProductionRun(
      id: _ids.next(),
      createdAt: _clock.now(),
      recipe: root,
      dependencySnapshot: dependencies,
      targetYield: targetYield,
      result: result,
    );
  }
}
