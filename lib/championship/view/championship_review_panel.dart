import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/championship/model/review_recipe_draft.dart';
import 'package:prep_book/championship/view/championship_strings.dart';

const _supportedUnits = <String>[
  '',
  'mg',
  'g',
  'kg',
  'ml',
  'L',
  'tsp',
  'tbsp',
  'portion',
  'piece',
  'tray',
];

class ChampionshipReviewPanel extends StatelessWidget {
  const ChampionshipReviewPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChampionshipDemoCubit>();
    final state = context.watch<ChampionshipDemoCubit>().state;
    final draft = state.review!;
    final strings = ChampionshipStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.reviewHeading,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(strings.reviewIntro),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const ValueKey('review-confirm-all'),
              onPressed: cubit.confirmAllUnambiguous,
              icon: const Icon(Icons.done_all),
              label: Text(strings.confirmAll),
            ),
            const SizedBox(height: 24),
            _SectionHeading(strings.recipeDetails),
            _StringReviewField(
              path: 'recipe.name',
              label: strings.recipeName,
              field: draft.recipe.name,
              onEdit: (value) =>
                  cubit.updateReview((review) => review.editRecipeName(value)),
              onConfirm: () =>
                  cubit.updateReview((review) => review.confirmRecipeName()),
            ),
            _StringReviewField(
              path: 'recipe.baseYield.amount',
              label: strings.baseYieldAmount,
              field: draft.recipe.baseYield.amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              onEdit: (value) => cubit.updateReview(
                (review) => review.editBaseYieldAmount(value),
              ),
              onConfirm: () => cubit.updateReview(
                (review) => review.confirmBaseYieldAmount(),
              ),
            ),
            _UnitReviewField(
              path: 'recipe.baseYield.unit',
              label: strings.baseYieldUnit,
              field: draft.recipe.baseYield.unit,
              resolvedValue: draft.units
                  .resolve(draft.recipe.baseYield.unit.value)
                  ?.symbol,
              onEdit: (value) => cubit.updateReview(
                (review) => review.editBaseYieldUnit(value),
              ),
              onConfirm: () =>
                  cubit.updateReview((review) => review.confirmBaseYieldUnit()),
            ),
            if (draft.recipe.maxBatchYield case final maximum?) ...[
              _StringReviewField(
                path: 'recipe.maxBatchYield.amount',
                label: strings.maxBatchAmount,
                field: maximum.amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onEdit: (value) => cubit.updateReview(
                  (review) => review.editMaxBatchYieldAmount(value),
                ),
                onConfirm: () => cubit.updateReview(
                  (review) => review.confirmMaxBatchYieldAmount(),
                ),
              ),
              _UnitReviewField(
                path: 'recipe.maxBatchYield.unit',
                label: strings.maxBatchUnit,
                field: maximum.unit,
                resolvedValue: draft.units.resolve(maximum.unit.value)?.symbol,
                onEdit: (value) => cubit.updateReview(
                  (review) => review.editMaxBatchYieldUnit(value),
                ),
                onConfirm: () => cubit.updateReview(
                  (review) => review.confirmMaxBatchYieldUnit(),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('recipe.maxBatchYield.remove'),
                onPressed: () => cubit.updateReview(
                  (review) => review.removeMaxBatchYield(),
                ),
                icon: const Icon(Icons.remove_circle_outline),
                label: Text(strings.removeMaximumBatch),
              ),
            ] else
              _AbsentMaximumReview(
                confirmed: draft.recipe.isMaxBatchYieldAbsentConfirmed,
                onConfirm: () => cubit.updateReview(
                  (review) => review.confirmMaxBatchYieldAbsent(),
                ),
              ),
            for (
              var index = 0;
              index < draft.recipe.preparationNotes.length;
              index += 1
            )
              _StringReviewField(
                path: 'recipe.preparationNotes[$index]',
                label: strings.preparationNote(index),
                field: draft.recipe.preparationNotes[index],
                onEdit: (value) => cubit.updateReview(
                  (review) => review.editPreparationNote(index, value),
                ),
                onConfirm: () => cubit.updateReview(
                  (review) => review.confirmPreparationNote(index),
                ),
              ),
            const SizedBox(height: 12),
            for (var index = 0; index < draft.components.length; index += 1)
              _ComponentReview(
                index: index,
                component: draft.components[index],
              ),
            if (state.reviewIssues.isNotEmpty) ...[
              const SizedBox(height: 16),
              _IssueSummary(issues: state.reviewIssues),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('review-continue'),
              onPressed: cubit.continueToTarget,
              icon: const Icon(Icons.arrow_forward),
              label: Text(strings.continueToTarget),
            ),
            TextButton(
              key: const ValueKey('review-back'),
              onPressed: cubit.back,
              child: Text(strings.back),
            ),
          ],
        ),
      ),
    );
  }
}

class _ComponentReview extends StatelessWidget {
  const _ComponentReview({required this.index, required this.component});

  final int index;
  final ReviewRecipeComponent component;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChampionshipDemoCubit>();
    final draft = context.watch<ChampionshipDemoCubit>().state.review!;
    final strings = ChampionshipStrings.of(context);
    final path = 'components[$index]';
    final isManual = component.behavior.value == DraftScalingBehavior.manual;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 40),
        _SectionHeading(strings.component(index)),
        _StringReviewField(
          path: '$path.name',
          label: strings.componentName,
          field: component.name,
          onEdit: (value) => cubit.updateReview(
            (review) => review.editComponentName(index, value),
          ),
          onConfirm: () => cubit.updateReview(
            (review) => review.confirmComponentName(index),
          ),
        ),
        if (isManual) ...[
          _ReadOnlyManualField(label: strings.amount, field: component.amount),
          _ReadOnlyManualField(label: strings.unit, field: component.unit),
        ] else ...[
          _StringReviewField(
            path: '$path.amount',
            label: strings.amount,
            field: component.amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onEdit: (value) => cubit.updateReview(
              (review) => review.editComponentAmount(index, value),
            ),
            onConfirm: () => cubit.updateReview(
              (review) => review.confirmComponentAmount(index),
            ),
          ),
          _UnitReviewField(
            path: '$path.unit',
            label: strings.unit,
            field: component.unit,
            resolvedValue: draft.units.resolve(component.unit.value)?.symbol,
            onEdit: (value) => cubit.updateReview(
              (review) => review.editComponentUnit(index, value),
            ),
            onConfirm: () => cubit.updateReview(
              (review) => review.confirmComponentUnit(index),
            ),
          ),
        ],
        _BehaviorReviewField(
          path: '$path.behavior',
          field: component.behavior,
          onEdit: (value) => cubit.updateReview(
            (review) => review.editComponentBehavior(index, value),
          ),
          onConfirm: () => cubit.updateReview(
            (review) => review.confirmComponentBehavior(index),
          ),
        ),
        if (component.note case final note?)
          _StringReviewField(
            path: '$path.note',
            label: strings.note,
            field: note,
            onEdit: (value) => cubit.updateReview(
              (review) => review.editComponentNote(index, value),
            ),
            onConfirm: () => cubit.updateReview(
              (review) => review.confirmComponentNote(index),
            ),
          ),
      ],
    );
  }
}

class _StringReviewField extends StatelessWidget {
  const _StringReviewField({
    required this.path,
    required this.label,
    required this.field,
    required this.onEdit,
    required this.onConfirm,
    this.keyboardType,
  });

  final String path;
  final String label;
  final ReviewField<String> field;
  final ValueChanged<String?> onEdit;
  final VoidCallback onConfirm;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => _ReviewFieldCard(
    label: label,
    field: field,
    input: TextFormField(
      key: ValueKey('$path.input'),
      initialValue: field.value,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: ChampionshipStrings.of(context).currentValue,
        border: const OutlineInputBorder(),
      ),
      onChanged: onEdit,
    ),
    confirmKey: ValueKey('$path.confirm'),
    onConfirm: field.canConfirm && !field.isConfirmed ? onConfirm : null,
  );
}

class _UnitReviewField extends StatelessWidget {
  const _UnitReviewField({
    required this.path,
    required this.label,
    required this.field,
    required this.resolvedValue,
    required this.onEdit,
    required this.onConfirm,
  });

  final String path;
  final String label;
  final ReviewField<String> field;
  final String? resolvedValue;
  final ValueChanged<String?> onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => _ReviewFieldCard(
    label: label,
    field: field,
    input: DropdownButtonFormField<String>(
      key: ValueKey('$path.input'),
      initialValue: resolvedValue ?? '',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: ChampionshipStrings.of(context).currentValue,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final unit in _supportedUnits)
          DropdownMenuItem(
            value: unit,
            child: Text(
              unit.isEmpty ? '—' : unit,
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) =>
          onEdit(value == null || value.isEmpty ? null : value),
    ),
    confirmKey: ValueKey('$path.confirm'),
    onConfirm: field.canConfirm && !field.isConfirmed ? onConfirm : null,
  );
}

class _BehaviorReviewField extends StatelessWidget {
  const _BehaviorReviewField({
    required this.path,
    required this.field,
    required this.onEdit,
    required this.onConfirm,
  });

  final String path;
  final ReviewField<DraftScalingBehavior> field;
  final ValueChanged<DraftScalingBehavior?> onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    return _ReviewFieldCard(
      label: strings.behavior,
      field: field,
      valueLabel: (value) => value == null ? '—' : strings.behaviorName(value),
      input: DropdownButtonFormField<DraftScalingBehavior>(
        key: ValueKey('$path.input'),
        initialValue: field.value,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: strings.currentValue,
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final behavior in DraftScalingBehavior.values)
            DropdownMenuItem(
              value: behavior,
              child: Text(
                strings.behaviorName(behavior),
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: onEdit,
      ),
      confirmKey: ValueKey('$path.confirm'),
      onConfirm: field.canConfirm && !field.isConfirmed ? onConfirm : null,
    );
  }
}

class _ReviewFieldCard<T> extends StatelessWidget {
  const _ReviewFieldCard({
    required this.label,
    required this.field,
    required this.input,
    required this.confirmKey,
    required this.onConfirm,
    this.valueLabel,
  });

  final String label;
  final ReviewField<T> field;
  final Widget input;
  final Key confirmKey;
  final VoidCallback? onConfirm;
  final String Function(T? value)? valueLabel;

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    final colors = Theme.of(context).colorScheme;
    final proposal =
        valueLabel?.call(field.sourceValue) ??
        field.sourceValue?.toString() ??
        '—';
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colors.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              _MetadataLine(label: strings.aiProposal, value: proposal),
              _MetadataLine(label: strings.evidence, value: field.evidence),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(strings.confidence(field.confidence))),
                  Chip(
                    avatar: Icon(
                      field.isConfirmed
                          ? Icons.check_circle
                          : Icons.pending_outlined,
                      size: 18,
                    ),
                    label: Text(
                      field.isConfirmed
                          ? strings.confirmed
                          : strings.needsConfirmation,
                    ),
                  ),
                  if (field.isEdited) Chip(label: Text(strings.edited)),
                ],
              ),
              if (field.activeIssues.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(strings.issues, style: TextStyle(color: colors.error)),
                for (final issue in [
                  ...field.activeSourceIssues,
                  for (final issue in field.activeLocalIssues)
                    strings.reviewIssue(issue),
                ])
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: colors.error)),
                      Expanded(
                        child: Text(
                          issue,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: 12),
              input,
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: confirmKey,
                onPressed: onConfirm,
                icon: const Icon(Icons.check),
                label: Text(
                  field.isConfirmed ? strings.confirmed : strings.confirm,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadOnlyManualField extends StatelessWidget {
  const _ReadOnlyManualField({required this.label, required this.field});

  final String label;
  final ReviewField<String> field;

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.edit_note),
        title: Text(label),
        subtitle: Text(
          '${strings.notApplicable}\n${strings.evidence}: ${field.evidence}',
        ),
      ),
    );
  }
}

class _AbsentMaximumReview extends StatelessWidget {
  const _AbsentMaximumReview({
    required this.confirmed,
    required this.onConfirm,
  });

  final bool confirmed;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: OutlinedButton.icon(
        key: const ValueKey('recipe.maxBatchYield.absent.confirm'),
        onPressed: confirmed ? null : onConfirm,
        icon: const Icon(Icons.check),
        label: Text(
          confirmed ? strings.confirmed : strings.confirmNoMaximumBatch,
        ),
      ),
    );
  }
}

class _MetadataLine extends StatelessWidget {
  const _MetadataLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        Text(value),
      ],
    ),
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class _IssueSummary extends StatelessWidget {
  const _IssueSummary({required this.issues});

  final List<String> issues;

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    final error = Theme.of(context).colorScheme.error;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: error),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(strings.issues, style: TextStyle(color: error)),
            for (final issue in issues) Text('• $issue'),
          ],
        ),
      ),
    );
  }
}
