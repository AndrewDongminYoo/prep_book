import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/export/export.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_page.dart';
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

final class _RecordingBuilder extends ProductionSheetBuilder {
  final organizations = <ProductionSheetOrganization>[];

  @override
  ProductionSheet build({
    required ProductionRun run,
    required ProductionSheetOrganization organization,
    required ProductionSheetLocalizations localizations,
  }) {
    organizations.add(organization);
    return ProductionSheet(
      organization: organization,
      labels: _labels,
      recipeName: run.recipe.name,
      recipeRevision: run.recipeRevision,
      targetYield: '1000 g',
      createdAt: 'Sep 11, 2026 04:05 UTC',
      rootBatchCount: 1,
      isDraft: false,
      outstandingWarnings: const [],
      acknowledgedWarnings: const [],
      sections: const [],
    );
  }
}

final class _ControlledRenderer extends ProductionSheetPdfRenderer {
  final pending = <Completer<Uint8List>>[];

  @override
  Future<Uint8List> render(
    ProductionSheet sheet, {
    required Uint8List fontBytes,
  }) {
    final completer = Completer<Uint8List>();
    pending.add(completer);
    return completer.future;
  }
}

final class _RecordingPlatform implements ProductionSheetPlatform {
  final previewedBytes = <Uint8List>[];
  final sharedBytes = <Uint8List>[];
  final printedBytes = <Uint8List>[];
  Widget Function(Object error)? previewErrorBuilder;
  Object? shareError;
  Object? printError;
  Completer<bool>? nextShare;
  Completer<bool>? nextPrint;
  bool shareResult = false;
  bool printResult = false;

  @override
  Future<Uint8List> loadFontBytes() async => Uint8List.fromList([1, 2, 3]);

  @override
  Widget preview({
    required Uint8List bytes,
    required Widget loading,
    required Widget Function(Object error) onError,
  }) {
    previewedBytes.add(bytes);
    previewErrorBuilder = onError;
    return const ColoredBox(
      key: ValueKey('fake-pdf-preview'),
      color: Colors.white,
    );
  }

  @override
  Future<bool> share({required Uint8List bytes, required String filename}) {
    sharedBytes.add(bytes);
    final error = shareError;
    if (error != null) return Future.error(error);
    return nextShare?.future ?? Future.value(shareResult);
  }

  @override
  Future<bool> print({required Uint8List bytes, required String name}) {
    printedBytes.add(bytes);
    final error = printError;
    if (error != null) return Future.error(error);
    return nextPrint?.future ?? Future.value(printResult);
  }
}

final class _Harness {
  _Harness()
    : run = buildProductionSheetRun(),
      builder = _RecordingBuilder(),
      renderer = _ControlledRenderer(),
      platform = _RecordingPlatform();

  final ProductionRun run;
  final _RecordingBuilder builder;
  final _ControlledRenderer renderer;
  final _RecordingPlatform platform;
}

Future<void> _open(
  WidgetTester tester,
  _Harness harness, {
  Size size = const Size(599, 900),
  Locale locale = const Locale('en'),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ProductionSheetPage(
        run: harness.run,
        platform: harness.platform,
        builder: harness.builder,
        renderer: harness.renderer,
      ),
    ),
  );
  await tester.pump();
}

SegmentedButton<ProductionSheetOrganization> _organizationControl(
  WidgetTester tester,
) => tester.widget(find.byType(SegmentedButton<ProductionSheetOrganization>));

Future<void> _complete(
  WidgetTester tester,
  _Harness harness,
  int index,
  Uint8List bytes,
) async {
  harness.renderer.pending[index].complete(bytes);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('starts with batch progress and previews the ready bytes', (
    tester,
  ) async {
    final harness = _Harness();
    await _open(tester, harness);

    expect(find.text('Generating PDF…'), findsOneWidget);
    expect(_organizationControl(tester).selected, {
      ProductionSheetOrganization.batch,
    });
    expect(find.byKey(const ValueKey('fake-pdf-preview')), findsNothing);

    final bytes = Uint8List.fromList([4, 5]);
    await _complete(tester, harness, 0, bytes);

    expect(find.byKey(const ValueKey('fake-pdf-preview')), findsOneWidget);
    expect(harness.platform.previewedBytes.last, same(bytes));
    final error = harness.platform.previewErrorBuilder!(StateError('preview'));
    expect(((error as Center).child! as Text).data, contains('could not'));
    expect(
      tester
          .widget<ButtonStyleButton>(find.widgetWithText(FilledButton, 'Share'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.widgetWithText(OutlinedButton, 'Print'),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('labels share and print while each action is in flight', (
    tester,
  ) async {
    final harness = _Harness();
    await _open(tester, harness);
    await _complete(tester, harness, 0, Uint8List.fromList([6]));

    final share = Completer<bool>();
    harness.platform.nextShare = share;
    await tester.tap(find.text('Share'));
    await tester.pump();
    expect(find.text('Sharing…'), findsOneWidget);
    share.complete(false);
    await tester.pumpAndSettle();

    final print = Completer<bool>();
    harness.platform.nextPrint = print;
    await tester.tap(find.text('Print'));
    await tester.pump();
    expect(find.text('Printing…'), findsOneWidget);
    print.complete(false);
    await tester.pumpAndSettle();
  });

  testWidgets('keeps total selected while its PDF is generated', (
    tester,
  ) async {
    final harness = _Harness();
    await _open(tester, harness);
    await _complete(tester, harness, 0, Uint8List.fromList([1]));

    await tester.tap(find.text('Totals'));
    await tester.pump();

    expect(_organizationControl(tester).selected, {
      ProductionSheetOrganization.total,
    });
    expect(find.text('Generating PDF…'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-pdf-preview')), findsNothing);
  });

  testWidgets('generation failure hides PDF actions and retry recovers', (
    tester,
  ) async {
    final harness = _Harness();
    await _open(tester, harness);

    harness.renderer.pending.single.completeError(StateError('render'));
    await tester.pumpAndSettle();

    expect(
      find.text('The production sheet could not be generated.'),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Share'), findsNothing);
    expect(find.text('Print'), findsNothing);
    expect(find.byKey(const ValueKey('fake-pdf-preview')), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    expect(find.text('Generating PDF…'), findsOneWidget);
    await _complete(tester, harness, 1, Uint8List.fromList([8]));
    expect(find.byKey(const ValueKey('fake-pdf-preview')), findsOneWidget);
  });

  testWidgets('action errors keep preview and cancellation clears errors', (
    tester,
  ) async {
    final harness = _Harness();
    await _open(tester, harness);
    final bytes = Uint8List.fromList([7]);
    await _complete(tester, harness, 0, bytes);

    harness.platform.shareError = StateError('share');
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(
      find.text('The production sheet could not be shared.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('fake-pdf-preview')), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(
            find.widgetWithText(OutlinedButton, 'Print'),
          )
          .onPressed,
      isNotNull,
    );

    harness.platform.shareError = null;
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();
    expect(
      find.text('The production sheet could not be shared.'),
      findsNothing,
    );
    expect(harness.platform.sharedBytes.last, same(bytes));

    harness.platform.printError = StateError('print');
    await tester.tap(find.text('Print'));
    await tester.pumpAndSettle();
    expect(find.text('The print service could not be opened.'), findsOneWidget);
    expect(find.byKey(const ValueKey('fake-pdf-preview')), findsOneWidget);
    expect(
      tester
          .widget<ButtonStyleButton>(find.widgetWithText(FilledButton, 'Share'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('switches panes at 600 pixels without regenerating', (
    tester,
  ) async {
    final harness = _Harness();
    await _open(tester, harness);
    await _complete(tester, harness, 0, Uint8List.fromList([1]));
    await tester.tap(find.text('Totals'));
    await tester.pump();
    final totalBytes = Uint8List.fromList([2]);
    await _complete(tester, harness, 1, totalBytes);

    expect(
      find.byKey(const ValueKey('production-sheet-compact')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('production-sheet-preview-pane')),
      findsNothing,
    );

    tester.view.physicalSize = const Size(600, 900);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('production-sheet-compact')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('production-sheet-controls-pane')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('production-sheet-preview-pane')),
      findsOneWidget,
    );
    expect(harness.builder.organizations, [
      ProductionSheetOrganization.batch,
      ProductionSheetOrganization.total,
    ]);
    expect(harness.platform.previewedBytes.last, same(totalBytes));
    expect(_organizationControl(tester).selected, {
      ProductionSheetOrganization.total,
    });
  });

  for (final locale in [const Locale('en'), const Locale('ko')]) {
    testWidgets('${locale.languageCode} compact layout survives 300% text', (
      tester,
    ) async {
      final harness = _Harness();
      await _open(
        tester,
        harness,
        size: const Size(360, 640),
        locale: locale,
        textScale: 3,
      );
      await _complete(tester, harness, 0, Uint8List.fromList([3]));

      expect(
        find.byKey(const ValueKey('production-sheet-compact')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
