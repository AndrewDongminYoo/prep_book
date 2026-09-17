import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';

final class _HistoryRepository implements ProductionRunRepository {
  List<ProductionRunSummary> summaries = const [];
  final Map<String, ProductionRun> stored = {};
  Completer<List<ProductionRunSummary>>? pendingList;
  Object? listError;
  Object? openError;
  int listCalls = 0;

  @override
  Future<List<ProductionRunSummary>> listSummaries() {
    listCalls++;
    final error = listError;
    if (error != null) return Future.error(error);
    return pendingList?.future ?? Future.value(summaries);
  }

  @override
  Future<ProductionRun?> findById(String id) {
    final error = openError;
    if (error != null) return Future.error(error);
    return Future.value(stored[id]);
  }

  @override
  Future<void> recordAcknowledgement(String runId, ProductionWarning warning) =>
      throw UnimplementedError();

  @override
  Future<void> recordOverride(String runId, OverrideKey key, Quantity value) =>
      throw UnimplementedError();

  @override
  Future<void> save(ProductionRun run) => throw UnimplementedError();
}

final class _SheetPlatform implements ProductionSheetPlatform {
  @override
  Future<Uint8List> loadFontBytes() async => Uint8List(0);

  @override
  Widget preview({
    required Uint8List bytes,
    required Widget loading,
    required Widget Function(Object error) onError,
  }) => const Text('PDF preview');

  @override
  Future<bool> print({required Uint8List bytes, required String name}) async =>
      true;

  @override
  Future<bool> share({
    required Uint8List bytes,
    required String filename,
  }) async => true;
}

ProductionRun _storedRun({required String id}) {
  final recipe = buildRecipeWithManualComponent(id: 'morning-rolls');
  final target = Quantity.parse('12', Unit.count('roll'));
  final storedRecipe = Recipe(
    id: recipe.id,
    revision: 3,
    name: 'Morning rolls',
    baseYield: target,
    modifiedAt: recipe.modifiedAt,
    components: recipe.components,
  );
  final result = const ProductionCalculator().calculate(
    recipe: storedRecipe,
    targetYield: target,
  );
  return ProductionRun(
    id: id,
    createdAt: DateTime.utc(2026, 9, 15, 23),
    recipe: storedRecipe,
    dependencySnapshot: const {},
    targetYield: target,
    result: result,
  );
}

ProductionRunSummary _summary({String id = 'run-1', bool isDraft = true}) =>
    ProductionRunSummary(
      id: id,
      recipeId: 'morning-rolls',
      recipeName: 'Morning rolls',
      recipeRevision: 3,
      targetYield: Quantity.parse('12', Unit.count('roll')),
      createdAt: DateTime.utc(2026, 9, 15, 23),
      isDraft: isDraft,
    );

Widget _screen(
  _HistoryRepository repository, {
  Locale locale = const Locale('en'),
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: ProductionHistoryPage(
    listHistory: ListProductionHistory(repository),
    openProductionRun: OpenProductionRun(repository),
    productionSheet: ProductionSheetLauncher(platform: _SheetPlatform()),
  ),
);

void main() {
  for (final viewport in [const Size(390, 844), const Size(1000, 900)]) {
    testWidgets('history stays readable at 300 percent text in $viewport', (
      tester,
    ) async {
      tester.view
        ..physicalSize = viewport
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final repository = _HistoryRepository()..summaries = [_summary()];

      await tester.pumpWidget(_screen(repository));
      await tester.pump();
      final normalTitleHeight = tester
          .getSize(find.text('Morning rolls'))
          .height;
      tester.platformDispatcher.textScaleFactorTestValue = 3;
      await tester.pumpAndSettle();

      expect(
        MediaQuery.textScalerOf(
          tester.element(find.text('Morning rolls')),
        ).scale(10),
        30,
      );
      expect(
        tester.getSize(find.text('Morning rolls')).height,
        greaterThan(normalTitleHeight * 2.5),
      );

      for (final label in ['Morning rolls', 'Revision 3', '12 roll', 'Draft']) {
        final text = find.text(label);
        await tester.ensureVisible(text);
        await tester.pumpAndSettle();
        final rect = tester.getRect(text);
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(viewport.width));
        expect(rect.top, greaterThanOrEqualTo(0));
        expect(rect.bottom, lessThanOrEqualTo(viewport.height));
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)).first,
        );
        expect(paragraph.didExceedMaxLines, isFalse, reason: label);
      }
      expect(tester.takeException(), isNull);

      await tester.ensureVisible(find.text('Morning rolls'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Morning rolls'));
      await tester.pump();
      expect(
        find.text('This production run is no longer available.'),
        findsOneWidget,
      );
    });
  }

  testWidgets('history row meets compact tap target guidance', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final semantics = tester.ensureSemantics();
    try {
      final repository = _HistoryRepository()..summaries = [_summary()];

      await tester.pumpWidget(_screen(repository));
      await tester.pump();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('shows loading and then the empty state', (tester) async {
    final repository = _HistoryRepository()
      ..pendingList = Completer<List<ProductionRunSummary>>();
    await tester.pumpWidget(_screen(repository));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    repository.pendingList!.complete(const []);
    await tester.pump();

    expect(find.text('No production runs yet.'), findsOneWidget);
  });

  testWidgets('retries a failed history read', (tester) async {
    final repository = _HistoryRepository()..listError = StateError('broken');
    await tester.pumpWidget(_screen(repository));
    await tester.pump();

    expect(
      find.text('Production history could not be loaded.'),
      findsOneWidget,
    );
    repository
      ..listError = null
      ..summaries = [_summary()];
    await tester.tap(find.widgetWithText(FilledButton, 'Try again'));
    await tester.pump();

    expect(repository.listCalls, 2);
    expect(find.text('Morning rolls'), findsOneWidget);
  });

  testWidgets('shows stored summary fields in English and Korean', (
    tester,
  ) async {
    final repository = _HistoryRepository()..summaries = [_summary()];
    await tester.pumpWidget(_screen(repository));
    await tester.pump();

    expect(find.text('Production history'), findsOneWidget);
    expect(find.text('Morning rolls'), findsOneWidget);
    expect(find.text('Revision 3'), findsOneWidget);
    expect(find.text('12 roll'), findsOneWidget);
    expect(find.text('Draft'), findsOneWidget);

    await tester.pumpWidget(_screen(repository, locale: const Locale('ko')));
    await tester.pump();

    expect(find.text('생산 이력'), findsOneWidget);
    expect(find.text('3차 버전'), findsOneWidget);
    expect(find.text('초안'), findsOneWidget);
  });

  testWidgets('separates rows and labels a ready run', (tester) async {
    final repository = _HistoryRepository()
      ..summaries = [_summary(), _summary(id: 'run-2', isDraft: false)];
    await tester.pumpWidget(_screen(repository));
    await tester.pump();

    expect(find.byType(Divider), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);
  });

  testWidgets('opens the exact stored snapshot in the sheet route', (
    tester,
  ) async {
    final run = _storedRun(id: 'run-1');
    final repository = _HistoryRepository()
      ..summaries = [_summary()]
      ..stored[run.id] = run;
    await tester.pumpWidget(_screen(repository));
    await tester.pump();

    await tester.tap(find.text('Morning rolls'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final sheet = tester.widget<ProductionSheetPage>(
      find.byType(ProductionSheetPage),
    );
    expect(sheet.run, same(run));
  });

  testWidgets('a missing stored run stays on history and reports the loss', (
    tester,
  ) async {
    final repository = _HistoryRepository()..summaries = [_summary()];
    await tester.pumpWidget(_screen(repository));
    await tester.pump();

    await tester.tap(find.text('Morning rolls'));
    await tester.pump();

    expect(find.byType(ProductionSheetPage), findsNothing);
    expect(
      find.text('This production run is no longer available.'),
      findsOneWidget,
    );
  });

  testWidgets('an unreadable stored run stays on history and reports failure', (
    tester,
  ) async {
    final repository = _HistoryRepository()
      ..summaries = [_summary()]
      ..openError = StateError('corrupt');
    await tester.pumpWidget(_screen(repository));
    await tester.pump();

    await tester.tap(find.text('Morning rolls'));
    await tester.pump();

    expect(find.byType(ProductionSheetPage), findsNothing);
    expect(
      find.text('This production run could not be opened.'),
      findsOneWidget,
    );
  });
}
