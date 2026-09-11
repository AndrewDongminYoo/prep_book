import 'dart:convert';
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
  String? recipeName,
}) {
  return ProductionSheet(
    organization: organization,
    labels: _labels,
    recipeName: recipeName ?? (isDraft ? '긴 한국어 반죽' : 'Bun dough'),
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
          recipeName: 'Section ${sectionIndex + 1} dough',
          targetYield: '${sectionIndex + 1} kg',
          batchCount: 3,
          preparationNotes: const ['Mix slowly and check the dough.'],
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
                    label: 'Ingredient ${sectionIndex + 1}-${rowIndex + 1}',
                    note: rowIndex.isEven ? 'Preparation note' : null,
                    calculated: 'calc-${sectionIndex + 1}-${rowIndex + 1}',
                    exact: rowIndex.isEven
                        ? 'exact-${sectionIndex + 1}-${rowIndex + 1}'
                        : null,
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

List<List<String>> _drawnStringsByPage(Uint8List bytes) {
  final source = utf8.decode(bytes, allowMalformed: true);
  final streams = RegExp(r'stream\r?\n([\s\S]*?)\r?\nendstream');
  final drawnString = RegExp(r'% drawString\("([^"]*)"\)');
  return [
    for (final stream in streams.allMatches(source))
      if (drawnString.allMatches(stream.group(1)!).toList() case final drawn
          when drawn.isNotEmpty)
        [for (final match in drawn) match.group(1)!],
  ];
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

  test('omits wall-clock metadata timestamps', () async {
    final bytes = await const ProductionSheetPdfRenderer().render(
      _sheet(isDraft: false, sectionRowCounts: const [1]),
      fontBytes: fontBytes,
    );
    final source = String.fromCharCodes(bytes);

    expect(source, contains('/Creator(PrepBook)'));
    expect(source, contains('/Title(Bun dough)'));
    expect(source, contains('/Producer(PrepBook'));
    expect(source, isNot(contains('/CreationDate')));
    expect(source, isNot(contains('/ModDate')));
  });

  test('renders a long Korean draft across at least three pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: true,
        sectionRowCounts: const [100],
        recipeName: 'Draft bun dough',
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(_pageCount(bytes)));
    expect(pages, hasLength(greaterThanOrEqualTo(3)));
    for (var index = 0; index < pages.length; index++) {
      final page = pages[index];
      expect(page, contains('DRAFT'));
      expect(page.join(' '), contains('Draft bun dough'));
      expect(
        page,
        containsAllInOrder(['Page', '${index + 1}', 'of', '${pages.length}']),
      );
    }
  });

  test('moves a complete section when it fits on a fresh page', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(isDraft: false, sectionRowCounts: const [12, 12]),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThanOrEqualTo(2)));
    final sectionPages = [
      for (var index = 0; index < pages.length; index++)
        if (pages[index].contains('2-1')) index,
    ];
    expect(sectionPages, hasLength(1));
    final sectionPage = pages[sectionPages.single];
    expect(sectionPage.join(' '), contains('Section 2 dough'));
    for (var row = 1; row <= 12; row++) {
      expect(sectionPage, contains('2-$row'));
      expect(sectionPage, contains('calc-2-$row'));
    }
  });

  test('splits an oversized section only across multiple pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(isDraft: false, sectionRowCounts: const [80]),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThanOrEqualTo(2)));
    for (final page in pages) {
      expect(page.join(' '), contains('Section 1 dough'));
      expect(page, contains('Component'));
      expect(page, contains('Calculated'));
    }
    for (var row = 1; row <= 80; row++) {
      final rowPages = pages.where((page) => page.contains('1-$row')).toList();
      expect(rowPages, hasLength(1), reason: 'row $row must stay intact');
      expect(rowPages.single, contains('calc-1-$row'));
    }
  });

  test('keeps the page plan deterministic across render calls', () async {
    const renderer = ProductionSheetPdfRenderer();
    final sheet = _sheet(isDraft: true, sectionRowCounts: const [100]);

    final first = await renderer.render(sheet, fontBytes: fontBytes);
    final second = await renderer.render(sheet, fontBytes: fontBytes);

    expect(_pageCount(first), _pageCount(second));
  });
}
