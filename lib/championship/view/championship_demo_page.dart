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
import 'package:prep_book/presentation/responsive/window_width_class.dart';

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
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final expanded = usesMultiplePanesAt(
                constraints.maxWidth,
                MediaQuery.textScalerOf(context),
              );
              return SingleChildScrollView(
                key: const ValueKey('championship-demo-content'),
                controller: _scrollController,
                padding: EdgeInsets.symmetric(
                  horizontal: expanded ? 48 : 24,
                  vertical: 40,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1120),
                    child: !expanded
                        ? _CompactShell(
                            key: const ValueKey('championship-compact-layout'),
                            phaseFocusNode: _phaseFocusNode,
                            openProductionSheet: widget.openProductionSheet,
                          )
                        : _ExpandedShell(
                            key: const ValueKey('championship-expanded-layout'),
                            phaseFocusNode: _phaseFocusNode,
                            openProductionSheet: widget.openProductionSheet,
                          ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({
    required this.phaseFocusNode,
    required this.openProductionSheet,
    super.key,
  });

  final FocusNode phaseFocusNode;
  final OpenChampionshipProductionSheet openProductionSheet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Introduction(),
        const SizedBox(height: 32),
        _PhasePanel(
          phaseFocusNode: phaseFocusNode,
          openProductionSheet: openProductionSheet,
        ),
      ],
    );
  }
}

class _ExpandedShell extends StatelessWidget {
  const _ExpandedShell({
    required this.phaseFocusNode,
    required this.openProductionSheet,
    super.key,
  });

  final FocusNode phaseFocusNode;
  final OpenChampionshipProductionSheet openProductionSheet;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(child: _Introduction()),
        const SizedBox(width: 32),
        Expanded(
          child: _PhasePanel(
            phaseFocusNode: phaseFocusNode,
            openProductionSheet: openProductionSheet,
          ),
        ),
      ],
    );
  }
}

class _Introduction extends StatelessWidget {
  const _Introduction();

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ChampionshipWordWrapText(
          key: const ValueKey('championship-introduction-title'),
          text: strings.title,
          style: textTheme.headlineLarge,
        ),
        const SizedBox(height: 20),
        ChampionshipWordWrapText(
          key: const ValueKey('championship-introduction-boundary'),
          text: strings.boundary,
          style: textTheme.titleLarge,
        ),
      ],
    );
  }
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          explicitChildNodes: true,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _PhaseLabel(
                phase: ChampionshipPhase.source,
                label: strings.source,
                currentPhase: state.phase,
              ),
              _PhaseLabel(
                phase: ChampionshipPhase.review,
                label: strings.review,
                currentPhase: state.phase,
              ),
              _PhaseLabel(
                phase: ChampionshipPhase.target,
                label: strings.target,
                currentPhase: state.phase,
              ),
              _PhaseLabel(
                phase: ChampionshipPhase.result,
                label: strings.result,
                currentPhase: state.phase,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Focus(
          key: const ValueKey('championship-current-phase-focus'),
          focusNode: phaseFocusNode,
          skipTraversal: true,
          child: Semantics(
            key: const ValueKey('championship-current-phase-semantics'),
            focusable: true,
            focused: phaseFocusNode.hasFocus,
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
  });

  final ChampionshipPhase phase;
  final String label;
  final ChampionshipPhase currentPhase;

  @override
  Widget build(BuildContext context) {
    final selected = phase == currentPhase;
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('championship-phase-${phase.name}'),
      excludeSemantics: true,
      label: ChampionshipStrings.of(
        context,
      ).phaseStep(label: label, index: phase.index, current: selected),
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? colors.primaryContainer : colors.surfaceContainer,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(label),
        ),
      ),
    );
  }
}
