import 'package:prep_book/championship/import/championship_recipe_mapper.dart';
import 'package:prep_book/championship/import/recipe_draft_verifier.dart';
import 'package:prep_book/domain/domain.dart';

final class ChampionshipRunBuilder {
  const ChampionshipRunBuilder({
    this.mapper = const ChampionshipRecipeMapper(),
    this.calculator = const ProductionCalculator(maxPlannedBatches: 1000),
  });

  final ChampionshipRecipeMapper mapper;
  final ProductionCalculator calculator;

  ProductionRun build({
    required VerifiedRecipeDraft draft,
    required String targetAmount,
    required String targetUnit,
    required DateTime createdAt,
    required String runId,
  }) {
    if (calculator.maxPlannedBatches != 1000) {
      throw StateError('Championship runs require a 1000-batch limit.');
    }
    final resolvedTargetUnit = mapper.units.resolve(targetUnit);
    if (resolvedTargetUnit == null) {
      throw const FormatException('The target unit is unsupported.');
    }
    final targetYield = Quantity.parse(targetAmount, resolvedTargetUnit);
    final bundle = mapper.map(draft, modifiedAt: createdAt);
    final result = calculator.calculate(
      recipe: bundle.recipe,
      targetYield: targetYield,
    );
    return ProductionRun(
      id: runId,
      createdAt: createdAt,
      recipe: bundle.recipe,
      dependencySnapshot: const {},
      ingredientSnapshot: bundle.ingredientSnapshot,
      targetYield: targetYield,
      result: result,
    );
  }
}
