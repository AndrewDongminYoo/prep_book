import 'dart:typed_data';

import 'package:meta/meta.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:prep_book/export/production_sheet/model.dart';

const _bodyFontSize = 9.0;
const _footerHeight = 18.0;
const _smallFontSize = 9.0;
const _sectionFontSize = 12.0;
const _titleFontSize = 18.0;

/// Renders an immutable production sheet as an A4 portrait PDF.
class ProductionSheetPdfRenderer {
  const ProductionSheetPdfRenderer();

  Future<Uint8List> render(
    ProductionSheet sheet, {
    required Uint8List fontBytes,
  }) => _render(sheet, fontBytes: fontBytes);

  /// Renders readable drawing comments for PDF layout regression tests.
  @visibleForTesting
  Future<Uint8List> renderForTesting(
    ProductionSheet sheet, {
    required Uint8List fontBytes,
  }) => _render(sheet, fontBytes: fontBytes, compress: false, verbose: true);

  Future<Uint8List> _render(
    ProductionSheet sheet, {
    required Uint8List fontBytes,
    bool compress = true,
    bool verbose = false,
  }) {
    final font = pw.Font.ttf(ByteData.sublistView(fontBytes));
    final theme = pw.ThemeData.withFont(base: font, bold: font);
    final document =
        pw.Document(
          title: sheet.recipeName,
          creator: 'PrepBook',
          producer: 'PrepBook',
          theme: theme,
          compress: compress,
          verbose: verbose,
        )..addPage(
          pw.MultiPage(
            pageTheme: pw.PageTheme(
              pageFormat: PdfPageFormat.a4,
              orientation: pw.PageOrientation.portrait,
              margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 42),
              theme: theme,
              buildBackground: sheet.isDraft
                  ? (_) => pw.Center(
                      child: pw.Transform.rotate(
                        angle: -0.55,
                        child: pw.Text(
                          sheet.labels.draft,
                          style: const pw.TextStyle(
                            color: PdfColors.grey300,
                            fontSize: 54,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                      ),
                    )
                  : null,
            ),
            footer: (context) => _footer(sheet, context),
            maxPages: 100,
            build: (context) => [
              pw.Inseparable(child: _summary(sheet)),
              if (sheet.outstandingWarnings.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                _keepTogetherFirst(
                  context,
                  _warningTable(
                    sheet.labels.outstandingWarnings,
                    sheet.outstandingWarnings,
                    outstanding: true,
                  ),
                ),
              ],
              if (sheet.acknowledgedWarnings.isNotEmpty) ...[
                pw.SizedBox(height: 10),
                _keepTogetherFirst(
                  context,
                  _warningTable(
                    sheet.labels.acknowledgedWarnings,
                    sheet.acknowledgedWarnings,
                    outstanding: false,
                  ),
                ),
              ],
              for (final section in sheet.sections) ...[
                pw.SizedBox(height: 14),
                _keepTogetherFirst(
                  context,
                  _sectionTable(sheet.labels, section),
                ),
              ],
            ],
          ),
        );
    return document.save();
  }

  pw.Widget _summary(ProductionSheet sheet) {
    final labels = sheet.labels;
    final organization = switch (sheet.organization) {
      ProductionSheetOrganization.batch => labels.batchOrganization,
      ProductionSheetOrganization.total => labels.totalOrganization,
    };
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          labels.documentTitle,
          style: const pw.TextStyle(
            fontSize: _titleFontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Text(
          sheet.recipeName,
          style: const pw.TextStyle(
            fontSize: _sectionFontSize,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 8),
        pw.Table(
          columnWidths: const {
            0: pw.FlexColumnWidth(),
            1: pw.FlexColumnWidth(),
          },
          children: [
            _summaryRow(labels.recipeRevision, '${sheet.recipeRevision}'),
            _summaryRow(labels.targetYield, sheet.targetYield),
            _summaryRow(labels.createdAt, sheet.createdAt),
            _summaryRow(labels.rootBatchCount, '${sheet.rootBatchCount}'),
            _summaryRow(labels.organization, organization),
          ],
        ),
      ],
    );
  }

  pw.TableRow _summaryRow(String label, String value) =>
      pw.TableRow(children: [_cell(label, bold: true), _cell(value)]);

  pw.Widget _warningTable(
    String heading,
    List<ProductionSheetWarning> warnings, {
    required bool outstanding,
  }) {
    final color = outstanding ? PdfColors.orange100 : PdfColors.grey100;
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      children: [
        pw.TableRow(
          repeat: true,
          decoration: pw.BoxDecoration(color: color),
          children: [_cell(heading, bold: true)],
        ),
        for (final warning in warnings)
          pw.TableRow(children: [_cell('• ${warning.message}')]),
      ],
    );
  }

  pw.Widget _sectionTable(
    ProductionSheetLabels labels,
    ProductionSheetSection section,
  ) {
    final indent = section.depth.clamp(0, 6).toDouble() * 10;
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(2),
        1: pw.FlexColumnWidth(1.4),
      },
      children: [
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell(section.recipeName, bold: true, leftPadding: 4 + indent),
            _cell(
              '${labels.sectionTarget}: ${section.targetYield}\n'
              '${labels.sectionBatchCount}: ${section.batchCount}',
              bold: true,
            ),
          ],
        ),
        if (section.preparationNotes.isNotEmpty)
          pw.TableRow(
            children: [
              _cell(labels.preparationNotes, bold: true),
              _cell(section.preparationNotes.join('\n')),
            ],
          ),
        pw.TableRow(
          repeat: true,
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _cell(labels.component, bold: true),
            _cell(labels.calculatedAmount, bold: true),
          ],
        ),
        for (final table in section.tables) ...[
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: PdfColors.blue50),
            children: [
              _cell(table.heading, bold: true),
              _cell(
                table.batchYield == null
                    ? ''
                    : '${labels.batchYield}: ${table.batchYield}',
                bold: true,
              ),
            ],
          ),
          for (final row in table.rows)
            pw.TableRow(
              verticalAlignment: pw.TableCellVerticalAlignment.top,
              children: [
                _cell(
                  row.note == null ? row.label : '${row.label}\n${row.note}',
                  bold: true,
                ),
                _cell(_amountText(labels, row)),
              ],
            ),
        ],
      ],
    );
  }

  String _amountText(ProductionSheetLabels labels, ProductionSheetRow row) {
    return [
      '${labels.calculatedAmount}: ${row.calculated}',
      if (row.exact case final exact?) '${labels.exactAmount}: $exact',
      if (row.actualWholeRun case final actual?)
        '${labels.wholeRunActual}: $actual',
    ].join('\n');
  }

  pw.Widget _cell(String text, {bool bold = false, double leftPadding = 4}) {
    return pw.Padding(
      padding: pw.EdgeInsets.fromLTRB(leftPadding, 4, 4, 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: _bodyFontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _footer(ProductionSheet sheet, pw.Context context) {
    final page = sheet.labels.pagePattern
        .replaceAll('{current}', '${context.pageNumber}')
        .replaceAll('{total}', '${context.pagesCount}');
    return pw.SizedBox(
      height: _footerHeight,
      child: pw.Container(
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: PdfColors.grey400)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Expanded(
              child: pw.Text(
                sheet.recipeName,
                maxLines: 1,
                style: const pw.TextStyle(fontSize: _smallFontSize),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(page, style: const pw.TextStyle(fontSize: _smallFontSize)),
          ],
        ),
      ),
    );
  }

  pw.Widget _keepTogetherFirst(pw.Context context, pw.Widget child) {
    // `Inseparable(canSpan: true)` starts splitting in the current page's
    // remaining space. Measure once at the exact printable width so a block
    // that fits on a fresh page can use the stable non-spanning path instead.
    child.layout(
      context,
      pw.BoxConstraints(maxWidth: PdfPageFormat.a4.width - 72),
    );
    final maxSinglePageHeight =
        PdfPageFormat.a4.height - 36 - 42 - _footerHeight;
    return pw.Inseparable(
      canSpan: child.box!.height > maxSinglePageHeight,
      child: child,
    );
  }
}
