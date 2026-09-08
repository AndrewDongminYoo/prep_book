import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';

/// The `Unit` instances the domain exposes as a fixed, enumerable set.
///
/// `Unit.count` and `Unit.namedYield` build additional units from arbitrary
/// caller-chosen symbols, so the domain's full unit space is not enumerable.
/// A unit outside this fixed set is stored with a `count:` or `yield:`
/// prefix by [unitToStorage] instead of relying on a table lookup; see that
/// function and [unitFromStorage] for the encoding.
final _fixedUnits = <Unit>[
  Unit.milligram,
  Unit.gram,
  Unit.kilogram,
  Unit.milliliter,
  Unit.liter,
  Unit.teaspoon,
  Unit.tablespoon,
  Unit.portion,
];

/// Encodes [unit] as the string a `_unit` column stores.
///
/// One of the fixed units in [_fixedUnits] stores its bare symbol (`g`,
/// `kg`, `portion`, ...). Every other unit is dynamic — built by
/// `Unit.count` or `Unit.namedYield` from a caller-chosen symbol — and is
/// stored as `count:<symbol>` or `yield:<symbol>` so the single `_unit`
/// column can still round-trip it without a second schema column recording
/// which factory built it. A mass or volume unit can only be one of the
/// fixed instances above, since `Unit`'s constructor is private, so the
/// dynamic branch below is reached only for `count` and `yieldOnly`.
String unitToStorage(Unit unit) {
  for (final fixed in _fixedUnits) {
    if (fixed == unit) return fixed.symbol;
  }
  final kind = unit.dimension == UnitDimension.count ? 'count' : 'yield';
  return '$kind:${unit.symbol}';
}

/// Recovers the domain `Unit` a [stored] string encodes, naming [location]
/// if it cannot.
///
/// A bare symbol matching one of [_fixedUnits] decodes to that unit. A
/// `count:<symbol>` or `yield:<symbol>` form decodes to `Unit.count` or
/// `Unit.namedYield` on the trailing payload, including an empty one
/// (`count:` decodes to `Unit.count('')`) — the domain places no
/// restriction on that symbol being non-empty, and persistence must be
/// able to store everything the domain can construct. Anything else — an
/// unrecognised bare symbol, or a prefix that is neither `count` nor
/// `yield` — is a corrupt row, never a guessed unit.
///
/// [location] is required for the same reason [parseStoredRational]'s is:
/// this function is handed one string and can name nothing on its own,
/// while every caller knows the row it read that string from. Three of the
/// four repository reads that reach it scan many rows at once
/// (`IngredientRepository.listAll`, `RecipeRepository.listLatestRevisions`,
/// `ProductionRunRepository.listSummaries`), so an unnamed symbol would
/// fail a whole history screen while telling the operator nothing about
/// which row to repair.
Unit unitFromStorage(String stored, {required String location}) {
  for (final fixed in _fixedUnits) {
    if (fixed.symbol == stored) return fixed;
  }
  final separator = stored.indexOf(':');
  if (separator > 0) {
    final kind = stored.substring(0, separator);
    final symbol = stored.substring(separator + 1);
    if (kind == 'count') return Unit.count(symbol);
    if (kind == 'yield') return Unit.namedYield(symbol);
  }
  throw CorruptDatabaseError('unknown unit symbol in $location: $stored');
}

/// Rebuilds the `Rational` a stored decimal-string pair encodes, naming
/// [location] if it cannot.
///
/// [location] must identify the failing value well enough for a reader to
/// find it, and that means the row whenever the caller knows it —
/// [quantityFromColumns] passes a column group *and* its row label for
/// exactly this reason. It is what [CorruptDatabaseError]'s "always names
/// the row" contract reduces to at this depth: this function is handed two
/// strings and can name nothing on its own.
///
/// Neither failure here is a `TypeError`, so neither is caught by the
/// shape guards in `result_codec.dart` and the repositories:
/// `BigInt.parse` throws a `FormatException` on a string that is not an
/// integer, and `Rational` throws an `ArgumentError` on a zero
/// denominator. Both would otherwise escape this layer raw, and a caller
/// wrapping storage reads in `on CorruptDatabaseError` would not see them.
///
/// Shared by [quantityFromColumns] and `result_codec.dart` rather than
/// written twice: the column pair and the JSON pair are the same encoding,
/// so a divergence between two copies of this check would be a bug, not a
/// degree of freedom.
Rational parseStoredRational(
  String numerator,
  String denominator, {
  required String location,
}) {
  try {
    return Rational(BigInt.parse(numerator), BigInt.parse(denominator));
  } on FormatException catch (error) {
    throw CorruptDatabaseError(
      'amount in $location is not an integer pair: $numerator/$denominator '
      '($error)',
    );
    // `ArgumentError` is an `Error`, so catching it needs this ignore for
    // the same reason `result_codec.dart`'s `on TypeError` handler does: a
    // zero denominator in a stored row is a corrupt row, not a programmer
    // bug in the caller that read it.
    // ignore: avoid_catching_errors
  } on ArgumentError catch (error) {
    throw CorruptDatabaseError(
      'amount in $location has a zero denominator: $numerator/$denominator '
      '($error)',
    );
  }
}

/// Splits [quantity] into the three text columns named by [prefix]:
/// `<prefix>_numerator`, `<prefix>_denominator`, and `<prefix>_unit`.
///
/// The numerator and denominator are stored as decimal strings because a
/// `Rational`'s components are `BigInt`, which SQLite's 64-bit `INTEGER`
/// cannot be relied on to hold.
Map<String, Object?> quantityToColumns(Quantity quantity, String prefix) =>
    <String, Object?>{
      '${prefix}_numerator': quantity.amount.numerator.toString(),
      '${prefix}_denominator': quantity.amount.denominator.toString(),
      '${prefix}_unit': unitToStorage(quantity.unit),
    };

/// Rebuilds the `Quantity` stored under [prefix] in [row], identifying the
/// row as [rowLabel] if it cannot.
///
/// Throws [CorruptDatabaseError] when any of the three columns is missing or
/// is not a `String`, when the numerator and denominator are not an integer
/// pair [Rational] accepts, when the unit column is not one
/// [unitFromStorage] recognises, or when the amount and unit are a pair the
/// domain refuses — a negative amount is the reachable case, since
/// [parseStoredRational] accepts a negative numerator and `Quantity` rejects
/// it.
///
/// That last guard sits here rather than at each of the five callers because
/// this is the one function every stored quantity group passes through:
/// `recipes.base_yield`, `recipes.max_batch`, `recipe_components.base`,
/// `production_runs.target`, and `run_overrides.override` all reach a domain
/// factory only on the line below. A `DomainError` is neither a `TypeError`
/// nor a `FormatException` — it is `sealed class DomainError implements
/// Exception` — so before this clause existed it escaped every guard in this
/// layer unlabelled, past a caller wrapping its storage reads in
/// `on CorruptDatabaseError`.
///
/// [rowLabel] is required rather than optional because a quantity group
/// says nothing about which row holds it, and the column-group name alone
/// repeats across tables: `target` appears on `production_runs`, `base` on
/// `recipe_components`. A caller scanning many rows — `listSummaries` over
/// the whole run history, say — would otherwise be told only that some
/// quantity somewhere was incomplete. Callers pass their table and the
/// row's identifying columns, in the same shape their own guards use, so
/// the two agree when a row fails both ways.
Quantity quantityFromColumns(
  Map<String, Object?> row,
  String prefix, {
  required String rowLabel,
}) {
  final numerator = row['${prefix}_numerator'];
  final denominator = row['${prefix}_denominator'];
  final symbol = row['${prefix}_unit'];
  if (numerator is! String || denominator is! String || symbol is! String) {
    throw CorruptDatabaseError(
      'incomplete quantity in column group $prefix of $rowLabel',
    );
  }
  final location = 'column group $prefix of $rowLabel';
  final amount = parseStoredRational(
    numerator,
    denominator,
    location: location,
  );
  final unit = unitFromStorage(symbol, location: location);
  // Only the domain factory is inside the try. Both helpers above already
  // raise a [CorruptDatabaseError] naming this same location, and keeping
  // them outside means this clause never has to be read against what they
  // might throw.
  try {
    return Quantity.fromRational(amount, unit);
  } on DomainError catch (error) {
    throw CorruptDatabaseError('invalid quantity in $location: $error');
  }
}
