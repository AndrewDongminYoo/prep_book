import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/cubit/championship_demo_state.dart';
import 'package:prep_book/championship/import/recipe_draft_verifier.dart';
import 'package:prep_book/championship/import/unit_alias_resolver.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/championship/model/review_recipe_draft.dart';
import 'package:prep_book/championship/view/championship_strings.dart';

/// The unit choices offered to the reviewer: no unit, then every symbol the
/// resolver can map back to a domain unit.
const _supportedUnits = <String>['', ...UnitAliasResolver.symbols];

class ChampionshipReviewPanel extends StatefulWidget {
  const new({super.key});

  @override
  State<ChampionshipReviewPanel> createState() => _ChampionshipReviewPanelState();
}

class _ChampionshipReviewPanelState extends State<ChampionshipReviewPanel> {
  final _focusNodes = <String, FocusNode>{};
  final _anchors = <String, GlobalKey>{};
  final GlobalKey _summaryKey = GlobalKey();
  var _componentListRevision = 0;
  var _recoveryGeneration = 0;
  int? _componentCount;

  String _fieldStateKey(String path) => '$_componentListRevision:$path';

  FocusNode _focusNode(String path) => _focusNodes.putIfAbsent(_fieldStateKey(path), FocusNode.new);

  GlobalKey _anchor(String path) => _anchors.putIfAbsent(_fieldStateKey(path), GlobalKey.new);

  void _syncComponentCount(int count) {
    if (_componentCount != null && _componentCount != count) {
      _componentListRevision += 1;
    }
    _componentCount = count;
  }

  @override
  void dispose() {
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    super.dispose();
  }

  void _recoverFromFailure(RecipeDraftVerificationIssue issue) {
    final generation = ++_recoveryGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || generation != _recoveryGeneration) return;
      final path = issue.path;
      final fieldStateKey = path == null ? null : _fieldStateKey(path);
      final focusNode = fieldStateKey == null ? null : _focusNodes[fieldStateKey];
      final targetContext = path == null ? null : _anchors[fieldStateKey]?.currentContext;
      if (focusNode == null || targetContext == null) {
        final summaryContext = _summaryKey.currentContext;
        if (summaryContext != null) {
          await Scrollable.ensureVisible(
            summaryContext,
            duration: const Duration(milliseconds: 250),
            alignment: 0.1,
          );
        }
        return;
      }
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 250),
        alignment: 0.1,
      );
      if (mounted && generation == _recoveryGeneration) {
        focusNode.requestFocus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChampionshipDemoCubit>();
    final state = context.watch<ChampionshipDemoCubit>().state;
    final draft = state.review!;
    final strings = ChampionshipStrings.of(context);
    _syncComponentCount(draft.components.length);
    return BlocListener<ChampionshipDemoCubit, ChampionshipDemoState>(
      listenWhen: (previous, current) => !identical(previous.reviewIssues, current.reviewIssues),
      listener: (context, state) {
        if (state.reviewIssues.isEmpty) {
          _recoveryGeneration += 1;
          return;
        }
        _recoverFromFailure(state.reviewIssues.first);
      },
      child: Card(
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
                anchorKey: _anchor('recipe.name'),
                focusNode: _focusNode('recipe.name'),
                label: strings.recipeName,
                field: draft.recipe.name,
                onEdit: (value) => cubit.updateReview(
                  (review) => review.editRecipeName(value),
                ),
                onConfirm: () => cubit.updateReview((review) => review.confirmRecipeName()),
              ),
              _StringReviewField(
                path: 'recipe.baseYield.amount',
                anchorKey: _anchor('recipe.baseYield.amount'),
                focusNode: _focusNode('recipe.baseYield.amount'),
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
                anchorKey: _anchor('recipe.baseYield.unit'),
                focusNode: _focusNode('recipe.baseYield.unit'),
                label: strings.baseYieldUnit,
                field: draft.recipe.baseYield.unit,
                resolvedValue: draft.units.resolve(draft.recipe.baseYield.unit.value)?.symbol,
                onEdit: (value) => cubit.updateReview(
                  (review) => review.editBaseYieldUnit(value),
                ),
                onConfirm: () => cubit.updateReview(
                  (review) => review.confirmBaseYieldUnit(),
                ),
              ),
              if (draft.recipe.maxBatchYield case final maximum?) ...[
                _StringReviewField(
                  path: 'recipe.maxBatchYield.amount',
                  anchorKey: _anchor('recipe.maxBatchYield.amount'),
                  focusNode: _focusNode('recipe.maxBatchYield.amount'),
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
                  anchorKey: _anchor('recipe.maxBatchYield.unit'),
                  focusNode: _focusNode('recipe.maxBatchYield.unit'),
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
              for (var index = 0; index < draft.recipe.preparationNotes.length; index += 1)
                _StringReviewField(
                  path: 'recipe.preparationNotes[$index]',
                  anchorKey: _anchor('recipe.preparationNotes[$index]'),
                  focusNode: _focusNode('recipe.preparationNotes[$index]'),
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
                  key: ObjectKey(draft.components[index]),
                  index: index,
                  component: draft.components[index],
                  anchorFor: _anchor,
                  focusNodeFor: _focusNode,
                ),
              if (state.reviewIssues.isNotEmpty) ...[
                const SizedBox(height: 16),
                _IssueSummary(key: _summaryKey, issues: state.reviewIssues),
              ],
              const SizedBox(height: 24),
              // The same bulk action as at the top, offered again where the
              // reviewer ends up after correcting the flagged fields, so the
              // remaining clean values can be confirmed without scrolling back.
              OutlinedButton.icon(
                key: const ValueKey('review-confirm-all-bottom'),
                onPressed: cubit.confirmAllUnambiguous,
                icon: const Icon(Icons.done_all),
                label: Text(strings.confirmAll),
              ),
              const SizedBox(height: 12),
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
      ),
    );
  }
}

class _ComponentReview extends StatelessWidget {
  const new({
    required this.index,
    required this.component,
    required this.anchorFor,
    required this.focusNodeFor,
    super.key,
  });

  final int index;
  final ReviewRecipeComponent component;
  final GlobalKey Function(String path) anchorFor;
  final FocusNode Function(String path) focusNodeFor;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChampionshipDemoCubit>();
    final draft = context.watch<ChampionshipDemoCubit>().state.review!;
    final strings = ChampionshipStrings.of(context);
    final path = 'components[$index]';
    final isManual = component.behavior.value == DraftScalingBehavior.manual;
    final name = component.name.value?.trim();
    final visibleName = name == null || name.isEmpty ? strings.component(index) : name;
    final removeComponent = draft.components.length > 1 ? () => _confirmRemoval(context, cubit, strings) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 40),
        _SectionHeading(strings.component(index)),
        const SizedBox(height: 12),
        Semantics(
          key: ValueKey('$path.remove-semantics'),
          excludeSemantics: true,
          button: true,
          enabled: removeComponent != null,
          label: strings.removeComponentAction(index: index, name: visibleName),
          onTap: removeComponent,
          child: OutlinedButton.icon(
            key: ValueKey('$path.remove'),
            onPressed: removeComponent,
            icon: const Icon(Icons.delete_outline),
            label: Text(strings.removeComponent),
          ),
        ),
        _StringReviewField(
          path: '$path.name',
          anchorKey: anchorFor('$path.name'),
          focusNode: focusNodeFor('$path.name'),
          label: strings.componentNameFor(index),
          field: component.name,
          onEdit: (value) => cubit.updateReview(
            (review) => review.editComponentName(index, value),
          ),
          onConfirm: () => cubit.updateReview(
            (review) => review.confirmComponentName(index),
          ),
        ),
        if (isManual) ...[
          _ReadOnlyManualField(
            label: strings.componentAmountFor(index),
            field: component.amount,
          ),
          _ReadOnlyManualField(
            label: strings.componentUnitFor(index),
            field: component.unit,
          ),
        ] else ...[
          _StringReviewField(
            path: '$path.amount',
            anchorKey: anchorFor('$path.amount'),
            focusNode: focusNodeFor('$path.amount'),
            label: strings.componentAmountFor(index),
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
            anchorKey: anchorFor('$path.unit'),
            focusNode: focusNodeFor('$path.unit'),
            label: strings.componentUnitFor(index),
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
          anchorKey: anchorFor('$path.behavior'),
          focusNode: focusNodeFor('$path.behavior'),
          label: strings.componentBehaviorFor(index),
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
            anchorKey: anchorFor('$path.note'),
            focusNode: focusNodeFor('$path.note'),
            label: strings.componentNoteFor(index),
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

  Future<void> _confirmRemoval(
    BuildContext context,
    ChampionshipDemoCubit cubit,
    ChampionshipStrings strings,
  ) async {
    final name = component.name.value?.trim();
    final visibleName = name == null || name.isEmpty ? strings.component(index) : name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(strings.removeComponentTitle(visibleName)),
        content: Text(strings.removeComponentMessage(visibleName)),
        actions: [
          TextButton(
            key: const ValueKey('component-remove-cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const ValueKey('component-remove-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(strings.remove),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      cubit.updateReview((review) => review.removeComponent(index));
    }
  }
}

class _StringReviewField extends StatelessWidget {
  const new({
    required this.path,
    required this.anchorKey,
    required this.focusNode,
    required this.label,
    required this.field,
    required this.onEdit,
    required this.onConfirm,
    this.keyboardType,
  });

  final String path;
  final GlobalKey anchorKey;
  final FocusNode focusNode;
  final String label;
  final ReviewField<String> field;
  final ValueChanged<String?> onEdit;
  final VoidCallback onConfirm;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) => _ReviewFieldCard(
    key: anchorKey,
    path: path,
    label: label,
    field: field,
    input: TextFormField(
      key: ValueKey('$path.input'),
      initialValue: field.value,
      focusNode: focusNode,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: ChampionshipStrings.of(context).currentValueFor(label),
      ),
      onChanged: onEdit,
    ),
    confirmKey: ValueKey('$path.confirm'),
    onConfirm: field.canConfirm && !field.isConfirmed ? onConfirm : null,
  );
}

class _UnitReviewField extends StatelessWidget {
  const new({
    required this.path,
    required this.anchorKey,
    required this.focusNode,
    required this.label,
    required this.field,
    required this.resolvedValue,
    required this.onEdit,
    required this.onConfirm,
  });

  final String path;
  final GlobalKey anchorKey;
  final FocusNode focusNode;
  final String label;
  final ReviewField<String> field;
  final String? resolvedValue;
  final ValueChanged<String?> onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) => _ReviewFieldCard(
    key: anchorKey,
    path: path,
    label: label,
    field: field,
    input: DropdownButtonFormField<String>(
      key: ValueKey('$path.input'),
      initialValue: resolvedValue ?? '',
      focusNode: focusNode,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: ChampionshipStrings.of(context).currentValueFor(label),
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
      onChanged: (value) => onEdit(value == null || value.isEmpty ? null : value),
    ),
    confirmKey: ValueKey('$path.confirm'),
    onConfirm: field.canConfirm && !field.isConfirmed ? onConfirm : null,
  );
}

class _BehaviorReviewField extends StatelessWidget {
  const new({
    required this.path,
    required this.anchorKey,
    required this.focusNode,
    required this.label,
    required this.field,
    required this.onEdit,
    required this.onConfirm,
  });

  final String path;
  final GlobalKey anchorKey;
  final FocusNode focusNode;
  final String label;
  final ReviewField<DraftScalingBehavior> field;
  final ValueChanged<DraftScalingBehavior?> onEdit;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    return _ReviewFieldCard(
      key: anchorKey,
      path: path,
      label: label,
      field: field,
      valueLabel: (value) => value == null ? '—' : strings.behaviorName(value),
      input: DropdownButtonFormField<DraftScalingBehavior>(
        key: ValueKey('$path.input'),
        initialValue: field.value,
        focusNode: focusNode,
        isExpanded: true,
        decoration: InputDecoration(labelText: strings.currentValueFor(label)),
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
  const new({
    required this.path,
    required this.label,
    required this.field,
    required this.input,
    required this.confirmKey,
    required this.onConfirm,
    this.valueLabel,
    super.key,
  });

  final String path;
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
    final proposal = valueLabel?.call(field.sourceValue) ?? field.sourceValue?.toString() ?? '—';
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _MetadataLine(label: strings.aiProposal, value: proposal),
        _MetadataLine(label: strings.evidence, value: field.evidence),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatusChip(
              semanticsKey: ValueKey('$path.confidence-semantics'),
              label: strings.confidence(field.confidence),
            ),
            _StatusChip(
              semanticsKey: ValueKey('$path.confirmation-semantics'),
              avatar: Icon(
                field.isConfirmed ? Icons.check_circle : Icons.pending_outlined,
                size: 18,
              ),
              label: field.isConfirmed ? strings.confirmed : strings.needsConfirmation,
            ),
            if (field.isEdited)
              _StatusChip(
                semanticsKey: ValueKey('$path.edited-semantics'),
                label: strings.edited,
              ),
          ],
        ),
      ],
    );
    final controls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (field.activeIssues.isNotEmpty) ...[
          Text(strings.issues, style: TextStyle(color: colors.error)),
          for (final issue in [
            ...field.activeSourceIssues,
            for (final issue in field.activeLocalIssues) strings.reviewIssue(issue),
          ])
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('• ', style: TextStyle(color: colors.error)),
                Expanded(
                  child: Text(issue, style: TextStyle(color: colors.error)),
                ),
              ],
            ),
          const SizedBox(height: 12),
        ],
        input,
        const SizedBox(height: 12),
        Semantics(
          key: ValueKey('$path.confirm-semantics'),
          excludeSemantics: true,
          button: true,
          enabled: onConfirm != null,
          label: field.isConfirmed ? strings.confirmedField(label) : strings.confirmField(label),
          onTap: onConfirm,
          child: OutlinedButton.icon(
            key: confirmKey,
            onPressed: onConfirm,
            icon: const Icon(Icons.check),
            label: Text(
              field.isConfirmed ? strings.confirmed : strings.confirm,
            ),
          ),
        ),
      ],
    );
    return Semantics(
      key: ValueKey('$path.field-semantics'),
      container: true,
      explicitChildNodes: true,
      label: label,
      child: Padding(
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
                ExcludeSemantics(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final sideBySide = constraints.maxWidth >= 600 && MediaQuery.textScalerOf(context).scale(16) <= 24;
                    if (!sideBySide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          details,
                          const SizedBox(height: 12),
                          controls,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 5, child: details),
                        const SizedBox(width: 24),
                        Expanded(flex: 4, child: controls),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const new({
    required this.semanticsKey,
    required this.label,
    this.avatar,
  });

  final Key semanticsKey;
  final String label;
  final Widget? avatar;

  @override
  Widget build(BuildContext context) => Semantics(
    key: semanticsKey,
    container: true,
    excludeSemantics: true,
    role: SemanticsRole.status,
    label: label,
    child: Chip(avatar: avatar, label: Text(label)),
  );
}

class _ReadOnlyManualField extends StatelessWidget {
  const new({required this.label, required this.field});

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
  const new({
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
  const new({required this.label, required this.value});

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
  const new(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleLarge);
}

class _IssueSummary extends StatelessWidget {
  const new({required this.issues, super.key});

  final List<RecipeDraftVerificationIssue> issues;

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
            for (final issue in issues) Text('• ${strings.verificationIssue(issue)}'),
          ],
        ),
      ),
    );
  }
}
