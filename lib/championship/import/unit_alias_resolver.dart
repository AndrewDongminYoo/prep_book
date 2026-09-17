import 'package:prep_book/domain/domain.dart';

final class UnitAliasResolver {
  const new();

  /// One display symbol per resolvable unit, in the order the unit tables
  /// list them. Each symbol resolves back to the unit it names, so a picker
  /// can offer exactly these and the mapper can resolve whatever was picked.
  ///
  /// Count units keep the word the source used: a whole item counted in
  /// `개` and one counted in `ea` are different units to the domain, and a
  /// `piece` may be a cut of one, so none of the three stands in for another.
  static const symbols = <String>[
    'mg',
    'g',
    'kg',
    'ml',
    'L',
    'tsp',
    'tbsp',
    'portion',
    'piece',
    'ea',
    '개',
    'tray',
  ];

  Unit? resolve(String? value) {
    final normalized = value?.trim().toLowerCase();
    return switch (normalized) {
      'mg' || 'milligram' || '밀리그램' => Unit.milligram,
      'g' || 'gram' || 'grams' || '그램' => Unit.gram,
      'kg' || 'kilogram' || 'kilograms' || '킬로그램' => Unit.kilogram,
      'ml' || 'milliliter' || 'milliliters' || '밀리리터' => Unit.milliliter,
      'l' || 'liter' || 'liters' || '리터' => Unit.liter,
      'tsp' || 'teaspoon' || '티스푼' => Unit.teaspoon,
      'tbsp' || 'tablespoon' || '테이블스푼' || '큰술' => Unit.tablespoon,
      'portion' || 'portions' || '인분' => Unit.portion,
      'piece' || 'pieces' => Unit.count('piece'),
      'ea' || 'each' || 'item' || 'items' => Unit.count('ea'),
      '개' => Unit.count('개'),
      'tray' || 'trays' || '판' => Unit.namedYield('tray'),
      _ => null,
    };
  }
}
