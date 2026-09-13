import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';

void main() {
  testWidgets('shows the English source phase in the compact shell', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const ChampionshipApp(locale: Locale('en')));
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

    await tester.pumpWidget(const ChampionshipApp(locale: Locale('ko')));
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

    await tester.pumpWidget(const ChampionshipApp(locale: Locale('en')));
    final compactContext = tester.element(
      find.byKey(const ValueKey('championship-demo-content')),
    );
    final compactCubit = compactContext.read<ChampionshipDemoCubit>();

    tester.view.physicalSize = const Size(900, 900);
    await tester.pumpAndSettle();

    final expandedContext = tester.element(
      find.byKey(const ValueKey('championship-demo-content')),
    );
    expect(expandedContext.read<ChampionshipDemoCubit>(), same(compactCubit));
    expect(compactCubit.state, ChampionshipPhase.source);
  });
}
