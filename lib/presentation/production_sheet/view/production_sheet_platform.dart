import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

typedef _LoadAsset = Future<ByteData> Function(String key);
typedef _SharePdf =
    Future<bool> Function({required Uint8List bytes, required String filename});
typedef _LayoutPdf =
    Future<bool> Function({
      required LayoutCallback onLayout,
      required String name,
      required PdfPageFormat format,
      required bool dynamicLayout,
    });

/// The platform operations used by the production-sheet feature.
abstract interface class ProductionSheetPlatform {
  Future<Uint8List> loadFontBytes();

  Widget preview({
    required Uint8List bytes,
    required Widget loading,
    required Widget Function(Object error) onError,
  });

  Future<bool> share({required Uint8List bytes, required String filename});

  Future<bool> print({required Uint8List bytes, required String name});
}

/// Adapts bundled assets and the printing plugin to the feature boundary.
final class PrintingProductionSheetPlatform implements ProductionSheetPlatform {
  const PrintingProductionSheetPlatform({
    Future<ByteData> Function(String key)? loadAsset,
    Future<bool> Function({required Uint8List bytes, required String filename})?
    sharePdf,
    Future<bool> Function({
      required LayoutCallback onLayout,
      required String name,
      required PdfPageFormat format,
      required bool dynamicLayout,
    })?
    layoutPdf,
  }) : _injections = (
         loadAsset: loadAsset,
         sharePdf: sharePdf,
         layoutPdf: layoutPdf,
       );

  final ({_LoadAsset? loadAsset, _SharePdf? sharePdf, _LayoutPdf? layoutPdf})
  _injections;

  @override
  Future<Uint8List> loadFontBytes() async {
    final data = await (_injections.loadAsset ?? rootBundle.load)(
      'assets/fonts/NotoSansKR.ttf',
    );
    return Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
  }

  @override
  Widget preview({
    required Uint8List bytes,
    required Widget loading,
    required Widget Function(Object error) onError,
  }) {
    return PdfPreviewCustom(
      build: (_) => bytes,
      loadingWidget: loading,
      onError: (_, error) => onError(error),
    );
  }

  @override
  Future<bool> share({required Uint8List bytes, required String filename}) {
    final sharePdf = _injections.sharePdf ?? Printing.sharePdf;
    return sharePdf(bytes: bytes, filename: filename);
  }

  @override
  Future<bool> print({required Uint8List bytes, required String name}) {
    final layoutPdf = _injections.layoutPdf ?? Printing.layoutPdf;
    return layoutPdf(
      onLayout: (_) => bytes,
      name: name,
      format: PdfPageFormat.a4,
      dynamicLayout: false,
    );
  }
}
