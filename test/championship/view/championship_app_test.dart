import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';

import '../championship_test_harness.dart';

void main() {
  testWidgets('reports each locale after Flutter resolves it', (tester) async {
    final cubit = buildChampionshipTestCubit();
    addTearDown(cubit.close);
    final resolvedLocales = <Locale>[];

    Future<void> pumpWith(Locale locale) => tester.pumpWidget(
      ChampionshipApp(
        cubit: cubit,
        openProductionSheet: ignoreChampionshipProductionSheet,
        locale: locale,
        onResolvedLocale: resolvedLocales.add,
      ),
    );

    await pumpWith(const Locale('en'));
    await tester.pumpAndSettle();
    expect(resolvedLocales, const [Locale('en')]);

    await pumpWith(const Locale('ko'));
    await tester.pumpAndSettle();
    expect(resolvedLocales, const [Locale('en'), Locale('ko')]);
  });
}
