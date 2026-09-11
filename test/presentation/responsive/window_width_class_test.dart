import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/presentation/presentation.dart';

void main() {
  group('windowWidthClassOf', () {
    test('classifies every width at both boundaries', () {
      expect(windowWidthClassOf(599), WindowWidthClass.compact);
      expect(windowWidthClassOf(600), WindowWidthClass.medium);
      expect(windowWidthClassOf(839), WindowWidthClass.medium);
      expect(windowWidthClassOf(840), WindowWidthClass.expanded);
    });

    test('only medium and expanded widths use multiple panes', () {
      expect(WindowWidthClass.compact.usesMultiplePanes, isFalse);
      expect(WindowWidthClass.medium.usesMultiplePanes, isTrue);
      expect(WindowWidthClass.expanded.usesMultiplePanes, isTrue);
    });

    test('large text keeps narrow medium windows on one pane', () {
      expect(usesMultiplePanesAt(600, TextScaler.noScaling), isTrue);
      expect(usesMultiplePanesAt(600, const TextScaler.linear(2)), isTrue);
      expect(usesMultiplePanesAt(600, const TextScaler.linear(3)), isFalse);
      expect(usesMultiplePanesAt(899, const TextScaler.linear(3)), isFalse);
      expect(usesMultiplePanesAt(900, const TextScaler.linear(3)), isTrue);
      expect(usesMultiplePanesAt(1200, const TextScaler.linear(4)), isTrue);
    });
  });
}
