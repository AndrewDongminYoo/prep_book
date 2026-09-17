import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/cubit/championship_demo_state.dart';
import 'package:prep_book/championship/view/championship_result_panel.dart';
import 'package:prep_book/championship/view/championship_review_panel.dart';
import 'package:prep_book/championship/view/championship_source_panel.dart';
import 'package:prep_book/championship/view/championship_strings.dart';
import 'package:prep_book/championship/view/championship_target_panel.dart';
import 'package:prep_book/championship/view/championship_word_wrap_text.dart';

const _paperGridColor = Color(0xFFEAF0F5);
const _completedStepLineColor = Color(0xFFC8DACF);
const _completedStepBackgroundColor = Color(0xFFE7F1EB);
const _completedStepForegroundColor = Color(0xFF397553);

class ChampionshipDemoPage extends StatefulWidget {
  const ChampionshipDemoPage({required this.openProductionSheet, super.key});

  final OpenChampionshipProductionSheet openProductionSheet;

  @override
  State<ChampionshipDemoPage> createState() => _ChampionshipDemoPageState();
}

class _ChampionshipDemoPageState extends State<ChampionshipDemoPage> {
  final ScrollController _scrollController = ScrollController();
  final FocusNode _phaseFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _phaseFocusNode.addListener(_phaseFocusChanged);
  }

  void _phaseFocusChanged() {
    if (mounted) setState(() {});
  }

  void _showPhase() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        if (MediaQuery.disableAnimationsOf(context)) {
          _scrollController.jumpTo(0);
        } else {
          await _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
      if (mounted) _phaseFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _phaseFocusNode
      ..removeListener(_phaseFocusChanged)
      ..dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChampionshipDemoCubit, ChampionshipDemoState>(
      listenWhen: (previous, current) => previous.phase != current.phase,
      listener: (context, state) => _showPhase(),
      child: Scaffold(
        body: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _PaperGridPainter()),
              ),
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final expanded =
                      constraints.maxWidth >= 600 &&
                      MediaQuery.textScalerOf(context).scale(16) <= 24;
                  return SingleChildScrollView(
                    key: const ValueKey('championship-demo-content'),
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                      horizontal: expanded ? 32 : 20,
                      vertical: expanded ? 48 : 28,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 760),
                        child: _WorkflowShell(
                          key: ValueKey(
                            expanded
                                ? 'championship-expanded-layout'
                                : 'championship-compact-layout',
                          ),
                          phaseFocusNode: _phaseFocusNode,
                          openProductionSheet: widget.openProductionSheet,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowShell extends StatelessWidget {
  const _WorkflowShell({
    required this.phaseFocusNode,
    required this.openProductionSheet,
    super.key,
  });

  final FocusNode phaseFocusNode;
  final OpenChampionshipProductionSheet openProductionSheet;

  @override
  Widget build(BuildContext context) {
    final phase = context.watch<ChampionshipDemoCubit>().state.phase;
    final strings = ChampionshipStrings.of(context);
    return Column(
      key: const ValueKey('championship-workflow-progress'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _BrandHeader(),
        const SizedBox(height: 24),
        const _PhaseSteps(),
        const SizedBox(height: 24),
        KeyedSubtree(
          key: phase == ChampionshipPhase.source
              ? null
              : const ValueKey('championship-task-layout'),
          child: _PhasePanel(
            phaseFocusNode: phaseFocusNode,
            openProductionSheet: openProductionSheet,
          ),
        ),
        const SizedBox(height: 32),
        const Divider(),
        const SizedBox(height: 12),
        ChampionshipWordWrapText(
          key: const ValueKey('championship-introduction-boundary'),
          text: strings.boundary,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    return Row(
      key: const ValueKey('championship-brand-header'),
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: colors.primary,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.menu_book_outlined, color: colors.onPrimary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChampionshipWordWrapText(
                key: const ValueKey('championship-introduction-title'),
                text: strings.brandTitle,
                style: textTheme.titleMedium,
              ),
              Text(
                strings.brandSubtitle,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PaperGridPainter extends CustomPainter {
  const _PaperGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _paperGridColor
      ..strokeWidth = 0.7;
    const spacing = 24.0;
    for (var x = 0.0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var y = 0.0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PaperGridPainter oldDelegate) => false;
}

class _PhasePanel extends StatelessWidget {
  const _PhasePanel({
    required this.phaseFocusNode,
    required this.openProductionSheet,
  });

  final FocusNode phaseFocusNode;
  final OpenChampionshipProductionSheet openProductionSheet;

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    final state = context.watch<ChampionshipDemoCubit>().state;
    return Column(
      key: const ValueKey('championship-phase-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Focus(
          key: const ValueKey('championship-current-phase-focus'),
          focusNode: phaseFocusNode,
          skipTraversal: true,
          child: Semantics(
            key: const ValueKey('championship-current-phase-semantics'),
            focusable: true,
            focused: phaseFocusNode.hasPrimaryFocus,
            liveRegion: true,
            label: strings.currentStep(
              label: strings.phaseName(state.phase),
              index: state.phase.index,
            ),
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: _CurrentPanel(
                state: state,
                openProductionSheet: openProductionSheet,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PhaseSteps extends StatelessWidget {
  const _PhaseSteps();

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    final phase = context.watch<ChampionshipDemoCubit>().state.phase;
    final steps = <_PhaseLabel>[
      _PhaseLabel(
        phase: ChampionshipPhase.source,
        label: strings.source,
        currentPhase: phase,
      ),
      _PhaseLabel(
        phase: ChampionshipPhase.review,
        label: strings.review,
        currentPhase: phase,
      ),
      _PhaseLabel(
        phase: ChampionshipPhase.target,
        label: strings.target,
        currentPhase: phase,
      ),
      _PhaseLabel(
        phase: ChampionshipPhase.result,
        label: strings.result,
        currentPhase: phase,
      ),
    ];
    return Semantics(
      container: true,
      explicitChildNodes: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
          final colors = Theme.of(context).colorScheme;
          final compactLine =
              constraints.maxWidth >= 280 &&
              constraints.maxWidth < 600 &&
              scale <= 1;
          if (compactLine) {
            final markerSize = MediaQuery.textScalerOf(context).scale(14) + 14;
            return Stack(
              children: [
                Positioned(
                  left: constraints.maxWidth / 8,
                  right: constraints.maxWidth / 8,
                  top: markerSize / 2,
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        for (var index = 0; index < 3; index += 1)
                          Expanded(
                            child: Container(
                              key: ValueKey(
                                'championship-step-connector-$index',
                              ),
                              height: 1,
                              color: index < phase.index
                                  ? _completedStepLineColor
                                  : colors.outlineVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Row(
                  children: [
                    for (final step in steps)
                      Expanded(
                        child: _PhaseLabel(
                          phase: step.phase,
                          label: step.label,
                          currentPhase: phase,
                          compact: true,
                        ),
                      ),
                  ],
                ),
              ],
            );
          }
          if (constraints.maxWidth < 600 || scale > 1) {
            return Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 12,
              children: steps,
            );
          }
          return Row(
            children: [
              for (var index = 0; index < steps.length; index += 1) ...[
                if (index > 0)
                  Expanded(
                    child: Container(
                      key: ValueKey('championship-step-connector-${index - 1}'),
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: index <= phase.index
                          ? _completedStepLineColor
                          : colors.outlineVariant,
                    ),
                  ),
                steps[index],
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CurrentPanel extends StatelessWidget {
  const _CurrentPanel({required this.state, required this.openProductionSheet});

  final ChampionshipDemoState state;
  final OpenChampionshipProductionSheet openProductionSheet;

  @override
  Widget build(BuildContext context) => switch (state.phase) {
    ChampionshipPhase.source => const ChampionshipSourcePanel(),
    ChampionshipPhase.review => const ChampionshipReviewPanel(),
    ChampionshipPhase.target => const ChampionshipTargetPanel(),
    ChampionshipPhase.result => ChampionshipResultPanel(
      openProductionSheet: openProductionSheet,
    ),
  };
}

class _PhaseLabel extends StatelessWidget {
  const _PhaseLabel({
    required this.phase,
    required this.label,
    required this.currentPhase,
    this.compact = false,
  });

  final ChampionshipPhase phase;
  final String label;
  final ChampionshipPhase currentPhase;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final selected = phase == currentPhase;
    final completed = phase.index < currentPhase.index;
    final colors = Theme.of(context).colorScheme;
    final markerSize = MediaQuery.textScalerOf(context).scale(14) + 14;
    final marker = Container(
      width: markerSize,
      height: markerSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected
            ? colors.primary
            : completed
            ? _completedStepBackgroundColor
            : colors.surface,
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: Text(
        '${phase.index + 1}',
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: selected
              ? colors.onPrimary
              : completed
              ? _completedStepForegroundColor
              : colors.onSurfaceVariant,
        ),
      ),
    );
    final title = Text(
      label,
      textAlign: compact ? TextAlign.center : null,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: selected ? colors.primary : colors.onSurfaceVariant,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
      ),
    );
    return Semantics(
      key: ValueKey('championship-phase-${phase.name}'),
      excludeSemantics: true,
      label: ChampionshipStrings.of(
        context,
      ).phaseStep(label: label, index: phase.index, current: selected),
      selected: selected,
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [marker, const SizedBox(height: 4), title],
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [marker, const SizedBox(width: 8), title],
            ),
    );
  }
}
