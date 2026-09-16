import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/production_history/cubit/production_history_cubit.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_launcher.dart';
import 'package:prep_book/presentation/units/readable_quantity.dart';

/// Lists stored production runs and reopens their immutable sheets.
class ProductionHistoryPage extends StatelessWidget {
  /// Creates the page over its read use cases and sheet route.
  const ProductionHistoryPage({
    required this.listHistory,
    required this.openProductionRun,
    required this.productionSheet,
    super.key,
  });

  /// Reads stored-run summaries.
  final ListProductionHistory listHistory;

  /// Reads one immutable stored snapshot.
  final OpenProductionRun openProductionRun;

  /// Opens the existing preview, share, and print surface.
  final ProductionSheetLauncher productionSheet;

  @override
  Widget build(BuildContext context) => BlocProvider(
    create: (_) {
      final cubit = ProductionHistoryCubit(listHistory);
      unawaited(cubit.load());
      return cubit;
    },
    child: ProductionHistoryView(
      openProductionRun: openProductionRun,
      productionSheet: productionSheet,
    ),
  );
}

/// The production history rendering and row-open interaction.
class ProductionHistoryView extends StatefulWidget {
  /// Creates the view.
  const ProductionHistoryView({
    required this.openProductionRun,
    required this.productionSheet,
    super.key,
  });

  final OpenProductionRun openProductionRun;
  final ProductionSheetLauncher productionSheet;

  @override
  State<ProductionHistoryView> createState() => _ProductionHistoryViewState();
}

class _ProductionHistoryViewState extends State<ProductionHistoryView> {
  String? _openingRunId;

  Future<void> _open(ProductionHistoryEntry summary) async {
    if (_openingRunId != null) return;
    setState(() => _openingRunId = summary.id);
    try {
      final run = await widget.openProductionRun(summary.id);
      if (!mounted) return;
      if (run == null) {
        _show(context.l10n.productionHistoryMissing);
        return;
      }
      await widget.productionSheet.open(context, run: run);
    } on Object {
      if (mounted) _show(context.l10n.productionHistoryOpenError);
    } finally {
      if (mounted) setState(() => _openingRunId = null);
    }
  }

  void _show(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.productionHistoryTitle)),
      body: SafeArea(
        child: BlocBuilder<ProductionHistoryCubit, ProductionHistoryState>(
          builder: (context, state) => switch (state.status) {
            ProductionHistoryStatus.loading => const Center(
              child: CircularProgressIndicator(),
            ),
            ProductionHistoryStatus.failure => _FailureBody(
              onRetry: () {
                unawaited(context.read<ProductionHistoryCubit>().retry());
              },
            ),
            ProductionHistoryStatus.loaded =>
              state.runs.isEmpty
                  ? Center(child: Text(l10n.productionHistoryEmpty))
                  : ListView.separated(
                      key: const ValueKey('production-history-list'),
                      itemCount: state.runs.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final summary = state.runs[index];
                        return _HistoryRow(
                          summary: summary,
                          opening: _openingRunId == summary.id,
                          onOpen: () => _open(summary),
                        );
                      },
                    ),
          },
        ),
      ),
    );
  }
}

class _FailureBody extends StatelessWidget {
  const _FailureBody({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.l10n.productionHistoryError,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onRetry,
            child: Text(context.l10n.recipeLibraryRetry),
          ),
        ],
      ),
    ),
  );
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.summary,
    required this.opening,
    required this.onOpen,
  });

  final ProductionHistoryEntry summary;
  final bool opening;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final createdAt = DateFormat.yMMMd(
      locale,
    ).add_jm().format(summary.createdAt.toLocal());
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      title: Text(summary.recipeName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Text(l10n.productionHistoryRevision(summary.recipeRevision)),
          Text(readableQuantity(summary.targetYield)),
          Text(createdAt),
        ],
      ),
      trailing: opening
          ? const SizedBox.square(
              dimension: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Chip(
              label: Text(
                summary.isDraft
                    ? l10n.productionHistoryDraft
                    : l10n.productionHistoryReady,
              ),
            ),
      onTap: opening ? null : onOpen,
    );
  }
}
