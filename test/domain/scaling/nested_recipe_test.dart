import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe dough({bool isArchived = false}) {
  return Recipe(
    id: 'dough',
    revision: 1,
    name: 'Dough',
    baseYield: Quantity.parse('2', Unit.kilogram),
    isArchived: isArchived,
    components: [
      RecipeComponent(
        id: 'dough-flour',
        target: const IngredientRef('flour'),
        baseQuantity: Quantity.parse('1.2', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'dough-salt',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

Recipe pie({bool isArchived = false}) {
  return Recipe(
    id: 'pie',
    revision: 1,
    name: 'Pie',
    baseYield: Quantity.parse('4', Unit.portion),
    isArchived: isArchived,
    components: [
      RecipeComponent(
        id: 'pie-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

/// A pie whose dough line rounds up for display, so its exact and displayed
/// totals diverge — this discriminates which one a sub-recipe is expanded
/// against.
Recipe roundedPie() {
  return Recipe(
    id: 'rounded-pie',
    revision: 1,
    name: 'Rounded pie',
    baseYield: Quantity.parse('4', Unit.portion),
    components: [
      RecipeComponent(
        id: 'rounded-pie-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: Quantity.parse('0.9', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        rounding: RoundingRule.upToIncrement(Decimal.parse('0.5')),
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

/// A pie that references the same sub-recipe twice, so a warning lifted
/// from that sub-recipe would otherwise be duplicated in the parent.
Recipe twicePie() {
  return Recipe(
    id: 'twice-pie',
    revision: 1,
    name: 'Twice pie',
    baseYield: Quantity.parse('4', Unit.portion),
    components: [
      RecipeComponent(
        id: 'top-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'bottom-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

/// A pie with its own manual component sharing an id with a manual
/// component in the sub-recipe it references — same component id, two
/// different recipes. The manual component is listed before the sub-recipe
/// reference. Since a component's own warning and a lifted one both go
/// through the same de-duplication path, this order has no bearing on the
/// outcome; [saltyPieReversed] lists the two lines the other way to pin
/// that the order really doesn't matter, rather than leaving it assumed.
Recipe saltyPie() {
  return Recipe(
    id: 'salty-pie',
    revision: 1,
    name: 'Salty pie',
    baseYield: Quantity.parse('4', Unit.portion),
    components: [
      RecipeComponent(
        id: 'dough-salt',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'pie-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

/// The same collision as [saltyPie], with the sub-recipe line listed before
/// the manual one.
Recipe saltyPieReversed() {
  return Recipe(
    id: 'salty-pie-reversed',
    revision: 1,
    name: 'Salty pie (reversed)',
    baseYield: Quantity.parse('4', Unit.portion),
    components: [
      RecipeComponent(
        id: 'pie-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: Quantity.parse('1', Unit.kilogram),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'dough-salt',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

/// A pie whose dough line names a sub-recipe but is manual, so it carries
/// no quantity and there is nothing to expand the sub-recipe against.
Recipe manualDoughPie() {
  return Recipe(
    id: 'manual-dough-pie',
    revision: 1,
    name: 'Manual dough pie',
    baseYield: Quantity.parse('4', Unit.portion),
    components: [
      RecipeComponent(
        id: 'pie-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

/// The same manual sub-recipe reference twice over, so an archived target
/// would be reported twice without de-duplication.
Recipe twiceManualDoughPie() {
  return Recipe(
    id: 'twice-manual-dough-pie',
    revision: 1,
    name: 'Twice manual dough pie',
    baseYield: Quantity.parse('4', Unit.portion),
    components: [
      RecipeComponent(
        id: 'top-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'bottom-dough',
        target: const SubRecipeRef('dough'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  const calculator = ProductionCalculator();

  group('nested recipes', () {
    test('expands a sub-recipe against the parent quantity', () {
      final result = calculator.calculate(
        recipe: pie(),
        targetYield: Quantity.parse('8', Unit.portion),
        recipeIndex: {'dough': dough(), 'pie': pie()},
      );

      final line = result.components.single;
      expect(line.total!.exact, Quantity.parse('2', Unit.kilogram));

      final nested = line.subRecipe!;
      expect(nested.scaleRatio, Rational.one);
      expect(
        nested.components.first.total!.exact,
        Quantity.parse('1.2', Unit.kilogram),
      );
      expect(
        result.warnings,
        isNot(contains(isA<ArchivedDependencyWarning>())),
      );
    });

    test('expands the sub-recipe against the displayed total, not the '
        'exact one', () {
      // Exact: 0.9kg * (8/4) = 1.8kg. Displayed: rounded up to 2.0kg. Dough's
      // base yield is 2kg, so only the displayed value scales it to exactly
      // Rational.one; the exact value would scale it to 9/10.
      final result = calculator.calculate(
        recipe: roundedPie(),
        targetYield: Quantity.parse('8', Unit.portion),
        recipeIndex: {'dough': dough(), 'rounded-pie': roundedPie()},
      );

      final line = result.components.single;
      expect(line.total!.exact, Quantity.parse('1.8', Unit.kilogram));
      expect(line.total!.displayed, Quantity.parse('2', Unit.kilogram));

      final nested = line.subRecipe!;
      expect(nested.scaleRatio, Rational.one);
      expect(
        nested.components.first.total!.exact,
        Quantity.parse('1.2', Unit.kilogram),
      );
    });

    test('lifts a nested blocking warning into the parent', () {
      final result = calculator.calculate(
        recipe: pie(),
        targetYield: Quantity.parse('8', Unit.portion),
        recipeIndex: {'dough': dough(), 'pie': pie()},
      );
      expect(result.warnings, contains(isA<ManualComponentWarning>()));
      expect(result.hasBlockingWarnings, isTrue);
    });

    test(
      'de-duplicates a warning lifted from a sub-recipe referenced twice',
      () {
        final result = calculator.calculate(
          recipe: twicePie(),
          targetYield: Quantity.parse('4', Unit.portion),
          recipeIndex: {'dough': dough()},
        );

        expect(
          result.warnings.whereType<ManualComponentWarning>(),
          hasLength(1),
        );

        final top = result.components[0];
        final bottom = result.components[1];
        expect(top.total!.exact, Quantity.parse('1', Unit.kilogram));
        expect(bottom.total!.exact, Quantity.parse('1', Unit.kilogram));
        expect(
          top.subRecipe!.components.first.total!.exact,
          Quantity.parse('0.6', Unit.kilogram),
        );
        expect(
          bottom.subRecipe!.components.first.total!.exact,
          Quantity.parse('0.6', Unit.kilogram),
        );
      },
    );

    test('a manual component sharing an id with one in its sub-recipe still '
        'produces two distinct warnings', () {
      final result = calculator.calculate(
        recipe: saltyPie(),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough()},
      );

      // Asserted as a raw count plus the distinguishing field (rather than
      // via ManualComponentWarning's own equality) so this test still
      // fails correctly if that equality itself is ever the thing that
      // regresses.
      final manualWarnings = result.warnings
          .whereType<ManualComponentWarning>()
          .toList();
      expect(manualWarnings, hasLength(2));
      expect(
        manualWarnings.map((w) => w.recipeId),
        unorderedEquals(['salty-pie', 'dough']),
      );
    });

    test('the same collision still produces two distinct warnings when the '
        'sub-recipe line is listed first', () {
      final result = calculator.calculate(
        recipe: saltyPieReversed(),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough()},
      );

      final manualWarnings = result.warnings
          .whereType<ManualComponentWarning>()
          .toList();
      expect(manualWarnings, hasLength(2));
      expect(
        manualWarnings.map((w) => w.recipeId),
        unorderedEquals(['salty-pie-reversed', 'dough']),
      );
    });

    test('warns when a dependency is archived', () {
      final result = calculator.calculate(
        recipe: pie(),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough(isArchived: true), 'pie': pie()},
      );
      expect(
        result.warnings,
        contains(const ArchivedDependencyWarning('dough')),
      );
      expect(result.hasBlockingWarnings, isTrue);
    });

    test('warns when the run is computed straight from an archived recipe', () {
      final result = calculator.calculate(
        recipe: pie(isArchived: true),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough(), 'pie': pie(isArchived: true)},
      );
      expect(result.warnings, contains(const ArchivedDependencyWarning('pie')));
      expect(result.hasBlockingWarnings, isTrue);
    });

    test('reports both when the run is computed from an archived recipe that '
        'also references an archived child, without collapsing them since '
        'their recipe ids differ', () {
      final result = calculator.calculate(
        recipe: pie(isArchived: true),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {
          'dough': dough(isArchived: true),
          'pie': pie(isArchived: true),
        },
      );

      final archivedWarnings = result.warnings
          .whereType<ArchivedDependencyWarning>()
          .toList();
      expect(archivedWarnings, hasLength(2));
      expect(
        archivedWarnings.map((w) => w.recipeId),
        unorderedEquals(['pie', 'dough']),
      );
    });

    test('de-duplicates an archived-dependency warning when the sub-recipe is '
        'referenced twice', () {
      final result = calculator.calculate(
        recipe: twicePie(),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough(isArchived: true)},
      );

      expect(
        result.warnings.whereType<ArchivedDependencyWarning>(),
        hasLength(1),
      );
      expect(
        result.warnings,
        contains(const ArchivedDependencyWarning('dough')),
      );
    });

    test('warns that an archived sub-recipe is referenced by a manual line, '
        'which has no total to expand it against', () {
      final result = calculator.calculate(
        recipe: manualDoughPie(),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough(isArchived: true)},
      );

      expect(
        result.warnings,
        contains(const ArchivedDependencyWarning('dough')),
      );
      expect(
        result.warnings,
        contains(const ManualComponentWarning('manual-dough-pie', 'pie-dough')),
      );
      expect(result.hasBlockingWarnings, isTrue);
      // The line is still not expanded: there is no quantity to scale the
      // sub-recipe to, so only its archived identity is reported.
      expect(result.components.single.subRecipe, isNull);
    });

    test('does not raise an archived warning for a manual line whose '
        'sub-recipe is live', () {
      final result = calculator.calculate(
        recipe: manualDoughPie(),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough()},
      );

      expect(
        result.warnings,
        contains(const ManualComponentWarning('manual-dough-pie', 'pie-dough')),
      );
      expect(
        result.warnings,
        isNot(contains(isA<ArchivedDependencyWarning>())),
      );
    });

    test('de-duplicates an archived-dependency warning raised by two manual '
        'lines naming the same sub-recipe', () {
      final result = calculator.calculate(
        recipe: twiceManualDoughPie(),
        targetYield: Quantity.parse('4', Unit.portion),
        recipeIndex: {'dough': dough(isArchived: true)},
      );

      expect(
        result.warnings.whereType<ArchivedDependencyWarning>(),
        hasLength(1),
      );
      expect(result.warnings.whereType<ManualComponentWarning>(), hasLength(2));
    });

    test('rejects a cycle before calculating', () {
      final a = Recipe(
        id: 'a',
        revision: 1,
        name: 'A',
        baseYield: Quantity.parse('1', Unit.portion),
        components: [
          RecipeComponent(
            id: 'a-b',
            target: const SubRecipeRef('a'),
            baseQuantity: Quantity.parse('1', Unit.portion),
            behavior: ScalingBehavior.proportional,
            displayOrder: 0,
          ),
        ],
        modifiedAt: DateTime.utc(2026, 9, 6),
      );
      expect(
        () => calculator.calculate(
          recipe: a,
          targetYield: Quantity.parse('2', Unit.portion),
          recipeIndex: {'a': a},
        ),
        throwsA(isA<RecipeCycleError>()),
      );
    });

    test('rejects a missing dependency', () {
      expect(
        () => calculator.calculate(
          recipe: pie(),
          targetYield: Quantity.parse('4', Unit.portion),
          recipeIndex: {'pie': pie()},
        ),
        throwsA(isA<MissingDependencyError>()),
      );
    });
  });
}
