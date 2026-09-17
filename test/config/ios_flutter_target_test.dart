import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS configurations preserve the generated Flutter target', () {
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final overrides = RegExp(
      r'^\s*FLUTTER_TARGET\s*=',
      multiLine: true,
    ).allMatches(project);

    expect(
      overrides,
      isEmpty,
      reason: 'project settings must not override the generated test listener',
    );
    expect(project, contains('Flutter/resolve_flutter_target.sh'));
  });

  for (final flavor in ['development', 'staging', 'production']) {
    for (final mode in ['Debug', 'Profile', 'Release']) {
      test('iOS $mode-$flavor replaces stale generated flavor', () async {
        final result = await _resolve(
          configuration: '$mode-$flavor',
          target: 'lib/main_development.dart',
          flavor: 'development',
        );
        expect(result.exitCode, 0, reason: result.stderr.toString());
        expect(result.stdout, 'lib/main_$flavor.dart:$flavor');
      });
    }
  }

  test('iOS build preserves a live integration test listener', () async {
    final directory = await Directory.systemTemp.createTemp(
      'flutter_test_listener.',
    );
    addTearDown(() => directory.delete(recursive: true));
    final listener = File('${directory.path}/listener.dart')..writeAsStringSync('');

    final result = await _resolve(
      configuration: 'Debug-development',
      target: listener.path,
      flavor: 'development',
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, '${listener.path}:development');
  });

  test('iOS build replaces a deleted integration test listener', () async {
    final result = await _resolve(
      configuration: 'Debug-staging',
      target: '${Directory.systemTemp.path}/flutter_test_listener.missing/listener.dart',
      flavor: 'development',
    );
    expect(result.exitCode, 0, reason: result.stderr.toString());
    expect(result.stdout, 'lib/main_staging.dart:staging');
  });
}

Future<ProcessResult> _resolve({
  required String configuration,
  required String target,
  required String flavor,
}) => Process.run(
  'sh',
  [
    '-c',
    r'. ./ios/Flutter/resolve_flutter_target.sh; printf "%s:%s" "$FLUTTER_TARGET" "$FLAVOR"',
  ],
  environment: {
    'CONFIGURATION': configuration,
    'FLUTTER_TARGET': target,
    'FLAVOR': flavor,
  },
);
