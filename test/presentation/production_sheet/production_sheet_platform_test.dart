import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_platform.dart';
import 'package:printing/printing.dart';

void main() {
  testWidgets('loads a copied font and previews the identical PDF bytes', (
    tester,
  ) async {
    final font = Uint8List.fromList([1, 2, 3]);
    final bytes = Uint8List.fromList([4, 5, 6]);
    String? assetKey;
    final platform = PrintingProductionSheetPlatform(
      loadAsset: (key) async {
        assetKey = key;
        return ByteData.sublistView(font);
      },
    );
    const loading = SizedBox(key: Key('loading'));

    final loaded = await platform.loadFontBytes();
    final widget = platform.preview(
      bytes: bytes,
      loading: loading,
      onError: (error) => Text('$error'),
    );
    final preview = widget as PdfPreviewCustom;

    expect(assetKey, 'assets/fonts/NotoSansKR.ttf');
    expect(loaded, font);
    expect(identical(loaded, font), isFalse);
    expect(preview.pageFormat, PdfPageFormat.a4);
    expect(preview.loadingWidget, same(loading));
    expect(await preview.build(PdfPageFormat.a4), same(bytes));
  });

  test('shares the identical bytes and deterministic filename', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    Uint8List? receivedBytes;
    String? receivedFilename;
    final platform = PrintingProductionSheetPlatform(
      sharePdf: ({required bytes, required filename}) async {
        receivedBytes = bytes;
        receivedFilename = filename;
        return true;
      },
    );

    final result = await platform.share(bytes: bytes, filename: 'sheet.pdf');

    expect(result, isTrue);
    expect(receivedBytes, same(bytes));
    expect(receivedFilename, 'sheet.pdf');
  });

  test('prints A4 with a fixed callback over the identical bytes', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    LayoutCallback? receivedLayout;
    String? receivedName;
    PdfPageFormat? receivedFormat;
    bool? receivedDynamicLayout;
    final platform = PrintingProductionSheetPlatform(
      layoutPdf:
          ({
            required onLayout,
            required name,
            required format,
            required dynamicLayout,
          }) async {
            receivedLayout = onLayout;
            receivedName = name;
            receivedFormat = format;
            receivedDynamicLayout = dynamicLayout;
            return true;
          },
    );

    final result = await platform.print(bytes: bytes, name: 'sheet.pdf');

    expect(result, isTrue);
    expect(receivedName, 'sheet.pdf');
    expect(receivedFormat, PdfPageFormat.a4);
    expect(receivedDynamicLayout, isFalse);
    expect(await receivedLayout!(PdfPageFormat.letter), same(bytes));
  });
}
