import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

Recipe recipeWith(String id, List<String> subRecipeIds) {
  return Recipe(
    id: id,
    revision: 1,
    name: id,
    baseYield: Quantity.parse('1', Unit.portion),
    components: [
      for (var i = 0; i < subRecipeIds.length; i++)
        RecipeComponent(
          id: '$id-c$i',
          target: SubRecipeRef(subRecipeIds[i]),
          baseQuantity: Quantity.parse('1', Unit.portion),
          behavior: ScalingBehavior.proportional,
          displayOrder: i,
        ),
    ],
    modifiedAt: DateTime.utc(2026, 9, 6),
  );
}

void main() {
  group('RecipeDependencyGraph', () {
    test('accepts an acyclic graph', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['b']),
        'b': recipeWith('b', ['c']),
        'c': recipeWith('c', []),
      });
      expect(graph.findCycleFrom('a'), isNull);
      expect(() => graph.assertResolvable('a'), returnsNormally);
    });

    test('detects a direct cycle', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['a']),
      });
      expect(graph.findCycleFrom('a'), ['a', 'a']);
    });

    test('detects an indirect cycle and names the path', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['b']),
        'b': recipeWith('b', ['c']),
        'c': recipeWith('c', ['a']),
      });
      expect(graph.findCycleFrom('a'), ['a', 'b', 'c', 'a']);
    });

    test('throws with the cycle path attached', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['b']),
        'b': recipeWith('b', ['a']),
      });
      expect(
        () => graph.assertResolvable('a'),
        throwsA(
          isA<RecipeCycleError>().having(
            (e) => e.path,
            'path',
            ['a', 'b', 'a'],
          ),
        ),
      );
    });

    test('reports a missing dependency', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['ghost']),
      });
      expect(
        () => graph.assertResolvable('a'),
        throwsA(
          isA<MissingDependencyError>().having(
            (e) => e.missingId,
            'missingId',
            'ghost',
          ),
        ),
      );
    });

    test('reports a missing root', () {
      final graph = RecipeDependencyGraph(const {});
      expect(
        () => graph.assertResolvable('a'),
        throwsA(isA<MissingDependencyError>()),
      );
    });

    test('visits a shared dependency once', () {
      final graph = RecipeDependencyGraph({
        'a': recipeWith('a', ['b', 'c']),
        'b': recipeWith('b', ['d']),
        'c': recipeWith('c', ['d']),
        'd': recipeWith('d', []),
      });
      expect(graph.findCycleFrom('a'), isNull);
      expect(() => graph.assertResolvable('a'), returnsNormally);
    });
  });
}
