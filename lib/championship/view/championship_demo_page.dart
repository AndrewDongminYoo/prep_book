import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/cubit/championship_demo_state.dart';
import 'package:prep_book/championship/view/championship_result_panel.dart';
import 'package:prep_book/championship/view/championship_review_panel.dart';
import 'package:prep_book/championship/view/championship_source_panel.dart';
import 'package:prep_book/championship/view/championship_strings.dart';
import 'package:prep_book/championship/view/championship_target_panel.dart';
import 'package:prep_book/presentation/responsive/window_width_class.dart';

class ChampionshipDemoPage extends StatelessWidget {
  const ChampionshipDemoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final expanded = usesMultiplePanesAt(
              constraints.maxWidth,
              MediaQuery.textScalerOf(context),
            );
            return SingleChildScrollView(
              key: const ValueKey('championship-demo-content'),
              padding: EdgeInsets.symmetric(
                horizontal: expanded ? 48 : 24,
                vertical: 40,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1120),
                  child: !expanded
                      ? const _CompactShell(
                          key: ValueKey('championship-compact-layout'),
                        )
                      : const _ExpandedShell(
                          key: ValueKey('championship-expanded-layout'),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CompactShell extends StatelessWidget {
  const _CompactShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_Introduction(), SizedBox(height: 32), _PhasePanel()],
    );
  }
}

class _ExpandedShell extends StatelessWidget {
  const _ExpandedShell({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(flex: 2, child: _Introduction()),
        SizedBox(width: 48),
        Expanded(flex: 3, child: _PhasePanel()),
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
        Text(strings.title, style: textTheme.displaySmall),
        const SizedBox(height: 20),
        Text(strings.boundary, style: textTheme.titleLarge),
      ],
    );
  }
}

class _PhasePanel extends StatelessWidget {
  const _PhasePanel();

  @override
  Widget build(BuildContext context) {
    final strings = ChampionshipStrings.of(context);
    final state = context.watch<ChampionshipDemoCubit>().state;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
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
        const SizedBox(height: 24),
        _CurrentPanel(state: state),
      ],
    );
  }
}

class _CurrentPanel extends StatelessWidget {
  const _CurrentPanel({required this.state});

  final ChampionshipDemoState state;

  @override
  Widget build(BuildContext context) => switch (state.phase) {
    ChampionshipPhase.source => const ChampionshipSourcePanel(),
    ChampionshipPhase.review => const ChampionshipReviewPanel(),
    ChampionshipPhase.target => const ChampionshipTargetPanel(),
    ChampionshipPhase.result => const ChampionshipResultPanel(),
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
