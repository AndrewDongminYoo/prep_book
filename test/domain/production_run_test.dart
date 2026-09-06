import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe soup({String name = 'Soup'}) {
  return Recipe(
    id: 'soup',
    revision: 1,
    name: name,
    baseYield: Quantity.parse('10', Unit.portion),
    components: [
      RecipeComponent(
        id: 'stock',
        target: const IngredientRef('stock'),
        baseQuantity: Quantity.parse('2', Unit.liter),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'pepper',
        target: const IngredientRef('pepper'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

/// A recipe with two independent blocking warnings, so a test can prove
/// [ProductionRun.isFinalizable] needs every one of them acknowledged and
/// not merely one — `every` and `any` agree whenever there is only a single
/// blocking warning to check.
Recipe twiceManualSoup() {
  return Recipe(
    id: 'soup',
    revision: 1,
    name: 'Soup',
    baseYield: Quantity.parse('10', Unit.portion),
    components: [
      RecipeComponent(
        id: 'pepper',
        target: const IngredientRef('pepper'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 0,
      ),
      RecipeComponent(
        id: 'salt',
        target: const IngredientRef('salt'),
        baseQuantity: null,
        behavior: ScalingBehavior.manual,
        displayOrder: 1,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

/// A dependency this test's runs reference through [ProductionRun]'s
/// `dependencySnapshot`, distinct from the recipe the run itself scales.
Recipe brothRecipe({bool isArchived = false}) {
  return Recipe(
    id: 'broth',
    revision: 1,
    name: 'Broth',
    baseYield: Quantity.parse('5', Unit.liter),
    isArchived: isArchived,
    components: [
      RecipeComponent(
        id: 'water',
        target: const IngredientRef('water'),
        baseQuantity: Quantity.parse('5', Unit.liter),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

/// A recipe whose calculation raises no blocking warning, for the branch of
/// [ProductionRun.isFinalizable] where `every` is satisfied by having
/// nothing to acknowledge rather than by acknowledging something.
Recipe plainStock() {
  return Recipe(
    id: 'plain',
    revision: 1,
    name: 'Plain stock',
    baseYield: Quantity.parse('10', Unit.portion),
    components: [
      RecipeComponent(
        id: 'stock',
        target: const IngredientRef('stock'),
        baseQuantity: Quantity.parse('2', Unit.liter),
        behavior: ScalingBehavior.proportional,
        displayOrder: 0,
      ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

ProductionRun buildRunFor(
  Recipe recipe,
  Quantity target, {
  String id = 'run-1',
}) {
  const calculator = ProductionCalculator();
  return ProductionRun(
    id: id,
    createdAt: DateTime.utc(2026, 9, 6, 9),
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: target,
    result: calculator.calculate(recipe: recipe, targetYield: target),
  );
}

ProductionRun buildRun() =>
    buildRunFor(soup(), Quantity.parse('20', Unit.portion));

void main() {
  group('ProductionRun', () {
    test('records the recipe revision it was computed from', () {
      final run = buildRun();
      expect(run.recipeId, 'soup');
      expect(run.recipeRevision, 1);
    });

    test('a later recipe edit does not change the snapshot', () {
      final run = buildRun();
      final edited = soup(name: 'Renamed soup');

      expect(edited.name, 'Renamed soup');
      expect(run.recipe.name, 'Soup');
      expect(
        run.result.components.first.total!.exact,
        Quantity.parse('4', Unit.liter),
      );
    });

    test('is not finalizable while a blocking warning stands', () {
      expect(buildRun().isFinalizable, isFalse);
    });

    test(
      'becomes finalizable once every blocking warning is acknowledged',
      () {
        final run = buildRun();
        final acknowledged = run.acknowledge(
          const ManualComponentWarning('soup', 'pepper'),
        );
        expect(acknowledged.isFinalizable, isTrue);
        expect(run.isFinalizable, isFalse);
      },
    );

    test(
      'stays unfinalizable until every blocking warning is acknowledged, '
      'not merely one of them',
      () {
        final run = buildRunFor(
          twiceManualSoup(),
          Quantity.parse('20', Unit.portion),
          id: 'run-4',
        );
        expect(
          run.result.warnings.where((w) => w.isBlocking).length,
          2,
        );

        final partiallyAcknowledged = run.acknowledge(
          const ManualComponentWarning('soup', 'pepper'),
        );
        expect(partiallyAcknowledged.isFinalizable, isFalse);

        final fullyAcknowledged = partiallyAcknowledged.acknowledge(
          const ManualComponentWarning('soup', 'salt'),
        );
        expect(fullyAcknowledged.isFinalizable, isTrue);
      },
    );

    test(
      'is finalizable when the calculation raised no blocking warning',
      () {
        final run = buildRunFor(
          plainStock(),
          Quantity.parse('20', Unit.portion),
          id: 'run-2',
        );
        expect(run.result.hasBlockingWarnings, isFalse);
        expect(run.isFinalizable, isTrue);
      },
    );

    test(
      'is finalizable while a non-blocking warning stands unacknowledged',
      () {
        // Distinguishes "every blocking warning is acknowledged" from a
        // broken filter that requires every warning, blocking or not, to be
        // acknowledged: this run carries a RoundingAdjustedWarning (not
        // blocking) that is never acknowledged, so isFinalizable must stay
        // true.
        final recipe = Recipe(
          id: 'buns',
          revision: 1,
          name: 'Buns',
          baseYield: Quantity.parse('10', Unit.portion),
          components: [
            RecipeComponent(
              id: 'eggs',
              target: const IngredientRef('egg'),
              baseQuantity: Quantity.parse('3', Unit.count('item')),
              behavior: ScalingBehavior.proportional,
              rounding: RoundingRule.upToIncrement(Decimal.one),
              displayOrder: 0,
            ),
          ],
          modifiedAt: DateTime.utc(2026, 9, 6),
        );
        final run = buildRunFor(
          recipe,
          Quantity.parse('15', Unit.portion),
          id: 'run-3',
        );

        expect(
          run.result.warnings,
          contains(const RoundingAdjustedWarning('buns', 'eggs')),
        );
        expect(run.result.hasBlockingWarnings, isFalse);
        expect(run.isFinalizable, isTrue);
      },
    );

    test('records an operator override without touching the result', () {
      final run = buildRun();
      final overridden = run.override(
        recipeId: 'soup',
        componentId: 'stock',
        value: Quantity.parse('5', Unit.liter),
      );

      expect(
        overridden.overrides[('soup', 'stock')],
        Quantity.parse('5', Unit.liter),
      );
      expect(
        overridden.result.components.first.total!.exact,
        Quantity.parse('4', Unit.liter),
      );
      expect(run.overrides, isEmpty);
    });

    test(
      'keys an override by recipe and component so a same-named component '
      'in another recipe never collides',
      () {
        final run = buildRun();
        final overridden = run
            .override(
              recipeId: 'soup',
              componentId: 'stock',
              value: Quantity.parse('5', Unit.liter),
            )
            .override(
              recipeId: 'broth',
              componentId: 'stock',
              value: Quantity.parse('9', Unit.liter),
            );

        expect(
          overridden.overrides[('soup', 'stock')],
          Quantity.parse('5', Unit.liter),
        );
        expect(
          overridden.overrides[('broth', 'stock')],
          Quantity.parse('9', Unit.liter),
        );
      },
    );

    test(
      'keeps acknowledgements and overrides independent of each other, '
      'regardless of which is recorded first',
      () {
        const acknowledgement = ManualComponentWarning('soup', 'pepper');
        final value = Quantity.parse('5', Unit.liter);

        final acknowledgeThenOverride = buildRun()
            .acknowledge(acknowledgement)
            .override(recipeId: 'soup', componentId: 'stock', value: value);
        expect(acknowledgeThenOverride.overrides[('soup', 'stock')], value);
        expect(acknowledgeThenOverride.isFinalizable, isTrue);

        final overrideThenAcknowledge = buildRun()
            .override(recipeId: 'soup', componentId: 'stock', value: value)
            .acknowledge(acknowledgement);
        expect(overrideThenAcknowledge.overrides[('soup', 'stock')], value);
        expect(overrideThenAcknowledge.isFinalizable, isTrue);
      },
    );

    test(
      'copies the collections it is constructed with, rather than '
      "aliasing the caller's map or set",
      () {
        // A wrong implementation that wraps the caller's own container in
        // an unmodifiable view (instead of copying it first) would still
        // pass the "exposes unmodifiable collections" test below — direct
        // writes through `run.overrides` etc. would still throw — while
        // leaking every mutation the caller makes to its original
        // afterward. Mutating the caller's originals here, after
        // construction, is what tells the two implementations apart.
        final snapshot = <String, Recipe>{'broth': brothRecipe()};
        final overridesMap = <OverrideKey, Quantity>{
          ('soup', 'stock'): Quantity.parse('5', Unit.liter),
        };
        final acknowledged = <ProductionWarning>{
          const ManualComponentWarning('soup', 'pepper'),
        };

        final run = ProductionRun(
          id: 'run-5',
          createdAt: DateTime.utc(2026, 9, 6, 9),
          recipe: soup(),
          dependencySnapshot: snapshot,
          targetYield: Quantity.parse('20', Unit.portion),
          result: const ProductionCalculator().calculate(
            recipe: soup(),
            targetYield: Quantity.parse('20', Unit.portion),
          ),
          overrides: overridesMap,
          acknowledgedWarnings: acknowledged,
        );

        snapshot['broth'] = brothRecipe(isArchived: true);
        snapshot['extra'] = soup();
        overridesMap[('soup', 'stock')] = Quantity.parse('9', Unit.liter);
        overridesMap[('broth', 'stock')] = Quantity.parse('1', Unit.liter);
        acknowledged.clear();

        expect(run.dependencySnapshot['broth']!.isArchived, isFalse);
        expect(run.dependencySnapshot.containsKey('extra'), isFalse);
        expect(
          run.overrides[('soup', 'stock')],
          Quantity.parse('5', Unit.liter),
        );
        expect(run.overrides.containsKey(('broth', 'stock')), isFalse);
        expect(
          run.acknowledgedWarnings,
          contains(const ManualComponentWarning('soup', 'pepper')),
        );
      },
    );

    test('exposes unmodifiable collections', () {
      final run = buildRun();
      expect(
        () => run.overrides[('soup', 'stock')] = Quantity.parse(
          '1',
          Unit.liter,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => run.acknowledgedWarnings.add(
          const ManualComponentWarning('soup', 'pepper'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => run.dependencySnapshot['soup'] = run.recipe,
        throwsUnsupportedError,
      );
    });
  });
}
