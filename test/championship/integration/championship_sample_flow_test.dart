import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';

import '../championship_test_harness.dart';

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sample review produces the exact 180 piece result offline', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(900, 1000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = RecordingRecipeImportClient(
      (_, _) => throw StateError('network must not be called'),
    );
    final cubit = buildChampionshipTestCubit(client: client);
    addTearDown(cubit.close);
    await tester.pumpWidget(
      ChampionshipApp(cubit: cubit, locale: const Locale('en')),
    );

    await _tapVisible(tester, find.byKey(const ValueKey('source-sample')));
    await _tapVisible(tester, find.byKey(const ValueKey('review-confirm-all')));

    final waterUnit = find.byKey(const ValueKey('components[2].unit.input'));
    await _tapVisible(tester, waterUnit);
    await tester.tap(find.text('g').last);
    await tester.pumpAndSettle();
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('components[2].unit.confirm')),
    );
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('components[3].behavior.confirm')),
    );
    await _tapVisible(tester, find.byKey(const ValueKey('review-continue')));

    await tester.enterText(
      find.byKey(const ValueKey('target-amount-input')),
      '180',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('target-calculate')));

    expect(client.requests, isEmpty);
    expect(find.text('15 batches'), findsOneWidget);
    expect(find.text('7500 g'), findsOneWidget);
    expect(find.text('3750 g'), findsOneWidget);
    expect(find.text('3600 g'), findsOneWidget);
    expect(find.text('Manual / as needed'), findsOneWidget);
    expect(find.text('Exact PrepBook calculation'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
