import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

import 'fakes.dart';

/// A minimal but real [ProductionRun], built through [ProductionCalculator]
/// rather than hand-assembled, so [FakeProductionRunRepository] tests exert
/// the same shape a use case would pass it.
ProductionRun _buildRun({
  required String id,
  required DateTime createdAt,
  required Recipe recipe,
}) {
  final result = const ProductionCalculator().calculate(
    recipe: recipe,
    targetYield: recipe.baseYield,
  );
  return ProductionRun(
    id: id,
    createdAt: createdAt,
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: recipe.baseYield,
    result: result,
  );
}

void main() {
  group('FakeRecipeRepository ordering matches the real repository', () {
    test('listLatestRevisions orders by id, not insertion order', () async {
      final repo = FakeRecipeRepository()
        ..seed(buildRecipe(id: 'zucchini'))
        ..seed(buildRecipe(id: 'apple'))
        ..seed(buildRecipe(id: 'mango'));

      final result = await repo.listLatestRevisions();

      expect(result.map((recipe) => recipe.id), ['apple', 'mango', 'zucchini']);
    });

    test(
      'listLatestRevisionsUsingIngredient orders by id, not insertion order',
      () async {
        final repo = FakeRecipeRepository()
          ..seed(buildRecipe(id: 'zucchini'))
          ..seed(buildRecipe(id: 'apple'))
          ..seed(buildRecipe(id: 'mango'));

        final result = await repo.listLatestRevisionsUsingIngredient('flour');

        expect(result.map((recipe) => recipe.id), [
          'apple',
          'mango',
          'zucchini',
        ]);
      },
    );
  });

  group('FakeProductionRunRepository.listSummaries ordering', () {
    test('breaks a createdAt tie by id ascending', () async {
      final createdAt = DateTime.utc(2026, 9, 8, 12);
      final repo = FakeProductionRunRepository();
      repo.stored['zucchini-run'] = _buildRun(
        id: 'zucchini-run',
        createdAt: createdAt,
        recipe: buildRecipe(id: 'zucchini'),
      );
      repo.stored['apple-run'] = _buildRun(
        id: 'apple-run',
        createdAt: createdAt,
        recipe: buildRecipe(id: 'apple'),
      );

      final summaries = await repo.listSummaries();

      expect(summaries.map((summary) => summary.id), [
        'apple-run',
        'zucchini-run',
      ]);
    });

    test('orders by createdAt descending when timestamps differ', () async {
      final older = DateTime.utc(2026, 9, 8, 12);
      final newer = DateTime.utc(2026, 9, 8, 13);
      final repo = FakeProductionRunRepository();
      repo.stored['older'] = _buildRun(
        id: 'older',
        createdAt: older,
        recipe: buildRecipe(id: 'r1'),
      );
      repo.stored['newer'] = _buildRun(
        id: 'newer',
        createdAt: newer,
        recipe: buildRecipe(id: 'r2'),
      );

      final summaries = await repo.listSummaries();

      expect(summaries.map((summary) => summary.id), ['newer', 'older']);
    });
  });

  group('FakeProductionRunRepository.save matches the real ABORT conflict', () {
    test('a second save under the same run id throws', () async {
      final repo = FakeProductionRunRepository();
      final recipe = buildRecipe(id: 'a');
      final first = _buildRun(
        id: 'run-1',
        createdAt: DateTime.utc(2026, 9, 8, 12),
        recipe: recipe,
      );
      final second = _buildRun(
        id: 'run-1',
        createdAt: DateTime.utc(2026, 9, 8, 13),
        recipe: recipe,
      );
      await repo.save(first);

      await expectLater(repo.save(second), throwsStateError);
      // The first save is left standing, not silently replaced.
      expect(await repo.findById('run-1'), same(first));
    });
  });
}
