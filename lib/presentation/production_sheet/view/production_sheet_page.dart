import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/export/export.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/production_sheet/cubit/production_sheet_cubit.dart';
import 'package:prep_book/presentation/production_sheet/view/app_production_sheet_localizations.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_platform.dart';
import 'package:prep_book/presentation/responsive/window_width_class.dart';

/// Previews and distributes one saved production-run snapshot.
class ProductionSheetPage extends StatelessWidget {
  const ProductionSheetPage({
    required this.run,
    required this.platform,
    this.builder = const ProductionSheetBuilder(),
    this.renderer = const ProductionSheetPdfRenderer(),
    super.key,
  });

  final ProductionRun run;
  final ProductionSheetPlatform platform;
  final ProductionSheetBuilder builder;
  final ProductionSheetPdfRenderer renderer;

  @override
  Widget build(BuildContext context) {
    final localizations = AppProductionSheetLocalizations(
      localizations: context.l10n,
      locale: Localizations.localeOf(context),
    );
    return BlocProvider(
      create: (_) {
        final cubit = ProductionSheetCubit(
          run: run,
          builder: builder,
          renderer: renderer,
          localizations: localizations,
          platform: platform,
        );
        unawaited(cubit.generate());
        return cubit;
      },
      child: _ProductionSheetView(platform: platform),
    );
  }
}

class _ProductionSheetView extends StatelessWidget {
  const _ProductionSheetView({required this.platform});

  final ProductionSheetPlatform platform;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.productionSheetTitle, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: BlocBuilder<ProductionSheetCubit, ProductionSheetState>(
          builder: (context, state) {
            final controls = _Controls(state: state);
            final preview = _preview(context, state);
            return LayoutBuilder(
              builder: (context, constraints) {
                if (usesMultiplePanesAt(
                  constraints.maxWidth,
                  MediaQuery.textScalerOf(context),
                )) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          key: const ValueKey('production-sheet-controls-pane'),
                          padding: const EdgeInsets.all(24),
                          child: controls,
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(
                        child: Padding(
                          key: const ValueKey('production-sheet-preview-pane'),
                          padding: const EdgeInsets.all(16),
                          child: preview ?? const SizedBox.shrink(),
                        ),
                      ),
                    ],
                  );
                }
                return CustomScrollView(
                  key: const ValueKey('production-sheet-compact'),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                      sliver: SliverToBoxAdapter(child: controls),
                    ),
                    if (preview != null)
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        sliver: SliverToBoxAdapter(
                          child: SizedBox(
                            height: constraints.maxHeight * 0.7,
                            child: preview,
                          ),
                        ),
                      ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget? _preview(BuildContext context, ProductionSheetState state) {
    final bytes = state.bytes;
    if (state.status != ProductionSheetStatus.ready || bytes == null) {
      return null;
    }
    return platform.preview(
      bytes: bytes,
      loading: const Center(child: CircularProgressIndicator()),
      onError: (_) => Center(
        child: Text(
          context.l10n.productionSheetGenerationFailed,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.state});

  final ProductionSheetState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cubit = context.read<ProductionSheetCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.productionSheetOrganization,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<ProductionSheetOrganization>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: ProductionSheetOrganization.batch,
                label: Text(l10n.productionSheetBatchOrganization),
              ),
              ButtonSegment(
                value: ProductionSheetOrganization.total,
                label: Text(l10n.productionSheetTotalOrganization),
              ),
            ],
            selected: {state.organization},
            onSelectionChanged:
                state.actionStatus == ProductionSheetActionStatus.idle
                ? (selected) => cubit.organizationChanged(selected.single)
                : null,
          ),
        ),
        const SizedBox(height: 24),
        ...switch (state.status) {
          ProductionSheetStatus.generating => [
            Row(
              children: [
                const SizedBox.square(
                  dimension: 24,
                  child: CircularProgressIndicator(strokeWidth: 3),
                ),
                const SizedBox(width: 12),
                Flexible(child: Text(l10n.productionSheetGenerating)),
              ],
            ),
          ],
          ProductionSheetStatus.failure => [
            Text(
              l10n.productionSheetGenerationFailed,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton(
                onPressed: cubit.generate,
                child: Text(l10n.productionSheetRetry),
              ),
            ),
          ],
          ProductionSheetStatus.ready => [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: state.canUsePdfActions ? cubit.share : null,
                  icon: const Icon(Icons.share_outlined),
                  label: Text(
                    state.actionStatus == ProductionSheetActionStatus.sharing
                        ? l10n.productionSheetSharing
                        : l10n.productionSheetShare,
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: state.canUsePdfActions ? cubit.print : null,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(
                    state.actionStatus == ProductionSheetActionStatus.printing
                        ? l10n.productionSheetPrinting
                        : l10n.productionSheetPrint,
                  ),
                ),
              ],
            ),
            if (state.actionError != null) ...[
              const SizedBox(height: 12),
              Text(
                state.failedAction == ProductionSheetActionStatus.printing
                    ? l10n.productionSheetPrintFailed
                    : l10n.productionSheetShareFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        },
      ],
    );
  }
}
