import 'package:prep_book/domain/domain.dart';

final class UnitAliasResolver {
  const UnitAliasResolver();

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
      'piece' ||
      'pieces' ||
      'item' ||
      'items' ||
      'ea' ||
      '개' => Unit.count('piece'),
      'tray' || 'trays' || '판' => Unit.namedYield('tray'),
      _ => null,
    };
  }
}
