import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/cubit/championship_demo_state.dart';
import 'package:prep_book/championship/import/unit_alias_resolver.dart';
import 'package:prep_book/championship/view/championship_strings.dart';

class ChampionshipTargetPanel extends StatelessWidget {
  const ChampionshipTargetPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChampionshipDemoCubit>();
    final state = context.watch<ChampionshipDemoCubit>().state;
    final verified = state.verified!;
    final strings = ChampionshipStrings.of(context);
    final units = _compatibleUnits(verified.recipe.baseYield.unit);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.targetHeading,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.verified_outlined),
              title: Text(strings.verifiedRecipe),
              subtitle: Text(
                '${verified.recipe.name}\n'
                '${verified.recipe.baseYield.amount} '
                '${verified.recipe.baseYield.unit}',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const ValueKey('target-amount-input'),
              initialValue: state.targetAmount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(labelText: strings.targetAmount),
              onChanged: cubit.setTargetAmount,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              key: const ValueKey('target-unit-input'),
              initialValue: units.contains(state.targetUnit)
                  ? state.targetUnit
                  : units.first,
              isExpanded: true,
              decoration: InputDecoration(labelText: strings.targetUnit),
              items: [
                for (final unit in units)
                  DropdownMenuItem(
                    value: unit,
                    child: Text(unit, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) cubit.setTargetUnit(value);
              },
            ),
            if (state.targetFailure case final failure?) ...[
              const SizedBox(height: 16),
              Text(switch (failure) {
                ChampionshipTargetFailure.invalidTarget =>
                  strings.invalidTarget,
                ChampionshipTargetFailure.batchLimit => strings.batchLimit,
              }, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('target-calculate'),
              onPressed: state.targetAmount.trim().isEmpty
                  ? null
                  : cubit.calculate,
              icon: const Icon(Icons.calculate_outlined),
              label: Text(strings.calculate),
            ),
            TextButton(
              key: const ValueKey('target-back'),
              onPressed: cubit.back,
              child: Text(strings.back),
            ),
          ],
        ),
      ),
    );
  }
}

List<String> _compatibleUnits(String source) {
  const resolver = UnitAliasResolver();
  final sourceUnit = resolver.resolve(source)!;
  return [
    for (final symbol in UnitAliasResolver.symbols)
      if (sourceUnit.canConvertTo(resolver.resolve(symbol)!)) symbol,
  ];
}
