import 'package:decimal/decimal.dart';
import 'package:prep_book/domain/units/unit.dart';
import 'package:rational/rational.dart';

/// Base type for every error the domain raises.
sealed class DomainError implements Exception {
  const DomainError(this.message);

  final String message;

  @override
  // Diagnostic-only: this message is logged for debugging, never shown
  // to an end user, so an obfuscated release renaming the type is fine.
  // ignore: no_runtimetype_tostring
  String toString() => '$runtimeType: $message';
}

/// Raised when two units have no defined conversion between them.
final class UndefinedConversionError extends DomainError {
  UndefinedConversionError(this.from, this.to)
    : super('no defined conversion from ${from.symbol} to ${to.symbol}');

  final Unit from;
  final Unit to;
}

/// Raised when a quantity would become negative.
final class NegativeQuantityError extends DomainError {
  NegativeQuantityError(this.amount)
    : super('a quantity may not be negative: $amount');

  final Rational amount;
}

/// Raised when a rounding increment is not strictly positive.
final class InvalidRoundingIncrementError extends DomainError {
  InvalidRoundingIncrementError(this.increment)
    : super('a rounding increment must be positive: $increment');

  final Decimal increment;
}

/// Raised when a recipe's base yield is zero.
///
/// A negative base yield cannot reach this guard: `Quantity.fromRational`
/// already rejects a negative amount when the yield is constructed. A
/// missing one cannot reach it either — a recipe's base yield parameter is
/// required, not nullable.
final class InvalidBaseYieldError extends DomainError {
  InvalidBaseYieldError(this.recipeId)
    : super('recipe $recipeId has no positive base yield');

  final String recipeId;
}

/// Raised when a recipe's maximum batch yield is zero.
///
/// Zero is redundant with `null`, which already means "no maximum" — see
/// `BatchPlan.decompose`. Accepting a zero maximum would let it reach that
/// decomposition and be silently reinterpreted as `null` there, so it is
/// rejected here instead.
final class InvalidMaxBatchYieldError extends DomainError {
  InvalidMaxBatchYieldError(this.recipeId)
    : super('recipe $recipeId has a zero maximum batch yield');

  final String recipeId;
}

/// Raised when a component's fields contradict its scaling behavior, or a
/// recipe's component list repeats an id.
final class InvalidComponentError extends DomainError {
  InvalidComponentError(this.componentId, String reason)
    : super('component $componentId is invalid: $reason');

  final String componentId;
}

/// Raised when a yield is expressed in an incompatible dimension.
final class IncompatibleYieldUnitError extends DomainError {
  IncompatibleYieldUnitError(this.expected, this.actual)
    : super('expected a yield in ${expected.symbol}, got ${actual.symbol}');

  final Unit expected;
  final Unit actual;
}

/// Raised when a recipe depends on itself, directly or indirectly.
final class RecipeCycleError extends DomainError {
  RecipeCycleError(this.path)
    : super('recipe dependency cycle: ${path.join(' -> ')}');

  /// The dependency path, ending at the identifier that repeats.
  final List<String> path;
}

/// Raised when a referenced recipe is not in the index.
final class MissingDependencyError extends DomainError {
  // `recipeId == missingId` only ever happens when the walk's root itself is
  // absent: a cycle check runs before this walk, so a recipe that truly
  // references itself is already reported as a RecipeCycleError, never
  // reaches here. That case is not "references itself" but "is not there",
  // so it gets its own message rather than the misleading reference wording.
  MissingDependencyError(this.recipeId, this.missingId)
    : super(
        recipeId == missingId
            ? 'recipe $recipeId is not in the index'
            : 'recipe $recipeId references missing recipe $missingId',
      );

  final String recipeId;
  final String missingId;
}

/// Raised when a target yield is zero.
final class InvalidTargetYieldError extends DomainError {
  InvalidTargetYieldError()
    : super('a production run needs a positive target yield');
}

/// Raised when a target needs more full batches than a batch count can
/// hold.
///
/// Not a bound on how large a run may be — that is
/// [BatchLimitExceededError], which is the caller's to set or to leave
/// unset. This one is the arithmetic refusing to answer: the count is
/// derived exactly and then kept as an `int`, and past the largest one
/// there is no truthful answer left to give.
final class BatchCountOverflowError extends DomainError {
  BatchCountOverflowError(this.batchCount)
    : super('a run of $batchCount batches cannot be counted');

  /// How many batches the target actually needs, exactly, counting a
  /// remainder batch when there is one.
  ///
  /// The whole count rather than the full-batch count alone, because the
  /// remainder batch is what carries a plan of exactly the largest `int`
  /// full batches past what a count can hold. Kept as it was derived
  /// rather than narrowed, since narrowing it is the thing this refuses.
  final BigInt batchCount;
}

/// Raised when a recipe in a run splits into more batches than the caller
/// allowed.
///
/// Not a product rule about how large a run may be: the bound is optional,
/// the caller sets it, and a caller that sets none scales to any target.
/// It exists so a caller that cannot afford an unbounded calculation — an
/// interactive screen, which blocks until one returns — can have it refused
/// rather than performed.
final class BatchLimitExceededError extends DomainError {
  BatchLimitExceededError(this.recipeId, this.maxPlannedBatches)
    : super('recipe $recipeId needs more than $maxPlannedBatches batches');

  /// The recipe whose own batch plan crossed the bound.
  ///
  /// Not necessarily the run's root. A sub-recipe is scaled to whatever
  /// its parent's component total demands, against its own maximum batch
  /// yield, so it can cross a bound the root stays far inside.
  final String recipeId;

  /// The bound the caller set.
  final int maxPlannedBatches;
}
