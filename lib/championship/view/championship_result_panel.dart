import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/view/championship_strings.dart';
import 'package:prep_book/domain/domain.dart';

class ChampionshipResultPanel extends StatelessWidget {
  const ChampionshipResultPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChampionshipDemoCubit>();
    final run = context.watch<ChampionshipDemoCubit>().state.run!;
    final strings = ChampionshipStrings.of(context);
    final batchPlan = run.result.batchPlan;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.resultHeading,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            _ExactBoundary(strings: strings),
            const SizedBox(height: 20),
            Text(
              run.recipe.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(run.targetYield.toString()),
            Text(strings.batches(batchPlan.batchCount)),
            if (batchPlan.fullBatchCount > 0)
              Text(
                strings.fullBatches(
                  batchPlan.fullBatchCount,
                  batchPlan.fullBatchYield,
                ),
              ),
            if (batchPlan.remainderYield case final remainder?)
              Text(strings.remainderBatch(remainder)),
            const SizedBox(height: 20),
            for (final component in run.result.components)
              _ComponentResult(run: run, component: component),
            const SizedBox(height: 20),
            Text(
              strings.warnings,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (run.result.warnings.isEmpty)
              Text(strings.noWarnings)
            else
              for (final warning in run.result.warnings)
                Text('• ${_warningLabel(warning, run)}'),
            const SizedBox(height: 24),
            TextButton(
              key: const ValueKey('result-back'),
              onPressed: cubit.back,
              child: Text(strings.back),
            ),
            OutlinedButton(
              key: const ValueKey('result-reset'),
              onPressed: cubit.reset,
              child: Text(strings.reset),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExactBoundary extends StatelessWidget {
  const _ExactBoundary({required this.strings});

  final ChampionshipStrings strings;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calculate_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    strings.exactCalculation,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(strings.exactBoundary),
          ],
        ),
      ),
    );
  }
}

class _ComponentResult extends StatelessWidget {
  const _ComponentResult({required this.run, required this.component});

  final ProductionRun run;
  final ScaledComponent component;

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    // ChampionshipRecipeMapper emits ingredient references only.
    final ingredientId =
        (component.source.target as IngredientRef).ingredientId;
    final name = run.ingredientSnapshot[ingredientId]?.name ?? ingredientId;
    final total =
        component.total?.displayed.toString() ?? strings.manualAsNeeded;
    String perBatchAmount(int index) =>
        component.perBatch[index]?.displayed.toString() ??
        strings.manualAsNeeded;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(name, style: Theme.of(context).textTheme.titleMedium),
          if (component.source.note case final note?) Text(note),
          const SizedBox(height: 4),
          Text(total, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (var index = 0; index < component.perBatch.length; index += 1)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text('${strings.batch(index)}: ${perBatchAmount(index)}'),
            ),
        ],
      ),
    );
  }
}

String _warningLabel(ProductionWarning warning, ProductionRun run) {
  // The championship mapper creates no rounding or dependency warnings.
  final componentId = (warning as ManualComponentWarning).componentId;
  final component = run.recipe.components.singleWhere(
    (candidate) => candidate.id == componentId,
  );
  final ingredientId = (component.target as IngredientRef).ingredientId;
  return run.ingredientSnapshot[ingredientId]!.name;
}
