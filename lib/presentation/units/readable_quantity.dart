import 'package:prep_book/domain/domain.dart';

/// [amount] as a decimal at [scale] places, or as the exact fraction where
/// that rounding cannot hold it.
///
/// For a ratio or a converted amount, which is where a screen meets a value
/// the domain keeps exact and a kitchen has to read as a number.
String readableAmount(Rational amount, {required int scale}) =>
    _approximated(amount, amount.toDecimal(scaleOnInfinitePrecision: scale));

/// [quantity]'s amount alone, without the unit symbol [readableQuantity]
/// writes after it.
///
/// For the places a screen needs the number on its own: a row that lays the
/// amount and the symbol out as separate widgets, and a form field the
/// operator types over. Both used to call `toDecimal()` themselves, which is
/// the one call that turns a small positive amount into `0`.
///
/// A field seeded from this is still safe to save back: the recipe editor
/// decides whether a line is still showing its stored value by comparing the
/// field's text against this same function, so the two sides move together
/// whatever it returns.
String readableAmountOf(Quantity quantity) =>
    _approximated(quantity.amount, quantity.toDecimal());

/// [quantity] as the screens write it: an amount and the symbol of the unit
/// it is measured in.
///
/// Rounded at the domain's own display scale, which `Quantity.toDecimal`
/// owns, so a quantity reads here the way it reads anywhere else.
String readableQuantity(Quantity quantity) =>
    '${readableAmountOf(quantity)} ${quantity.unit.symbol}';

/// What a value looks like once its exact form has been approximated:
/// [rounded], unless rounding has flattened it to nothing, in which case
/// the [exact] fraction the domain holds.
///
/// The one place that decision is made, because every fixed number of
/// places has a value below it that rounds to zero, and a row reading `0`
/// over positive numbers is simply false. Two of them had been on this
/// screen: a run scaled to `1/30000` of its base yield, whose four-place
/// decimal is `0`, and a target of a millionth of a millilitre against a
/// recipe measured in tablespoons, which is `1/15000000` tbsp and rounds
/// to `0` at six. Deepening either scale would only move the threshold,
/// while the fraction is exact at any magnitude — so both go the same way
/// rather than each screen choosing.
///
/// A value with a finite decimal form is never touched: `toDecimal` applies
/// a scale only to a value that has none, so a millionth of a tablespoon
/// still reads `0.000001`, and only a value no decimal at that scale can
/// express falls back. An amount that is exactly zero reads `0` either way.
String _approximated(Rational exact, Decimal rounded) =>
    rounded == Decimal.zero ? '$exact' : '$rounded';
