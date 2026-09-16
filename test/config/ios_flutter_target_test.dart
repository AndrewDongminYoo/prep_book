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
  });
}
