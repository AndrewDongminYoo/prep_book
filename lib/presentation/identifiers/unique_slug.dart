/// A run of everything a slug drops: anything that is not a letter or a
/// digit, in any script, so a Korean recipe name slugs to its own words
/// rather than to nothing.
final _slugSeparators = RegExp(r'[^\p{L}\p{N}]+', unicode: true);

/// A lowercase, dash-joined form of [source] that no id in [taken] uses.
///
/// Identifiers are never displayed, so this only has to be stable and
/// unique. Uniqueness is the part that matters: a second recipe named like
/// an existing one would otherwise slug to the same id and be stored as
/// that recipe's *next revision*, silently replacing it in the library
/// under its own name.
///
/// [fallback] is the stem used when [source] holds no letter or digit at
/// all, so a name of punctuation still produces an id.
///
/// One function for every screen that mints an id — the recipe editor for
/// a new recipe or ingredient, the library for a duplicate — so a copy is
/// stored under the same shape of id the editor would have given it.
String uniqueSlug(
  String source,
  Set<String> taken, {
  required String fallback,
}) {
  final parts = source.toLowerCase().split(_slugSeparators);
  final slug = parts.where((part) => part.isNotEmpty).join('-');
  final stem = slug.isEmpty ? fallback : slug;
  if (!taken.contains(stem)) return stem;
  var suffix = 2;
  while (taken.contains('$stem-$suffix')) {
    suffix++;
  }
  return '$stem-$suffix';
}
