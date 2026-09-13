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
      Unit.count('piece'): ['piece', 'pieces', 'item', 'items', 'ea', '개'],
      Unit.namedYield('tray'): ['tray', 'trays', '판'],
    };

    for (final MapEntry(key: unit, value: unitAliases) in aliases.entries) {
      for (final alias in unitAliases) {
        expect(resolver.resolve(alias), unit, reason: alias);
      }
    }
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
