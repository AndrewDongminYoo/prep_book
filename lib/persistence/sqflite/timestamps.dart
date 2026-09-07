/// Encodes [value] as the text a timestamp column or payload field stores.
///
/// Two normalizations, both of which have to happen at the write, because
/// this is the last moment either piece of information is still available.
///
/// The value is moved to UTC first. `toIso8601String` emits the trailing
/// `Z` from the `isUtc` flag rather than from a zone offset, and a caller
/// supplies whatever `DateTime` it holds — `DateTime.now()` is local. A
/// column mixing the two forms is uncomparable as text, and a naive value
/// already written cannot be assigned an offset afterwards.
///
/// The microsecond triplet is then always present. `toIso8601String` writes
/// the millisecond triplet unconditionally and the microsecond triplet only
/// when `microsecond` is non-zero, so a whole-millisecond instant
/// serializes three characters shorter than one carrying microseconds — and
/// the shorter string sorts *after* the longer one, because the `Z` it ends
/// on is greater than any digit. That inverts
/// `ProductionRunRepository.listSummaries`, which orders on `created_at` as
/// text: of two runs landing in the same millisecond, the older one is
/// returned first whenever it is the one with no microseconds. Its
/// `id ASC` tiebreaker does not rescue the order, since the two strings are
/// not equal and the tiebreaker is never reached.
///
/// The condition below is the field, `microsecond`, not the width of the
/// string it produced: `microsecond` is what `toIso8601String` itself
/// branches on, so reading it cannot disagree with what was emitted.
///
/// Fixed width was chosen over an integer epoch column so that a timestamp
/// on a production record stays readable to anyone inspecting the database,
/// and so the correction stays inside the write path rather than reaching
/// the column type, its index, and every fixture. The result is still what
/// `DateTime.parse` reads on the way back.
///
/// Every writer of a stored timestamp goes through here — `recipes`'
/// `modified_at`, `production_runs`' `created_at`, and the `modifiedAt`
/// field of a run payload — so the three cannot drift apart.
String timestampToStorage(DateTime value) {
  final utc = value.toUtc();
  final iso = utc.toIso8601String();
  if (utc.microsecond != 0) return iso;
  return iso.replaceFirst('Z', '000Z');
}
