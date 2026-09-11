import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:prep_book/export/export.dart';

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

ProductionSheet _sheet({
  required bool isDraft,
  required List<int> sectionRowCounts,
  ProductionSheetOrganization organization = ProductionSheetOrganization.batch,
}) {
  return ProductionSheet(
    organization: organization,
    labels: _labels,
    recipeName: isDraft ? '긴 한국어 반죽' : 'Bun dough',
    recipeRevision: 4,
    targetYield: '120 kg',
    createdAt: '2026-09-11 04:05 UTC',
    rootBatchCount: 3,
    isDraft: isDraft,
    outstandingWarnings: isDraft
        ? const [ProductionSheetWarning(message: '소금 양을 입력하세요.')]
        : const [],
    acknowledgedWarnings: const [
      ProductionSheetWarning(message: '반올림 값을 확인했습니다.'),
    ],
    sections: [
      for (
        var sectionIndex = 0;
        sectionIndex < sectionRowCounts.length;
        sectionIndex++
      )
        ProductionSheetSection(
          path: sectionIndex == 0 ? 'root' : 'root/$sectionIndex',
          depth: sectionIndex,
          recipeName: 'Section ${sectionIndex + 1} 반죽',
          targetYield: '${sectionIndex + 1} kg',
          batchCount: 3,
          preparationNotes: const ['천천히 섞고 상태를 확인합니다.'],
          tables: [
            ProductionSheetTable(
              heading: 'Batches 1–2',
              batchYield: '40 kg',
              rows: [
                for (
                  var rowIndex = 0;
                  rowIndex < sectionRowCounts[sectionIndex];
                  rowIndex++
                )
                  ProductionSheetRow(
                    label: '재료 ${sectionIndex + 1}-${rowIndex + 1}',
                    note: rowIndex.isEven ? '준비 메모' : null,
                    calculated: '${rowIndex + 1} g',
                    exact: rowIndex.isEven ? '${rowIndex + 0.5} g' : null,
                    actualWholeRun: rowIndex == 0 ? '2 g' : null,
                  ),
              ],
            ),
          ],
        ),
    ],
  );
}

int _pageCount(Uint8List bytes) {
  final source = String.fromCharCodes(bytes);
  return RegExp(r'/Type\s*/Page\b').allMatches(source).length;
}

Iterable<(double, double)> _pageSizes(Uint8List bytes) sync* {
  final source = String.fromCharCodes(bytes);
  final mediaBox = RegExp(
    r'/MediaBox\s*\[\s*0(?:\.0+)?\s+0(?:\.0+)?\s+'
    r'([0-9.]+)\s+([0-9.]+)\s*\]',
  );
  for (final match in mediaBox.allMatches(source)) {
    yield (double.parse(match.group(1)!), double.parse(match.group(2)!));
  }
}

void main() {
  late Uint8List fontBytes;

  setUpAll(() {
    fontBytes = File('assets/fonts/NotoSansKR.ttf').readAsBytesSync();
  });

  test('renders one A4 portrait page for a short final sheet', () async {
    final bytes = await const ProductionSheetPdfRenderer().render(
      _sheet(isDraft: false, sectionRowCounts: const [3]),
      fontBytes: fontBytes,
    );

    expect(bytes.sublist(0, 5), '%PDF-'.codeUnits);
    expect(_pageCount(bytes), 1);
    final pageSizes = _pageSizes(bytes).toList();
    expect(pageSizes, hasLength(1));
    expect(pageSizes.single.$1, closeTo(PdfPageFormat.a4.width, 0.02));
    expect(pageSizes.single.$2, closeTo(PdfPageFormat.a4.height, 0.02));
  });

  test('renders the total organization summary', () async {
    final bytes = await const ProductionSheetPdfRenderer().render(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [1],
        organization: ProductionSheetOrganization.total,
      ),
      fontBytes: fontBytes,
    );

    expect(_pageCount(bytes), 1);
  });

  test('renders a long Korean draft across at least three pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().render(
      _sheet(isDraft: true, sectionRowCounts: const [100]),
      fontBytes: fontBytes,
    );

    expect(_pageCount(bytes), greaterThanOrEqualTo(3));
  });

  test('moves a complete section when it fits on a fresh page', () async {
    final bytes = await const ProductionSheetPdfRenderer().render(
      _sheet(isDraft: false, sectionRowCounts: const [12, 12]),
      fontBytes: fontBytes,
    );

    expect(_pageCount(bytes), greaterThanOrEqualTo(2));
  });

  test('splits an oversized section only across multiple pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().render(
      _sheet(isDraft: false, sectionRowCounts: const [80]),
      fontBytes: fontBytes,
    );

    expect(_pageCount(bytes), greaterThanOrEqualTo(2));
  });

  test('keeps the page plan deterministic across render calls', () async {
    const renderer = ProductionSheetPdfRenderer();
    final sheet = _sheet(isDraft: true, sectionRowCounts: const [100]);

    final first = await renderer.render(sheet, fontBytes: fontBytes);
    final second = await renderer.render(sheet, fontBytes: fontBytes);

    expect(_pageCount(first), _pageCount(second));
  });
}
