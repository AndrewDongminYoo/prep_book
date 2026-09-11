import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/production_sheet/view/app_production_sheet_localizations.dart';

Future<AppProductionSheetLocalizations> _load(
  WidgetTester tester,
  Locale locale,
) async {
  late AppProductionSheetLocalizations result;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          result = AppProductionSheetLocalizations(
            localizations: context.l10n,
            locale: Localizations.localeOf(context),
          );
          return const SizedBox();
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
  return result;
}

void main() {
  testWidgets('adapts English export copy and keeps created time in UTC', (
    tester,
  ) async {
    final localizations = await _load(tester, const Locale('en'));

    expect(localizations.labels.documentTitle, 'Production sheet');
    expect(localizations.labels.draft, 'DRAFT');
    expect(localizations.labels.exactAmount, 'Exact');
    expect(localizations.labels.wholeRunActual, 'Whole-run actual');
    expect(localizations.labels.pagePattern, 'Page {current} of {total}');
    expect(localizations.batch(2), 'Batch 2');
    expect(localizations.batchRange(2, 4), 'Batches 2–4');
    expect(
      localizations.formatQuantity(Quantity.parse('1.25', Unit.gram)),
      '1.25 g',
    );

    final createdAt = localizations.formatCreatedAt(
      DateTime.parse('2026-09-11T13:05:00+09:00'),
    );
    expect(createdAt, contains('04:05'));
    expect(createdAt, endsWith(' UTC'));
    expect(createdAt, isNot(contains('13:05')));

    expect(
      localizations.warningMessage(
        warning: const ManualComponentWarning('dough', 'water'),
        recipeName: 'Dough',
        componentName: 'Water',
      ),
      'Water in Dough has no amount yet.',
    );
    expect(
      localizations.warningMessage(
        warning: const RoundingAdjustedWarning('dough', 'salt'),
        recipeName: 'Dough',
        componentName: 'Salt',
      ),
      'Salt in Dough was rounded for display.',
    );
    expect(
      localizations.warningMessage(
        warning: const ArchivedDependencyWarning('dough'),
        recipeName: 'Dough',
      ),
      'Dough is archived.',
    );
  });

  testWidgets('adapts Korean export copy and placeholder order', (
    tester,
  ) async {
    final localizations = await _load(tester, const Locale('ko'));

    expect(localizations.labels.documentTitle, '생산표');
    expect(localizations.labels.draft, '초안');
    expect(localizations.labels.exactAmount, '정확한 값');
    expect(localizations.labels.wholeRunActual, '전체 작업 실제 사용량');
    expect(localizations.labels.pagePattern, '{current}/{total}페이지');
    expect(localizations.batch(2), '배치 2');
    expect(localizations.batchRange(2, 4), '배치 2–4');

    final createdAt = localizations.formatCreatedAt(
      DateTime.parse('2026-09-11T13:05:00+09:00'),
    );
    expect(createdAt, contains('04:05'));
    expect(createdAt, endsWith(' UTC'));
    expect(createdAt, isNot(contains('13:05')));

    expect(
      localizations.warningMessage(
        warning: const ManualComponentWarning('dough', 'water'),
        recipeName: '반죽',
        componentName: '물',
      ),
      '반죽의 물에 아직 수량이 없습니다.',
    );
    expect(
      localizations.warningMessage(
        warning: const RoundingAdjustedWarning('dough', 'salt'),
        recipeName: '반죽',
        componentName: '소금',
      ),
      '반죽의 소금은(는) 표시를 위해 반올림했습니다.',
    );
    expect(
      localizations.warningMessage(
        warning: const ArchivedDependencyWarning('dough'),
        recipeName: '반죽',
      ),
      '반죽은(는) 보관 처리된 레시피입니다.',
    );
  });
}
