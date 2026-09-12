import 'package:prep_book/domain/domain.dart';

final _packet = Unit.count('packet');

ProductionRun buildProductionSheetRun({bool acknowledgeManual = false}) {
  final child = Recipe(
    id: 'child',
    revision: 2,
    name: 'Starter',
    baseYield: Quantity.parse('1', Unit.gram),
    components: [
      RecipeComponent(
        id: 'child-ingredient',
        target: const IngredientRef('child-ingredient'),
        baseQuantity: Quantity.parse('2', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'packet',
        target: const IngredientRef('packet'),
        baseQuantity: Quantity.parse('1', _packet),
        behavior: ScalingBehavior.fixedOnce,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 10),
    preparationNotes: const ['Feed before use.'],
  );
  final root = Recipe(
    id: 'root',
    revision: 4,
    name: 'Bun dough',
    baseYield: Quantity.parse('10', Unit.gram),
    maxBatchYield: Quantity.parse('4', Unit.gram),
    components: [
      RecipeComponent(
        id: 'flour',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('10', Unit.gram),
        behavior: ScalingBehavior.proportional,
        rounding: RoundingRule.upToIncrement(Decimal.fromInt(3)),
        note: 'Sift first.',
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'starter-a',
        target: const SubRecipeRef('child'),
        baseQuantity: Quantity.parse('2', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 1,
      ),
      RecipeComponent(
        id: 'starter-b',
        target: const SubRecipeRef('child'),
        baseQuantity: Quantity.parse('3', Unit.gram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 2,
      ),
      RecipeComponent(
        id: 'salt',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        note: 'Season after mixing.',
        displayOrder: 3,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 10),
    preparationNotes: const ['Mix until smooth.'],
  );
  const calculator = ProductionCalculator();
  final result = calculator.calculate(
    recipe: root,
    targetYield: Quantity.parse('10', Unit.gram),
    recipeIndex: {'child': child},
  );
  const roundingWarning = RoundingAdjustedWarning('root', 'flour');
  const manualWarning = ManualComponentWarning('root', 'salt');
  return ProductionRun(
    id: 'run-export',
    createdAt: DateTime.utc(2026, 9, 11, 4, 5, 6),
    recipe: root,
    dependencySnapshot: {'child': child},
    ingredientSnapshot: {
      'flour': Ingredient(
        id: 'flour',
        name: 'Bread flour',
        defaultUnit: Unit.gram,
      ),
      'salt': Ingredient(id: 'salt', name: 'Sea salt', defaultUnit: Unit.gram),
      'packet': Ingredient(
        id: 'packet',
        name: 'Yeast packet',
        defaultUnit: _packet,
      ),
    },
    targetYield: Quantity.parse('10', Unit.gram),
    result: result,
    overrides: {('root', 'salt'): Quantity.parse('7', Unit.gram)},
    acknowledgedWarnings: {
      roundingWarning,
      if (acknowledgeManual) manualWarning,
    },
  );
}

ProductionRun buildProductionSheetRunWithoutNames() {
  final run = buildProductionSheetRun();
  return ProductionRun(
    id: run.id,
    createdAt: run.createdAt,
    recipe: run.recipe,
    dependencySnapshot: const {},
    targetYield: run.targetYield,
    result: run.result,
    overrides: run.overrides,
    acknowledgedWarnings: run.acknowledgedWarnings,
  );
}

ProductionRun runNamed(String name, DateTime createdAt) {
  final recipe = Recipe(
    id: 'named',
    revision: 1,
    name: name,
    baseYield: Quantity.parse('1', Unit.portion),
    components: const [],
    modifiedAt: createdAt,
  );
  return ProductionRun(
    id: 'run-named',
    createdAt: createdAt,
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: Quantity.parse('1', Unit.portion),
    result: const ProductionCalculator().calculate(
      recipe: recipe,
      targetYield: Quantity.parse('1', Unit.portion),
    ),
  );
}
