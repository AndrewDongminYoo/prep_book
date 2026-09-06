import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('ManualComponentWarning', () {
    test('is equal to another warning for the same component', () {
      expect(
        const ManualComponentWarning('salt'),
        const ManualComponentWarning('salt'),
      );
      expect(
        const ManualComponentWarning('salt'),
        isNot(const ManualComponentWarning('pepper')),
      );
    });

    test('equal warnings share a hash code', () {
      expect(
        const ManualComponentWarning('salt').hashCode,
        const ManualComponentWarning('salt').hashCode,
      );
    });

    test('is blocking', () {
      expect(const ManualComponentWarning('salt').isBlocking, isTrue);
    });
  });

  group('RoundingAdjustedWarning', () {
    test('equal warnings share a hash code', () {
      expect(
        const RoundingAdjustedWarning('eggs').hashCode,
        const RoundingAdjustedWarning('eggs').hashCode,
      );
    });

    test('is not blocking', () {
      expect(const RoundingAdjustedWarning('eggs').isBlocking, isFalse);
    });
  });

  group('ArchivedDependencyWarning', () {
    test('carries the archived recipe id and is blocking', () {
      const warning = ArchivedDependencyWarning('dough');
      expect(warning.recipeId, 'dough');
      expect(warning.isBlocking, isTrue);
    });

    test('is equal to another warning for the same recipe', () {
      expect(
        const ArchivedDependencyWarning('dough'),
        const ArchivedDependencyWarning('dough'),
      );
      expect(
        const ArchivedDependencyWarning('dough'),
        isNot(const ArchivedDependencyWarning('starter')),
      );
    });

    test('equal warnings share a hash code', () {
      expect(
        const ArchivedDependencyWarning('dough').hashCode,
        const ArchivedDependencyWarning('dough').hashCode,
      );
    });
  });
}
