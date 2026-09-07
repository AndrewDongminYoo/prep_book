import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';

void main() {
  group('ManualComponentWarning', () {
    test('is equal to another warning for the same recipe and component', () {
      expect(
        const ManualComponentWarning('bread', 'salt'),
        const ManualComponentWarning('bread', 'salt'),
      );
      expect(
        const ManualComponentWarning('bread', 'salt'),
        isNot(const ManualComponentWarning('bread', 'pepper')),
      );
    });

    test('is not equal to a same-named component in a different recipe', () {
      expect(
        const ManualComponentWarning('bread', 'salt'),
        isNot(const ManualComponentWarning('dough', 'salt')),
      );
    });

    test('equal warnings share a hash code', () {
      expect(
        const ManualComponentWarning('bread', 'salt').hashCode,
        const ManualComponentWarning('bread', 'salt').hashCode,
      );
    });

    test('is blocking', () {
      expect(const ManualComponentWarning('bread', 'salt').isBlocking, isTrue);
    });
  });

  group('RoundingAdjustedWarning', () {
    test('is equal to another warning for the same recipe and component', () {
      expect(
        const RoundingAdjustedWarning('bread', 'eggs'),
        const RoundingAdjustedWarning('bread', 'eggs'),
      );
      expect(
        const RoundingAdjustedWarning('bread', 'eggs'),
        isNot(const RoundingAdjustedWarning('cake', 'eggs')),
      );
    });

    test('equal warnings share a hash code', () {
      expect(
        const RoundingAdjustedWarning('bread', 'eggs').hashCode,
        const RoundingAdjustedWarning('bread', 'eggs').hashCode,
      );
    });

    test('is not blocking', () {
      expect(
        const RoundingAdjustedWarning('bread', 'eggs').isBlocking,
        isFalse,
      );
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
