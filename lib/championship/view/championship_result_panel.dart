import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/view/championship_strings.dart';
import 'package:prep_book/domain/domain.dart';

typedef OpenChampionshipProductionSheet =
    Future<void> Function(BuildContext context, ProductionRun run);

class ChampionshipResultPanel extends StatelessWidget {
  const ChampionshipResultPanel({required this.openProductionSheet, super.key});

  final OpenChampionshipProductionSheet openProductionSheet;

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
            Semantics(
              key: const ValueKey('result-summary-semantics'),
              container: true,
              explicitChildNodes: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      strings.resultHeading,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    run.recipe.name,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  _ResultOverview(
                    target: run.targetYield.toString(),
                    batches: strings.batches(batchPlan.batchCount),
                    targetLabel: strings.target,
                  ),
                  const SizedBox(height: 20),
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
                  _ExactBoundary(strings: strings),
                ],
              ),
            ),
            const SizedBox(height: 20),
            for (final (index, component) in run.result.components.indexed)
              _ComponentResult(index: index, run: run, component: component),
            const SizedBox(height: 20),
            Semantics(
              key: const ValueKey('result-warnings-semantics'),
              container: true,
              explicitChildNodes: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    header: true,
                    child: Text(
                      strings.warnings,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (run.result.warnings.isEmpty)
                    Text(strings.noWarnings)
                  else
                    for (final warning in run.result.warnings)
                      Text('• ${_warningLabel(warning, run)}'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Semantics(
              key: const ValueKey('result-actions-semantics'),
              container: true,
              explicitChildNodes: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('result-production-sheet'),
                    onPressed: () async {
                      try {
                        await openProductionSheet(context, run);
                      } on Object {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(strings.productionSheetFailure),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: Text(strings.productionSheet),
                  ),
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
          ],
        ),
      ),
    );
  }
}

class _ResultOverview extends StatelessWidget {
  const _ResultOverview({
    required this.target,
    required this.batches,
    required this.targetLabel,
  });

  final String target;
  final String batches;
  final String targetLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.primaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(targetLabel, style: textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              target,
              key: const ValueKey('result-target-value'),
              style: textTheme.displaySmall?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              batches,
              key: const ValueKey('result-batch-count'),
              style: textTheme.titleLarge?.copyWith(
                color: colors.onPrimaryContainer,
              ),
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
  const _ComponentResult({
    required this.index,
    required this.run,
    required this.component,
  });

  final int index;
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
    final groups = _groupBatches(component.perBatch);
    return Semantics(
      key: ValueKey('result-component-$index-semantics'),
      container: true,
      explicitChildNodes: true,
      label: name,
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Text(name, style: Theme.of(context).textTheme.titleMedium),
            ),
            if (component.source.note case final note?) Text(note),
            const SizedBox(height: 4),
            Text(total, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final group in groups)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  strings.batchQuantity(
                    first: group.first,
                    last: group.last,
                    amount:
                        group.amount?.displayed.toString() ??
                        strings.manualAsNeeded,
                    manual: group.amount == null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

List<({int first, int last, ScaledQuantity? amount})> _groupBatches(
  List<ScaledQuantity?> batches,
) {
  final groups = <({int first, int last, ScaledQuantity? amount})>[];
  for (var index = 0; index < batches.length; index += 1) {
    final amount = batches[index];
    final open = groups.isEmpty ? null : groups.last;
    if (open != null && _sameAmount(open.amount, amount)) {
      groups[groups.length - 1] = (
        first: open.first,
        last: index + 1,
        amount: amount,
      );
    } else {
      groups.add((first: index + 1, last: index + 1, amount: amount));
    }
  }
  return groups;
}

bool _sameAmount(ScaledQuantity? left, ScaledQuantity? right) {
  if (left == null || right == null) return left == null && right == null;
  return left.exact == right.exact && left.displayed == right.displayed;
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
