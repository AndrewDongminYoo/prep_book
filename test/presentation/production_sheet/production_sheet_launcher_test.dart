import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_launcher.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_page.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_platform.dart';

import '../../export/fixtures.dart';

final class _PendingPlatform implements ProductionSheetPlatform {
  final _font = Completer<Uint8List>();

  @override
  Future<Uint8List> loadFontBytes() => _font.future;

  @override
  Widget preview({
    required Uint8List bytes,
    required Widget loading,
    required Widget Function(Object error) onError,
  }) => const SizedBox();

  @override
  Future<bool> print({required Uint8List bytes, required String name}) =>
      Future.value(false);

  @override
  Future<bool> share({required Uint8List bytes, required String filename}) =>
      Future.value(false);
}

void main() {
  testWidgets('pushes a page with the identical run and platform', (
    tester,
  ) async {
    final run = buildProductionSheetRun();
    final platform = _PendingPlatform();
    final launcher = ProductionSheetLauncher(platform: platform);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => unawaited(launcher.open(context, run: run)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final page = tester.widget<ProductionSheetPage>(
      find.byType(ProductionSheetPage),
    );
    expect(page.run, same(run));
    expect(page.platform, same(platform));
  });
}
