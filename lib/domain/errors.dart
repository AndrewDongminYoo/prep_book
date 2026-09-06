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
