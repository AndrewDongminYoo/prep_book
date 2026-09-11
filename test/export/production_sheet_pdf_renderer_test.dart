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
  List<String> preparationNotes = const ['Mix slowly and check the dough.'],
  List<List<String>>? preparationNotesBySection,
  String? componentLabel,
  String? componentNote,
  String? calculatedAmount,
  String? sectionRecipeName,
  String? sectionTargetYield,
  String? batchYield,
  List<ProductionSheetWarning>? outstandingWarnings,
  List<ProductionSheetWarning>? acknowledgedWarnings,
  bool hasTables = true,
}) {
  return ProductionSheet(
    organization: organization,
    labels: _labels,
    runId: '0123456789abcdef0123456789abcdef',
    recipeName: recipeName ?? (isDraft ? '긴 한국어 반죽' : 'Bun dough'),
    recipeRevision: 4,
    targetYield: '120 kg',
    createdAt: '2026-09-11 04:05 UTC',
    rootBatchCount: 3,
    isDraft: isDraft,
    outstandingWarnings:
        outstandingWarnings ??
        (isDraft
            ? const [ProductionSheetWarning(message: '소금 양을 입력하세요.')]
            : const []),
    acknowledgedWarnings:
        acknowledgedWarnings ??
        const [ProductionSheetWarning(message: '반올림 값을 확인했습니다.')],
    sections: [
      for (
        var sectionIndex = 0;
        sectionIndex < sectionRowCounts.length;
        sectionIndex++
      )
        ProductionSheetSection(
          path: sectionIndex == 0 ? 'root' : 'root/$sectionIndex',
          depth: sectionIndex,
          recipeName: sectionIndex == 0 && sectionRecipeName != null
              ? sectionRecipeName
              : 'Section ${sectionIndex + 1} dough',
          targetYield: sectionTargetYield ?? '${sectionIndex + 1} kg',
          batchCount: 3,
          preparationNotes:
              preparationNotesBySection?[sectionIndex] ?? preparationNotes,
          tables: [
            if (hasTables)
              ProductionSheetTable(
                heading: 'Batches 1–2',
                batchYield: batchYield ?? '40 kg',
                rows: [
                  for (
                    var rowIndex = 0;
                    rowIndex < sectionRowCounts[sectionIndex];
                    rowIndex++
                  )
                    ProductionSheetRow(
                      label: rowIndex == 0 && componentLabel != null
                          ? componentLabel
                          : 'Ingredient ${sectionIndex + 1}-'
                                '${rowIndex + 1}',
                      note: rowIndex == 0 && componentNote != null
                          ? componentNote
                          : rowIndex.isEven
                          ? 'Preparation note'
                          : null,
                      calculated: rowIndex == 0 && calculatedAmount != null
                          ? calculatedAmount
                          : 'calc-${sectionIndex + 1}-${rowIndex + 1}',
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

  test('identifies every page when the recipe name is clipped', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [80],
        recipeName: 'shared-prefix-${'가' * 500}',
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(1)));
    for (final page in pages) {
      expect(page.join(), contains('0123456789abcdef0123456789abcdef'));
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

  test('does not create a footer-only page before a section', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [14, 1],
        preparationNotesBySection: [
          const ['first section'],
          [List.generate(46, (_) => 'line').join('\n')],
        ],
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    for (final (pageIndex, page) in pages.indexed) {
      final pageText = page.join(' ');
      final hasBody =
          pageText.contains('Production sheet') ||
          pageText.contains('Acknowledged warnings') ||
          pageText.contains('Section ');
      expect(
        hasBody,
        isTrue,
        reason: 'page $pageIndex contains only the footer: $page',
      );
    }
  });

  test('does not create a footer-only page before a warning block', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [],
        outstandingWarnings: [
          ProductionSheetWarning(
            message: List.generate(50, (_) => 'outstanding line').join('\n'),
          ),
        ],
        acknowledgedWarnings: [
          ProductionSheetWarning(
            message: List.generate(75, (_) => 'acknowledged line').join('\n'),
          ),
        ],
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    for (final (pageIndex, page) in pages.indexed) {
      final pageText = page.join(' ');
      final hasBody =
          pageText.contains('Production sheet') ||
          pageText.contains('Outstanding warnings') ||
          pageText.contains('Acknowledged warnings');
      expect(
        hasBody,
        isTrue,
        reason: 'page $pageIndex contains only the footer: $page',
      );
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
      expect(page, contains('Batches'));
      expect(page.join(' '), contains('Batch yield: 40 kg'));
    }
    for (var row = 1; row <= 80; row++) {
      final rowPages = pages.where((page) => page.contains('1-$row')).toList();
      expect(rowPages, hasLength(1), reason: 'row $row must stay intact');
      expect(rowPages.single, contains('calc-1-$row'));
    }
  });

  test('bounds combined repeated section and batch headers', () async {
    final longUnit = List.filled(40, 'unit').join('\n');
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [80],
        sectionTargetYield: '1 $longUnit',
        batchYield: '40 $longUnit',
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(1)));
    for (var row = 1; row <= 80; row++) {
      final rowPages = pages.where((page) => page.contains('1-$row')).toList();
      expect(rowPages, hasLength(1), reason: 'row $row must stay intact');
      expect(rowPages.single, contains('calc-1-$row'));
    }
  });

  test('splits oversized preparation notes across pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [1],
        preparationNotes: ['note-start-${'가' * 5000}-note-end'],
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(1)));
    final renderedText = pages.expand((page) => page).join(' ');
    expect(renderedText, contains('note-start-'));
    expect(renderedText, contains('-note-end'));
  });

  test(
    'splits oversized notes when a section has no component table',
    () async {
      final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
        _sheet(
          isDraft: false,
          sectionRowCounts: const [0],
          preparationNotes: ['empty-start-${'가' * 5000}-empty-end'],
          hasTables: false,
        ),
        fontBytes: fontBytes,
      );

      final pages = _drawnStringsByPage(bytes);
      expect(pages, hasLength(greaterThan(1)));
      final renderedText = pages.expand((page) => page).join(' ');
      expect(renderedText, contains('empty-start-'));
      expect(renderedText, contains('-empty-end'));
    },
  );

  test('splits oversized component notes across pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [1],
        componentNote: 'component-start-${'가' * 5000}-component-end',
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(1)));
    final renderedText = pages
        .expand((page) => page)
        .join()
        .replaceAll(RegExp(r'\s'), '');
    expect(renderedText, contains('component-start-'));
    expect(renderedText, contains('-component-end'));
  });

  test('splits oversized component labels across pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [1],
        componentLabel: 'label-start-${'가' * 5000}-label-end',
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(1)));
    final renderedText = pages.expand((page) => page).join(' ');
    expect(renderedText, contains('label-start-'));
    expect(renderedText, contains('-label-end'));
  });

  test('splits oversized summary recipe names across pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [1],
        recipeName: 'summary-start-${'가' * 5000}-summary-end',
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(1)));
    final renderedText = pages.expand((page) => page).join(' ');
    expect(renderedText, contains('summary-start-'));
    expect(renderedText, contains('-summary-end'));
  });

  test('splits oversized warning messages across pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [1],
        outstandingWarnings: [
          ProductionSheetWarning(
            message: 'warning-start-${'가' * 5000}-warning-end',
          ),
        ],
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(1)));
    final renderedText = pages.expand((page) => page).join(' ');
    expect(renderedText, contains('warning-start-'));
    expect(renderedText, contains('-warning-end'));
  });

  test('splits oversized section names across pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [1],
        sectionRecipeName: 'section-start-${'가' * 5000}-section-end',
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(1)));
    final renderedText = pages.expand((page) => page).join(' ');
    expect(renderedText, contains('section-start-'));
    expect(renderedText, contains('-section-end'));
  });

  test('splits oversized amount text across pages', () async {
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [1],
        calculatedAmount: 'amount-start-${'가' * 5000}-amount-end',
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(1)));
    final renderedText = pages.expand((page) => page).join(' ');
    expect(renderedText, contains('amount-start-'));
    expect(renderedText, contains('-amount-end'));
  });

  test('renders a valid sheet that needs more than 100 pages', () async {
    final componentNote = [
      'document-start',
      ...List.generate(4200, (index) => 'line-$index'),
      'document-end',
    ].join('\n');
    final bytes = await const ProductionSheetPdfRenderer().renderForTesting(
      _sheet(
        isDraft: false,
        sectionRowCounts: const [1],
        componentNote: componentNote,
      ),
      fontBytes: fontBytes,
    );

    final pages = _drawnStringsByPage(bytes);
    expect(pages, hasLength(greaterThan(100)));
    final renderedText = pages.expand((page) => page).join(' ');
    expect(renderedText, contains('document-start'));
    expect(renderedText, contains('document-end'));
  });

  test('keeps the page plan deterministic across render calls', () async {
    const renderer = ProductionSheetPdfRenderer();
    final sheet = _sheet(isDraft: true, sectionRowCounts: const [100]);

    final first = await renderer.render(sheet, fontBytes: fontBytes);
    final second = await renderer.render(sheet, fontBytes: fontBytes);

    expect(_pageCount(first), _pageCount(second));
  });
}
