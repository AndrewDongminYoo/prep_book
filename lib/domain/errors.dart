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
