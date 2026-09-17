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

  test('normal CI gates the endpoint and championship release build', () {
    final workflow = File('.github/workflows/main.yaml').readAsStringSync();
    final config =
        jsonDecode(File('vercel.json').readAsStringSync())
            as Map<String, Object?>;
    final buildJob = RegExp(
      r'^  build:\n(.*?)(?=^  [\w-]+:\n|\z)',
      multiLine: true,
      dotAll: true,
    ).firstMatch(workflow)?.group(1);

    expect(buildJob, isNotNull);
    final setupBlocks = RegExp(
      r'^ {6}setup: \|\n((?: {8}.+(?:\n|$))+)',
      multiLine: true,
    ).allMatches(buildJob!).toList();

    expect(setupBlocks, hasLength(1));
    final setupCommands = setupBlocks.single
        .group(1)!
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map((line) => line.trim())
        .toList();
    expect(setupCommands, ['npm run test:api', config['buildCommand']]);
    expect(
      File('merry.yaml').readAsStringSync(),
      contains('(scripts): ${config['buildCommand']}'),
    );
    expect(
      File('lib/main_championship.dart').readAsStringSync(),
      contains("defaultValue: '/api/extract-recipe'"),
    );
  });
}
