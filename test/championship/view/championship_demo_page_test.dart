import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';

import '../championship_test_harness.dart';

void main() {
  testWidgets('shows the English source phase in the compact shell', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cubit = buildChampionshipTestCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      ChampionshipApp(
        cubit: cubit,
        openProductionSheet: ignoreChampionshipProductionSheet,
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('championship-introduction-title')),
          )
          .label,
      'PrepBook AI',
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('championship-introduction-boundary')),
          )
          .label,
      'AI interprets the source. PrepBook calculates the production plan.',
    );
    for (final label in ['Source', 'Review', 'Target', 'Result']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('championship-phase-source')),
          )
          .properties
          .selected,
      isTrue,
    );
    expect(
      find.byKey(const ValueKey('championship-compact-layout')),
      findsOneWidget,
    );
    for (var index = 0; index < 3; index += 1) {
      expect(
        find.byKey(ValueKey('championship-step-connector-$index')),
        findsOneWidget,
      );
    }
    final sample = find.byKey(const ValueKey('source-sample'));
    expect(tester.getRect(sample).bottom, lessThanOrEqualTo(844));
    expect(
      tester.getTopLeft(sample).dy,
      lessThan(
        tester.getTopLeft(find.byKey(const ValueKey('source-mode-selector'))).dy,
      ),
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('championship-phase-source')),
        matching: find.byKey(const ValueKey('championship-workflow-progress')),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  for (final width in [320.0, 600.0]) {
    testWidgets('step connectors remain visible at ${width.toInt()} px', (
      tester,
    ) async {
      tester.view
        ..physicalSize = Size(width, 844)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = buildChampionshipTestCubit();
      addTearDown(cubit.close);
      await tester.pumpWidget(
        ChampionshipApp(
          cubit: cubit,
          openProductionSheet: ignoreChampionshipProductionSheet,
          locale: const Locale('ko'),
        ),
      );
      await tester.pumpAndSettle();

      for (var index = 0; index < 3; index += 1) {
        expect(
          find.byKey(ValueKey('championship-step-connector-$index')),
          findsOneWidget,
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('desktop centers the source workflow and shows Sample', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = buildChampionshipTestCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      ChampionshipApp(
        cubit: cubit,
        openProductionSheet: ignoreChampionshipProductionSheet,
        locale: const Locale('ko'),
      ),
    );
    await tester.pumpAndSettle();

    final phasePanel = find.byKey(const ValueKey('championship-phase-panel'));
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('championship-phase-source')),
        matching: find.byKey(const ValueKey('championship-workflow-progress')),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(phasePanel).width, lessThanOrEqualTo(760));
    expect(tester.getSize(phasePanel).width, greaterThan(700));
    expect(
      tester.getRect(find.byKey(const ValueKey('source-sample'))).bottom,
      lessThanOrEqualTo(900),
    );
    expect((tester.getRect(phasePanel).center.dx - 720).abs(), lessThan(1));
    final grid = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('championship-paper-grid')),
    );
    expect(grid.painter, isNotNull);
    expect(grid.painter!.shouldRepaint(grid.painter!), isFalse);
    for (var index = 0; index < 3; index += 1) {
      final connector = find.byKey(
        ValueKey('championship-step-connector-$index'),
      );
      expect(connector, findsOneWidget);
      expect(tester.getSize(connector).width, greaterThan(20));
    }
    final theme = Theme.of(tester.element(phasePanel));
    final outline = theme.outlinedButtonTheme.style?.side?.resolve({});
    expect(outline?.color, theme.colorScheme.outlineVariant);
    expect(outline?.width, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('review keeps the centered workspace and split field cards', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1440, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final cubit = buildChampionshipTestCubit();
    addTearDown(cubit.close);
    await cubit.loadSample();
    await tester.pumpWidget(
      ChampionshipApp(
        cubit: cubit,
        openProductionSheet: ignoreChampionshipProductionSheet,
        locale: const Locale('ko'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('championship-task-layout')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('championship-brand-header')),
      findsOneWidget,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('championship-phase-panel'))).width,
      lessThanOrEqualTo(760),
    );
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('recipe.name.input'))).dx,
      greaterThan(tester.getTopLeft(find.text('AI 제안').first).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the Korean compact shell at large text scale', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(900, 900)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final cubit = buildChampionshipTestCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      ChampionshipApp(
        cubit: cubit,
        openProductionSheet: ignoreChampionshipProductionSheet,
        locale: const Locale('ko'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('championship-introduction-title')),
          )
          .label,
      'PrepBook AI',
    );
    expect(
      tester
          .getSemantics(
            find.byKey(const ValueKey('championship-introduction-boundary')),
          )
          .label,
      'AI는 원본을 해석합니다. PrepBook은 생산 계획을 계산합니다.',
    );
    for (final label in ['원본', '검토', '목표', '결과']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('championship-compact-layout')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps the root state when the responsive layout changes', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final cubit = buildChampionshipTestCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      ChampionshipApp(
        cubit: cubit,
        openProductionSheet: ignoreChampionshipProductionSheet,
        locale: const Locale('en'),
      ),
    );
    final compactContext = tester.element(
      find.byKey(const ValueKey('championship-demo-content')),
    );
    final compactCubit = compactContext.read<ChampionshipDemoCubit>();
    await cubit.loadSample();
    cubit.updateReview(
      (draft) => draft.editComponentUnit(2, 'g').confirmComponentUnit(2),
    );
    await tester.pumpAndSettle();
    final review = cubit.state.review;

    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpAndSettle();

    final expandedContext = tester.element(
      find.byKey(const ValueKey('championship-demo-content')),
    );
    expect(expandedContext.read<ChampionshipDemoCubit>(), same(compactCubit));
    expect(compactCubit.state.phase, ChampionshipPhase.review);
    expect(compactCubit.state.review, same(review));
    expect(compactCubit.state.review?.components[2].unit.isConfirmed, isTrue);
  });

  testWidgets('phase change restores and identifies the current step', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final cubit = buildChampionshipTestCubit();
    addTearDown(cubit.close);
    await tester.pumpWidget(
      ChampionshipApp(
        cubit: cubit,
        openProductionSheet: ignoreChampionshipProductionSheet,
        locale: const Locale('en'),
      ),
    );
    await tester.pumpAndSettle();

    final scrollable = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byKey(const ValueKey('championship-demo-content')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    scrollable.position.jumpTo(300);
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(0));

    await cubit.loadSample();
    await tester.pumpAndSettle();

    expect(cubit.state.phase, ChampionshipPhase.review);
    expect(scrollable.position.pixels, 0);
    expect(
      FocusManager.instance.primaryFocus?.context,
      tester.element(
        find.byKey(const ValueKey('championship-current-phase-focus')),
      ),
    );
    final currentStep = tester.widget<Semantics>(
      find.byKey(const ValueKey('championship-current-phase-semantics')),
    );
    expect(currentStep.properties.label, 'Current step 2 of 4: Review');
    expect(currentStep.properties.liveRegion, isTrue);
    expect(currentStep.properties.focused, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester
          .widget<Semantics>(
            find.byKey(const ValueKey('championship-current-phase-semantics')),
          )
          .properties
          .focused,
      isFalse,
    );
  });

  for (final width in [840.0, 900.0]) {
    testWidgets('keeps every Korean word together at expanded widths', (
      tester,
    ) async {
      tester.view
        ..physicalSize = Size(width, 900)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final cubit = buildChampionshipTestCubit();
      addTearDown(cubit.close);
      await tester.pumpWidget(
        ChampionshipApp(
          cubit: cubit,
          openProductionSheet: ignoreChampionshipProductionSheet,
          locale: const Locale('ko'),
        ),
      );
      await tester.pumpAndSettle();

      const fullTitle = 'PrepBook AI';
      const fullBoundary = 'AI는 원본을 해석합니다. PrepBook은 생산 계획을 계산합니다.';
      const fullConsent = '아래 개인정보 경계를 확인하고 동의합니다.';
      _expectAtomicWords(
        tester,
        const ValueKey('championship-introduction-title'),
        fullTitle,
        width,
      );
      _expectAtomicWords(
        tester,
        const ValueKey('championship-introduction-boundary'),
        fullBoundary,
        width,
      );
      _expectAtomicWords(
        tester,
        const ValueKey('source-live-consent-label'),
        fullConsent,
        width,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final locale in const [Locale('en'), Locale('ko')]) {
    testWidgets(
      'keeps every ${locale.languageCode} phase usable at 300 percent text',
      (tester) async {
        tester.view
          ..physicalSize = const Size(390, 844)
          ..devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 3;
        addTearDown(tester.view.reset);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final cubit = buildChampionshipTestCubit();
        addTearDown(cubit.close);
        await tester.pumpWidget(
          ChampionshipApp(
            cubit: cubit,
            openProductionSheet: ignoreChampionshipProductionSheet,
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('championship-compact-layout')),
          findsOneWidget,
        );
        expect(find.byKey(const ValueKey('source-text-input')), findsOneWidget);
        expect(tester.takeException(), isNull);

        final sample = find.byKey(const ValueKey('source-sample'));
        await tester.ensureVisible(sample);
        await tester.pumpAndSettle();
        await tester.tap(sample);
        await tester.pumpAndSettle();
        expect(cubit.state.phase, ChampionshipPhase.review);
        expect(tester.takeException(), isNull);

        cubit
          ..confirmAllUnambiguous()
          ..updateReview(
            (draft) => draft.editComponentUnit(2, 'g').confirmComponentUnit(2),
          )
          ..updateReview((draft) => draft.confirmComponentBehavior(3))
          ..continueToTarget();
        await tester.pumpAndSettle();
        expect(cubit.state.phase, ChampionshipPhase.target);
        expect(tester.takeException(), isNull);

        cubit
          ..setTargetAmount('181')
          ..calculate();
        await tester.pumpAndSettle();
        expect(cubit.state.phase, ChampionshipPhase.result);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

void _expectAtomicWords(
  WidgetTester tester,
  Key containerKey,
  String text,
  double width,
) {
  final container = find.byKey(containerKey);
  final wordWidgets = find.descendant(
    of: container,
    matching: find.byType(Text),
  );
  final words = text.split(' ');
  expect(
    tester.widgetList<Text>(wordWidgets).map((widget) => widget.data),
    words,
  );
  for (var index = 0; index < words.length; index += 1) {
    final word = words[index];
    final paragraph = tester.renderObject<RenderParagraph>(
      wordWidgets.at(index),
    );
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: word.length),
    );
    expect(
      boxes.map((box) => box.top.round()).toSet(),
      hasLength(1),
      reason: '`$word` must not split across rendered lines at $width px.',
    );
  }
}
