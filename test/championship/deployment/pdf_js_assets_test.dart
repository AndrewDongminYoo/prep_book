import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('points pdf.js at bundled local assets', () {
    final index = File('web/index.html').readAsStringSync();
    final baseUrl = RegExp(
      r'''dartPdfJsBaseUrl\s*=\s*["']([^"']+)["']''',
    ).firstMatch(index)?.group(1);

    expect(baseUrl, isNotNull);
    expect(
      baseUrl,
      startsWith('./assets/'),
      reason: 'dynamic import() requires an explicit relative specifier',
    );
    final baseUri = Uri.parse(baseUrl!);
    expect(baseUri.hasScheme, isFalse);
    expect(baseUri.hasAuthority, isFalse);
    expect(baseUri.path, startsWith('assets/'));
    expect(baseUri.path, endsWith('/'));

    for (final assetName in const [
      'pdf.min.mjs',
      'pdf.worker.min.mjs',
      'LICENSE',
    ]) {
      final asset = File('web/${baseUri.path}$assetName');
      expect(asset.existsSync(), isTrue, reason: '${asset.path} is missing');
      expect(
        asset.lengthSync(),
        greaterThan(1000),
        reason: '${asset.path} is unexpectedly small',
      );
    }
  });
}
