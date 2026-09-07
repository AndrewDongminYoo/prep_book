import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';

void main() {
  // The three repository interfaces declare no executable code of their
  // own; only `ProductionRunSummary`'s constructor needs a direct test to
  // keep the 100 percent coverage gate green until the task that implements
  // `ProductionRunRepository` exercises it for real.
  test('a ProductionRunSummary holds the fields it was created with', () {
    final createdAt = DateTime.utc(2026, 9, 7);
    final summary = ProductionRunSummary(
      id: 'run-1',
      recipeId: 'recipe-1',
      recipeRevision: 3,
      targetYield: Quantity.parse('10', Unit.gram),
      createdAt: createdAt,
    );

    expect(summary.id, 'run-1');
    expect(summary.recipeId, 'recipe-1');
    expect(summary.recipeRevision, 3);
    expect(summary.targetYield, Quantity.parse('10', Unit.gram));
    expect(summary.createdAt, createdAt);
  });
}
