import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowedUriPrefixes = <String>[
  'dart:typed_data',
  'package:meta/',
  'package:pdf/',
  'package:prep_book/domain/',
  'package:prep_book/export/',
];

const _bannedSubstrings = <String>[
  'dart:io',
  'dart:ui',
  'package:flutter/',
  'package:printing/',
  'package:http/',
  'prep_book/application/',
  'prep_book/persistence/',
  'prep_book/presentation/',
];

final _directiveStatement = RegExp(r'\b(?:import|export)\b[^;]*;');
final _quotedUri = RegExp("'([^']*)'|\"([^\"]*)\"");

bool _isAllowedUri(String uri) {
  if (_allowedUriPrefixes.any(uri.startsWith)) return true;
  if (uri.startsWith('package:') || uri.startsWith('dart:')) return false;
  return !uri.contains('../');
}

List<File> _exportFiles() {
  final directory = Directory('lib/export');
  if (!directory.existsSync()) {
    throw StateError('lib/export does not exist, so nothing was checked.');
  }
  final files = directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList();
  if (files.isEmpty) {
    throw StateError(
      'lib/export contains no Dart files, so nothing was checked.',
    );
  }
  return files;
}

void main() {
  test('the export boundary scans existing sources', () {
    expect(_exportFiles(), isNotEmpty);
  });

  test('every export import resolves inside the allowed set', () {
    final offenders = <String>[];
    for (final file in _exportFiles()) {
      final source = file.readAsStringSync();
      for (final statement in _directiveStatement.allMatches(source)) {
        for (final match in _quotedUri.allMatches(statement.group(0)!)) {
          final uri = match.group(1) ?? match.group(2)!;
          if (!_isAllowedUri(uri)) {
            offenders.add('${file.path} references disallowed uri: $uri');
          }
        }
      }
    }
    expect(offenders, isEmpty);
  });

  test('no export source contains a banned substring', () {
    final offenders = <String>[];
    for (final file in _exportFiles()) {
      final source = file.readAsStringSync();
      for (final banned in _bannedSubstrings) {
        if (source.contains(banned)) {
          offenders.add('${file.path} contains banned substring: $banned');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
