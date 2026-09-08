/// A stored row cannot be turned back into a domain object.
///
/// Always names the row. Never repaired by guessing a value, because a guess
/// here would put an invented quantity into a production record.
final class CorruptDatabaseError implements Exception {
  const CorruptDatabaseError(this.message);

  final String message;

  @override
  String toString() => 'CorruptDatabaseError: $message';
}
