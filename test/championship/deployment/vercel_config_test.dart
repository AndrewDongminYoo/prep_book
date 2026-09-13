import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds the championship SPA without rewriting API requests', () {
    final config =
        jsonDecode(File('vercel.json').readAsStringSync())
            as Map<String, Object?>;

    expect(
      config['buildCommand'],
      'flutter build web --release --target lib/main_championship.dart '
      '--dart-define=AI_IMPORT_ENDPOINT=/api/extract-recipe '
      '--tree-shake-icons',
    );
    expect(config['outputDirectory'], 'build/web');
    expect(config['functions'], {
      'api/extract-recipe.mjs': {'maxDuration': 30},
    });
    expect(config['rewrites'], [
      {'source': r'/((?!api(?:/|$)).*)', 'destination': '/index.html'},
    ]);
  });

  test('excludes local and private artifacts but keeps deployment inputs', () {
    final ignored = File('.vercelignore').readAsLinesSync().toSet();

    expect(
      ignored,
      containsAll({
        'android',
        'ios',
        'linux',
        'macos',
        'windows',
        'test',
        'coverage',
        'docs',
        'build',
        '.dart_tool',
        '.env*',
        '*.pem',
        '*.key',
      }),
    );
    for (final requiredInput in const [
      'lib',
      'assets',
      'api',
      'web',
      'pubspec.yaml',
    ]) {
      expect(ignored, isNot(contains(requiredInput)));
    }
  });
}
