import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/export/export.dart';

import 'fixtures.dart';

void main() {
  final fixedTime = DateTime.utc(2026, 9, 11, 4, 5, 6);

  test('uses the recipe name and UTC creation timestamp', () {
    expect(
      buildProductionSheetFilename(runNamed('Bun', fixedTime)),
      'production-sheet-Bun-20260911T040506Z.pdf',
    );
    expect(
      buildProductionSheetFilename(
        runNamed('Bun', DateTime.parse('2026-09-11T13:05:06+09:00')),
      ),
      'production-sheet-Bun-20260911T040506Z.pdf',
    );
  });

  test('preserves Unicode and replaces unsafe filename characters', () {
    expect(
      buildProductionSheetFilename(runNamed('소금 / 반죽', fixedTime)),
      contains('소금-반죽'),
    );
    expect(
      buildProductionSheetFilename(
        runNamed('A\u0000B / C\\D:E*F?G"H<I>J|K', fixedTime),
      ),
      'production-sheet-A-B-C-D-E-F-G-H-I-J-K-20260911T040506Z.pdf',
    );
  });

  test('collapses separators and trims edge punctuation', () {
    expect(
      buildProductionSheetFilename(
        runNamed(' ..  morning   --  buns... ', fixedTime),
      ),
      'production-sheet-morning-buns-20260911T040506Z.pdf',
    );
  });

  test('uses the fallback when sanitization removes the whole name', () {
    expect(
      buildProductionSheetFilename(runNamed('///', fixedTime)),
      'production-sheet-production-run-20260911T040506Z.pdf',
    );
  });

  test('limits the recipe segment to 80 Unicode code points', () {
    final filename = buildProductionSheetFilename(
      runNamed('${'a' * 79}bc', fixedTime),
    );
    final segment = filename
        .replaceFirst('production-sheet-', '')
        .replaceFirst('-20260911T040506Z.pdf', '');

    expect(segment.runes, hasLength(80));
    expect(segment, '${'a' * 79}b');
  });

  test('limits the complete filename to 255 UTF-8 bytes', () {
    final filename = buildProductionSheetFilename(
      runNamed('가' * 80, fixedTime),
    );
    final segment = filename
        .replaceFirst('production-sheet-', '')
        .replaceFirst('-20260911T040506Z.pdf', '');

    expect(utf8.encode(filename), hasLength(lessThanOrEqualTo(255)));
    expect(segment, '가' * 72);
  });
}
