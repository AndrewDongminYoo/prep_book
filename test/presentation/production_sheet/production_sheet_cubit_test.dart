import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/export/export.dart';
import 'package:prep_book/presentation/production_sheet/cubit/production_sheet_cubit.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_platform.dart';

import '../../export/fixtures.dart';

const _labels = ProductionSheetLabels(
  documentTitle: 'Production sheet',
  recipeRevision: 'Revision',
  targetYield: 'Target yield',
  createdAt: 'Created',
  rootBatchCount: 'Root batches',
  organization: 'Organization',
  batchOrganization: 'By batch',
  totalOrganization: 'Totals',
  outstandingWarnings: 'Outstanding warnings',
  acknowledgedWarnings: 'Acknowledged warnings',
  sectionTarget: 'Section target',
  sectionBatchCount: 'Section batches',
  preparationNotes: 'Preparation notes',
  totals: 'Totals',
  component: 'Component',
  calculatedAmount: 'Calculated',
  batchYield: 'Batch yield',
  exactAmount: 'Exact',
  wholeRunActual: 'Whole-run actual',
  manualAmount: 'Manual amount',
  draft: 'DRAFT',
  pagePattern: 'Page {current} of {total}',
);

final class _Localizations implements ProductionSheetLocalizations {
  const _Localizations();

  @override
  ProductionSheetLabels get labels => _labels;

  @override
  String batch(int number) => 'Batch $number';

  @override
  String batchRange(int first, int last) => '$first-$last';

  @override
  String formatCreatedAt(DateTime createdAtUtc) => '$createdAtUtc';

  @override
  String formatQuantity(Quantity quantity) => '$quantity';

  @override
  String warningMessage({
    required ProductionWarning warning,
    required String recipeName,
    String? componentName,
  }) => '$recipeName:$componentName';
}

ProductionSheet _sheet(ProductionSheetOrganization organization) {
  return ProductionSheet(
    organization: organization,
    labels: _labels,
    recipeName: 'Bun dough',
    recipeRevision: 1,
    targetYield: '10 g',
    createdAt: '2026-09-11',
    rootBatchCount: 1,
    isDraft: false,
    outstandingWarnings: const [],
    acknowledgedWarnings: const [],
    sections: const [],
  );
}

final class _RecordingBuilder extends ProductionSheetBuilder {
  final runs = <ProductionRun>[];
  final organizations = <ProductionSheetOrganization>[];
  Error? error;

  @override
  ProductionSheet build({
    required ProductionRun run,
    required ProductionSheetOrganization organization,
    required ProductionSheetLocalizations localizations,
  }) {
    runs.add(run);
    organizations.add(organization);
    final currentError = error;
    if (currentError != null) throw currentError;
    return _sheet(organization);
  }
}

final class _RecordingRenderer extends ProductionSheetPdfRenderer {
  final sheets = <ProductionSheet>[];
  final fonts = <Uint8List>[];
  final queued = <Future<Uint8List>>[];
  Error? error;
  Uint8List nextBytes = Uint8List.fromList([9]);

  @override
  Future<Uint8List> render(
    ProductionSheet sheet, {
    required Uint8List fontBytes,
  }) {
    sheets.add(sheet);
    fonts.add(fontBytes);
    final currentError = error;
    if (currentError != null) return Future.error(currentError);
    if (queued.isNotEmpty) return queued.removeAt(0);
    return Future.value(nextBytes);
  }
}

final class _RecordingPlatform implements ProductionSheetPlatform {
  final fontBytes = Uint8List.fromList([1, 2, 3]);
  final sharedBytes = <Uint8List>[];
  final sharedFilenames = <String>[];
  final printedBytes = <Uint8List>[];
  final printedNames = <String>[];
  Error? fontError;
  Error? shareError;
  Error? printError;
  Future<bool>? nextShare;
  Future<bool>? nextPrint;
  int fontLoads = 0;

  @override
  Future<Uint8List> loadFontBytes() async {
    fontLoads++;
    final currentError = fontError;
    if (currentError != null) throw currentError;
    return fontBytes;
  }

  @override
  Widget preview({
    required Uint8List bytes,
    required Widget loading,
    required Widget Function(Object error) onError,
  }) => const SizedBox();

  @override
  Future<bool> share({required Uint8List bytes, required String filename}) {
    sharedBytes.add(bytes);
    sharedFilenames.add(filename);
    final currentError = shareError;
    if (currentError != null) return Future.error(currentError);
    return nextShare ?? Future.value(true);
  }

  @override
  Future<bool> print({required Uint8List bytes, required String name}) {
    printedBytes.add(bytes);
    printedNames.add(name);
    final currentError = printError;
    if (currentError != null) return Future.error(currentError);
    return nextPrint ?? Future.value(true);
  }
}

ProductionSheetCubit _cubit({
  required ProductionRun run,
  required _RecordingBuilder builder,
  required _RecordingRenderer renderer,
  required _RecordingPlatform platform,
}) => ProductionSheetCubit(
  run: run,
  builder: builder,
  renderer: renderer,
  localizations: const _Localizations(),
  platform: platform,
);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  test('generates batch first and reuses the same run for total', () async {
    final run = buildProductionSheetRun();
    final builder = _RecordingBuilder();
    final renderer = _RecordingRenderer();
    final platform = _RecordingPlatform();
    final firstBytes = Uint8List.fromList([4]);
    renderer.nextBytes = firstBytes;
    final cubit = _cubit(
      run: run,
      builder: builder,
      renderer: renderer,
      platform: platform,
    );

    expect(cubit.state.organization, ProductionSheetOrganization.batch);
    expect(cubit.state.status, ProductionSheetStatus.generating);
    expect(cubit.state.canUsePdfActions, isFalse);

    await cubit.generate();

    expect(builder.runs.single, same(run));
    expect(builder.organizations.single, ProductionSheetOrganization.batch);
    expect(cubit.state.bytes, same(firstBytes));
    expect(
      cubit.state.filename,
      'production-sheet-Bun-dough-20260911T040506Z.pdf',
    );
    expect(cubit.state.canUsePdfActions, isTrue);
    expect(renderer.fonts.single, same(platform.fontBytes));

    final totalBytes = Uint8List.fromList([5]);
    renderer.nextBytes = totalBytes;
    await cubit.organizationChanged(ProductionSheetOrganization.total);

    expect(builder.runs.last, same(run));
    expect(builder.organizations.last, ProductionSheetOrganization.total);
    expect(cubit.state.organization, ProductionSheetOrganization.total);
    expect(cubit.state.bytes, same(totalBytes));
    expect(platform.fontLoads, 1);
    await cubit.close();
  });

  test(
    'ignores an obsolete render that finishes after the latest one',
    () async {
      final run = buildProductionSheetRun();
      final builder = _RecordingBuilder();
      final renderer = _RecordingRenderer();
      final platform = _RecordingPlatform();
      final batchRender = Completer<Uint8List>();
      final totalRender = Completer<Uint8List>();
      renderer.queued.addAll([batchRender.future, totalRender.future]);
      final cubit = _cubit(
        run: run,
        builder: builder,
        renderer: renderer,
        platform: platform,
      );

      final first = cubit.generate();
      await _flush();
      final second = cubit.organizationChanged(
        ProductionSheetOrganization.total,
      );
      await _flush();

      expect(cubit.state.organization, ProductionSheetOrganization.total);
      expect(cubit.state.canUsePdfActions, isFalse);
      final totalBytes = Uint8List.fromList([2]);
      totalRender.complete(totalBytes);
      await second;
      batchRender.complete(Uint8List.fromList([1]));
      await first;

      expect(cubit.state.organization, ProductionSheetOrganization.total);
      expect(cubit.state.bytes, same(totalBytes));
      await cubit.close();
    },
  );

  test('recovers from font, builder, and renderer failures', () async {
    final run = buildProductionSheetRun();
    final failures =
        <
          void Function(
            _RecordingBuilder,
            _RecordingRenderer,
            _RecordingPlatform,
          )
        >[
          (_, _, platform) => platform.fontError = StateError('font'),
          (builder, _, _) => builder.error = StateError('builder'),
          (_, renderer, _) => renderer.error = StateError('renderer'),
        ];

    for (final fail in failures) {
      final builder = _RecordingBuilder();
      final renderer = _RecordingRenderer();
      final platform = _RecordingPlatform();
      fail(builder, renderer, platform);
      final cubit = _cubit(
        run: run,
        builder: builder,
        renderer: renderer,
        platform: platform,
      );

      await cubit.organizationChanged(ProductionSheetOrganization.total);

      expect(cubit.state.organization, ProductionSheetOrganization.total);
      expect(cubit.state.status, ProductionSheetStatus.failure);
      expect(cubit.state.bytes, isNull);
      expect(cubit.state.generationError, isA<StateError>());

      platform.fontError = null;
      builder.error = null;
      renderer.error = null;
      await cubit.generate();

      expect(cubit.state.status, ProductionSheetStatus.ready);
      expect(cubit.state.generationError, isNull);
      await cubit.close();
    }
  });

  test('shares and prints the ready state bytes without copying', () async {
    final run = buildProductionSheetRun();
    final builder = _RecordingBuilder();
    final renderer = _RecordingRenderer();
    final platform = _RecordingPlatform()
      ..nextShare = Future.value(false)
      ..nextPrint = Future.value(false);
    final bytes = Uint8List.fromList([7]);
    renderer.nextBytes = bytes;
    final cubit = _cubit(
      run: run,
      builder: builder,
      renderer: renderer,
      platform: platform,
    );
    await cubit.generate();

    await cubit.share();
    await cubit.print();

    expect(platform.sharedBytes.single, same(bytes));
    expect(platform.printedBytes.single, same(bytes));
    expect(platform.sharedFilenames.single, cubit.state.filename);
    expect(platform.printedNames.single, cubit.state.filename);
    expect(cubit.state.actionStatus, ProductionSheetActionStatus.idle);
    expect(cubit.state.actionError, isNull);
    await cubit.close();
  });

  test('keeps ready bytes after share and print exceptions', () async {
    final run = buildProductionSheetRun();
    final builder = _RecordingBuilder();
    final renderer = _RecordingRenderer();
    final platform = _RecordingPlatform();
    final bytes = Uint8List.fromList([8]);
    renderer.nextBytes = bytes;
    final cubit = _cubit(
      run: run,
      builder: builder,
      renderer: renderer,
      platform: platform,
    );
    await cubit.generate();

    platform.shareError = StateError('share');
    await cubit.share();
    expect(cubit.state.actionError, isA<StateError>());
    expect(cubit.state.bytes, same(bytes));
    expect(cubit.state.status, ProductionSheetStatus.ready);

    platform
      ..shareError = null
      ..printError = StateError('print');
    await cubit.print();
    expect(cubit.state.actionError, isA<StateError>());
    expect(cubit.state.bytes, same(bytes));
    await cubit.close();
  });

  test('ignores another action while one is in flight', () async {
    final run = buildProductionSheetRun();
    final builder = _RecordingBuilder();
    final renderer = _RecordingRenderer();
    final platform = _RecordingPlatform();
    final share = Completer<bool>();
    platform.nextShare = share.future;
    final cubit = _cubit(
      run: run,
      builder: builder,
      renderer: renderer,
      platform: platform,
    );
    await cubit.generate();

    final inFlight = cubit.share();
    await cubit.print();
    await cubit.organizationChanged(ProductionSheetOrganization.total);

    expect(cubit.state.actionStatus, ProductionSheetActionStatus.sharing);
    expect(cubit.state.organization, ProductionSheetOrganization.batch);
    expect(platform.printedBytes, isEmpty);
    share.complete(false);
    await inFlight;
    expect(cubit.state.actionStatus, ProductionSheetActionStatus.idle);
    await cubit.close();
  });
}
