import 'package:prep_book/domain/domain.dart';

/// Every unit the domain declares as a fixed instance.
///
/// `lib/domain/units/unit.dart` owns this set; the domain exposes no list of
/// its own static fields, so the pickers restate them and
/// `recipe_editor_cubit_test.dart` reads that file to fail if the two ever
/// diverge. Kept in one place rather than in each screen, because a second
/// copy is what that test exists to catch and it can only watch one.
///
/// Nothing else about a picker's contents is a copy: every other unit an
/// operator can pick is discovered from the data on screen. `Unit.count` and
/// `Unit.namedYield` build a unit from any string, so no fixed list can name
/// a recipe measured in trays or an ingredient counted in sheets.
final builtInUnits = <Unit>[
  Unit.milligram,
  Unit.gram,
  Unit.kilogram,
  Unit.milliliter,
  Unit.liter,
  Unit.teaspoon,
  Unit.tablespoon,
  Unit.portion,
];
