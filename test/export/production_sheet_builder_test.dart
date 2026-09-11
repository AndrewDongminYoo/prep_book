import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/export/export.dart';

import 'fixtures.dart';

final class _EnglishSheetLocalizations implements ProductionSheetLocalizations {
  const _EnglishSheetLocalizations();

  @override
  ProductionSheetLabels get labels => const ProductionSheetLabels(
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

  @override
  String batch(int number) => 'Batch $number';

  @override
  String batchRange(int first, int last) => 'Batches $first–$last';

  @override
  String formatCreatedAt(DateTime createdAtUtc) =>
      createdAtUtc.toIso8601String();

  @override
  String formatQuantity(Quantity quantity) =>
      '${quantity.toDecimal()} ${quantity.unit.symbol}';

  @override
  String warningMessage({
    required ProductionWarning warning,
    required String recipeName,
    String? componentName,
  }) => '$recipeName:${componentName ?? '-'}:${warning.runtimeType}';
}

const _localizations = _EnglishSheetLocalizations();
const _builder = ProductionSheetBuilder();

void main() {
  group('ProductionSheetBuilder', () {
    test('groups equal full batches and separates the remainder', () {
      final sheet = _builder.build(
        run: buildProductionSheetRun(),
        organization: ProductionSheetOrganization.batch,
        localizations: _localizations,
      );

      expect(sheet.organization, ProductionSheetOrganization.batch);
      expect(sheet.rootBatchCount, 3);
      expect(sheet.sections.first.tables, hasLength(2));
      expect(sheet.sections.first.tables.first.heading, 'Batches 1–2');
      expect(sheet.sections.first.tables.first.batchYield, '4 g');
      expect(sheet.sections.first.tables.last.heading, 'Batch 3');
      expect(sheet.sections.first.tables.last.batchYield, '2 g');

      final flour = sheet.sections.first.tables.first.rows.first;
      expect(flour.label, 'Bread flour');
      expect(flour.note, 'Sift first.');
      expect(flour.calculated, '6 g');
      expect(flour.exact, '4 g');
    });

    test('uses stored totals and preserves manual and override meaning', () {
      final sheet = _builder.build(
        run: buildProductionSheetRun(),
        organization: ProductionSheetOrganization.total,
        localizations: _localizations,
      );

      final table = sheet.sections.first.tables.single;
      expect(table.heading, 'Totals');
      expect(table.batchYield, isNull);
      expect(table.rows.first.calculated, '15 g');
      expect(table.rows.first.exact, '10 g');

      final manual = table.rows.last;
      expect(manual.label, 'Sea salt');
      expect(manual.calculated, 'Manual amount');
      expect(manual.exact, isNull);
      expect(manual.actualWholeRun, '7 g');
    });

    test('keeps repeated sub-recipes as depth-first occurrence sections', () {
      final sheet = _builder.build(
        run: buildProductionSheetRun(),
        organization: ProductionSheetOrganization.batch,
        localizations: _localizations,
      );

      expect(sheet.sections.map((section) => section.path), [
        'root',
        'root/1',
        'root/2',
      ]);
      expect(sheet.sections.map((section) => section.depth), [0, 1, 1]);
      expect(sheet.sections.map((section) => section.recipeName), [
        'Bun dough',
        'Starter',
        'Starter',
      ]);
      expect(sheet.sections.map((section) => section.targetYield), [
        '10 g',
        '2 g',
        '3 g',
      ]);
      expect(sheet.sections[1].preparationNotes, ['Feed before use.']);
      expect(sheet.sections[1].tables.single.rows.last.calculated, '1 packet');
      expect(sheet.sections[2].tables.single.rows.last.calculated, '1 packet');
    });

    test('falls back to stored identifiers when names are unavailable', () {
      final sheet = _builder.build(
        run: buildProductionSheetRunWithoutNames(),
        organization: ProductionSheetOrganization.total,
        localizations: _localizations,
      );

      expect(sheet.sections[1].recipeName, 'child');
      expect(sheet.sections[1].preparationNotes, isEmpty);
      expect(sheet.sections.first.tables.single.rows.first.label, 'flour');
      expect(
        sheet.sections[1].tables.single.rows.first.label,
        'child-ingredient',
      );
    });

    test('separates warnings in stored order and derives draft state', () {
      final draft = _builder.build(
        run: buildProductionSheetRun(),
        organization: ProductionSheetOrganization.batch,
        localizations: _localizations,
      );
      final finalSheet = _builder.build(
        run: buildProductionSheetRun(acknowledgeManual: true),
        organization: ProductionSheetOrganization.batch,
        localizations: _localizations,
      );

      expect(draft.isDraft, isTrue);
      expect(draft.outstandingWarnings.single.message, contains('Sea salt'));
      expect(
        draft.acknowledgedWarnings.single.message,
        contains('Bread flour'),
      );
      expect(finalSheet.isDraft, isFalse);
      expect(finalSheet.outstandingWarnings, isEmpty);
      expect(
        finalSheet.acknowledgedWarnings.map((warning) => warning.message),
        [contains('Bread flour'), contains('Sea salt')],
      );
    });

    test('copies every collection into an unmodifiable value', () {
      final sheet = _builder.build(
        run: buildProductionSheetRun(),
        organization: ProductionSheetOrganization.batch,
        localizations: _localizations,
      );

      expect(
        () => sheet.sections.add(sheet.sections.first),
        throwsUnsupportedError,
      );
      expect(
        () =>
            sheet.sections.first.tables.add(sheet.sections.first.tables.first),
        throwsUnsupportedError,
      );
      expect(
        () => sheet.sections.first.tables.first.rows.add(
          sheet.sections.first.tables.first.rows.first,
        ),
        throwsUnsupportedError,
      );
      expect(
        () => sheet.sections.first.preparationNotes.add('Changed'),
        throwsUnsupportedError,
      );
    });
  });
}
