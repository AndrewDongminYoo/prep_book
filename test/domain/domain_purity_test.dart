import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no domain source imports Flutter or a platform library', () {
    const banned = <String>[
      'package:flutter/',
      'package:flutter_bloc/',
      'dart:io',
      'dart:ui',
      'package:sqflite',
      'package:pdf',
      'package:http',
    ];

    final domain = Directory('lib/domain');
    expect(domain.existsSync(), isTrue, reason: 'lib/domain must exist');

    final offenders = <String>[];
    for (final entity in domain.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      for (final reference in banned) {
        // Any quoted reference, so a re-export cannot slip past the guard.
        if (source.contains("'$reference")) {
          offenders.add('${entity.path} references $reference');
        }
      }
    }

    expect(offenders, isEmpty);
  });

  test('no domain source uses double', () {
    final domain = Directory('lib/domain');
    final offenders = <String>[];
    for (final entity in domain.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      if (RegExp(r'\bdouble\b').hasMatch(source)) {
        offenders.add(entity.path);
      }
    }

    expect(offenders, isEmpty);
  });
}
