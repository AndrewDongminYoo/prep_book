import 'package:flutter/material.dart';
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

    expect(find.text('PrepBook AI Recipe Import'), findsOneWidget);
    expect(
      find.text(
        'AI interprets the source. PrepBook calculates the production plan.',
      ),
      findsOneWidget,
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
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the Korean expanded shell at large text scale', (
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

    expect(find.text('PrepBook AI 레시피 가져오기'), findsOneWidget);
    expect(find.text('AI는 원본을 해석합니다. PrepBook은 생산 계획을 계산합니다.'), findsOneWidget);
    for (final label in ['원본', '검토', '목표', '결과']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(
      find.byKey(const ValueKey('championship-expanded-layout')),
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
