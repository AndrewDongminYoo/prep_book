import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  const resolver = UnitAliasResolver();

  test('resolves every supported alias', () {
    final aliases = <Unit, List<String>>{
      Unit.milligram: ['mg', 'milligram', '밀리그램'],
      Unit.gram: ['g', 'gram', 'grams', '그램'],
      Unit.kilogram: ['kg', 'kilogram', 'kilograms', '킬로그램'],
      Unit.milliliter: ['ml', 'milliliter', 'milliliters', '밀리리터'],
      Unit.liter: ['l', 'liter', 'liters', 'L', '리터'],
      Unit.teaspoon: ['tsp', 'teaspoon', '티스푼'],
      Unit.tablespoon: ['tbsp', 'tablespoon', '테이블스푼', '큰술'],
      Unit.portion: ['portion', 'portions', '인분'],
      Unit.count('piece'): ['piece', 'pieces'],
      Unit.count('ea'): ['ea', 'each', 'item', 'items'],
      Unit.count('개'): ['개'],
      Unit.namedYield('tray'): ['tray', 'trays', '판'],
    };

    for (final MapEntry(key: unit, value: unitAliases) in aliases.entries) {
      for (final alias in unitAliases) {
        expect(resolver.resolve(alias), unit, reason: alias);
      }
    }
  });

  test('count units keep the word the source used and never convert', () {
    final whole = resolver.resolve('개')!;
    final each = resolver.resolve('ea')!;
    final piece = resolver.resolve('piece')!;

    expect(whole.symbol, '개');
    expect(each.symbol, 'ea');
    expect(piece.symbol, 'piece');
    expect(whole.canConvertTo(piece), isFalse);
    expect(each.canConvertTo(piece), isFalse);
    expect(whole.canConvertTo(resolver.resolve(' 개 ')!), isTrue);
  });

  test('lists one display symbol per resolvable unit, in table order', () {
    for (final symbol in UnitAliasResolver.symbols) {
      expect(resolver.resolve(symbol)?.symbol, symbol, reason: symbol);
    }
    expect(UnitAliasResolver.symbols, containsAll(['piece', 'ea', '개']));
    expect(
      UnitAliasResolver.symbols.toSet().length,
      UnitAliasResolver.symbols.length,
    );
  });

  test('normalizes only surrounding whitespace and letter case', () {
    expect(resolver.resolve('  GrAmS  '), Unit.gram);
    expect(resolver.resolve('TABLESPOON'), Unit.tablespoon);
  });

  test('leaves absent and unsupported text unresolved', () {
    expect(resolver.resolve(null), isNull);
    expect(resolver.resolve(''), isNull);
    expect(resolver.resolve('cup'), isNull);
    expect(resolver.resolve('oz'), isNull);
    expect(resolver.resolve('flour'), isNull);
    expect(resolver.resolve('milli liter'), isNull);
  });
}
