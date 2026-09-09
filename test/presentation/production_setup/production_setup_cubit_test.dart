import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../fakes.dart';

final _piece = Unit.count('piece');
final _tray = Unit.namedYield('tray');

/// A recipe yielding a kilogram of dough.
///
/// The base yield is 1000 g rather than a round 1, so no expectation below
/// can confuse a scale ratio with an amount.
Recipe _dough({bool isArchived = false}) => buildRecipe(
  id: 'dough',
  name: 'Dough',
  isArchived: isArchived,
  baseYield: Quantity.parse('1000', Unit.gram),
);

/// A recipe whose 400 g maximum splits a 1000 g run into batches.
Recipe _sheeted() => Recipe(
  id: 'dough',
  revision: 1,
  name: 'Dough',
  baseYield: Quantity.parse('1000', Unit.gram),
  maxBatchYield: Quantity.parse('400', Unit.gram),
  modifiedAt: DateTime.utc(2026, 9, 8),
  components: const [],
);

/// A recipe consuming [dependency]'s output.
Recipe _filled(String dependency) => buildRecipe(
  id: 'filled',
  name: 'Filled bun',
  baseYield: Quantity.parse('1000', Unit.gram),
  components: [buildSubRecipeComponent(dependency)],
);

ProductionSetupCubit _setupOver(RecipeRepository storage, {Recipe? recipe}) =>
    ProductionSetupCubit(
      StartProductionRun(storage, const FixedRunIdSource(), const FixedClock()),
      recipe: recipe ?? _dough(),
      // Collapsed so a calculation resolves within one turn of the event queue,
      // the way the library screen's cubit tests collapse its search window.
      // The real length is pinned by the widget suite, which runs on a fake
      // clock and can advance it for free.
      previewDebounce: Duration.zero,
    );

void main() {
  group('ProductionSetupCubit', () {
    late FakeRecipeRepository storage;
    late ProductionSetupCubit cubit;

    setUp(() {
      storage = FakeRecipeRepository()..seed(_dough());
      cubit = _setupOver(storage);
    });

    tearDown(() => cubit.close());

    test('opens on the recipe yield unit with nothing calculated', () {
      expect(cubit.state.targetUnit, Unit.gram);
      expect(cubit.state.targetAmount, isEmpty);
      expect(cubit.state.status, ProductionSetupStatus.idle);
      expect(cubit.state.preview, isNull);
      expect(cubit.state.canContinue, isFalse);
      // An empty field is not an error: nothing has been typed yet.
      expect(cubit.state.amountIsInvalid, isFalse);
      expect(storage.calls, isEmpty);
    });

    test('a target calculates the run it describes', () async {
      await cubit.targetAmountChanged('2500');

      final run = cubit.state.preview;
      expect(cubit.state.status, ProductionSetupStatus.ready);
      expect(run, isNotNull);
      expect(run!.targetYield, Quantity.parse('2500', Unit.gram));
      // 2500 g against a 1000 g base yield. A calculation run against the
      // base yield, or against a target converted the wrong way round,
      // lands somewhere else.
      expect(run.result.scaleRatio, Rational.fromInt(5, 2));
      expect(cubit.state.canContinue, isTrue);
    });

    test('a target in another unit of the same dimension converts', () async {
      await cubit.targetUnitChanged(Unit.kilogram);
      await cubit.targetAmountChanged('3');

      // 3 kg against a 1000 g base yield is three times the recipe, not
      // three thousandths of it and not three.
      expect(cubit.state.preview?.result.scaleRatio, Rational.fromInt(3));
      expect(cubit.state.canContinue, isTrue);
    });

    test('the run is calculated and never stored', () async {
      await cubit.targetAmountChanged('2500');

      // The use case holds storage that can write as well as read. Only
      // reads are legitimate here: saving the run belongs to the
      // production result screen, which this slice does not build.
      expect(storage.calls, everyElement(startsWith('findLatest')));
    });

    test('the batch plan is read off the calculation', () async {
      final cubit = _setupOver(
        FakeRecipeRepository()..seed(_sheeted()),
        recipe: _sheeted(),
      );
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('1000');

      // Two full batches of 400 g and a 200 g remainder. A screen deriving
      // a count from the target alone, or ignoring the recipe's maximum,
      // says one batch of 1000 g.
      final plan = cubit.state.preview!.result.batchPlan;
      expect(plan.fullBatchCount, 2);
      expect(plan.fullBatchYield, Quantity.parse('400', Unit.gram));
      expect(plan.remainderYield, Quantity.parse('200', Unit.gram));
      expect(plan.batchCount, 3);
    });

    test(
      'an amount that is not a positive number calculates nothing',
      () async {
        for (final typed in ['0', '-5', 'two']) {
          await cubit.targetAmountChanged(typed);

          expect(cubit.state.amountIsInvalid, isTrue, reason: typed);
          expect(cubit.state.targetYield, isNull, reason: typed);
          expect(cubit.state.preview, isNull, reason: typed);
          expect(cubit.state.canContinue, isFalse, reason: typed);
        }
        expect(storage.calls, isEmpty);
      },
    );

    test('clearing the amount drops what was calculated for it', () async {
      await cubit.targetAmountChanged('2500');
      expect(cubit.state.preview, isNotNull);

      await cubit.targetAmountChanged('');

      // A batch plan is only true of the target it was calculated from, so
      // an emptied field must not leave one standing.
      expect(cubit.state.preview, isNull);
      expect(cubit.state.status, ProductionSetupStatus.idle);
      expect(cubit.state.amountIsInvalid, isFalse);
      expect(cubit.state.canContinue, isFalse);
    });

    test('changing the unit drops what the old one produced', () async {
      await cubit.targetAmountChanged('2500');
      expect(cubit.state.preview, isNotNull);

      final pending = cubit.targetUnitChanged(Unit.kilogram);

      // Before the next calculation lands the old one is already gone,
      // rather than sitting under a target that now means a thousand times
      // as much.
      expect(cubit.state.preview, isNull);
      await pending;
      expect(cubit.state.preview?.targetYield.unit, Unit.kilogram);
    });

    test('keystrokes inside the window calculate once', () async {
      unawaited(cubit.targetAmountChanged('2'));
      unawaited(cubit.targetAmountChanged('25'));
      await cubit.targetAmountChanged('2500');

      // One lookup, not three: without the intent count every keystroke
      // calculates, and each calculation is a read per recipe the run
      // depends on.
      expect(storage.calls, ['findLatest:dough']);
      expect(
        cubit.state.preview?.targetYield,
        Quantity.parse('2500', Unit.gram),
      );
    });

    test('a target above the batch limit is refused before the read', () async {
      final storage = FakeRecipeRepository()..seed(_sheeted());
      final cubit = _setupOver(storage, recipe: _sheeted());
      addTearDown(cubit.close);

      // 400 kg against a 400 g maximum is 1000 batches, the largest plan
      // the screen calculates; one gram more needs a 1001st batch.
      await cubit.targetAmountChanged('400001');

      expect(cubit.state.targetExceedsBatchLimit, isTrue);
      expect(cubit.state.targetYield, isNull);
      expect(cubit.state.preview, isNull);
      expect(cubit.state.canContinue, isFalse);
      // Empty, not merely discarded afterwards: the calculation is
      // synchronous and blocks the frame, so refusing it after it has run
      // would be no guard at all.
      expect(storage.calls, isEmpty);
    });

    test('the batch limit admits the largest plan that fits', () async {
      final cubit = _setupOver(
        FakeRecipeRepository()..seed(_sheeted()),
        recipe: _sheeted(),
      );
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('400000');

      // Exactly at the bound, so it calculates. A guard written with `>=`,
      // or one off by a batch, refuses this target.
      expect(cubit.state.targetExceedsBatchLimit, isFalse);
      expect(cubit.state.preview?.result.batchPlan.batchCount, 1000);
      expect(cubit.state.canContinue, isTrue);
    });

    test('a recipe with no maximum batch yield has no batch limit', () async {
      // `_dough` states no maximum and references nothing, so the run is
      // one batch whatever the target and nothing about it grows. A bound
      // measured against the base yield rather than the maximum batch
      // would refuse this.
      await cubit.targetAmountChanged('400000000');

      expect(cubit.state.targetExceedsBatchLimit, isFalse);
      expect(cubit.state.preview?.result.batchPlan.batchCount, 1);
      expect(cubit.state.canContinue, isTrue);
    });

    test('a sub-recipe past the batch limit fails rather than runs', () async {
      final storage = FakeRecipeRepository()
        ..seed(_filled('grain'))
        ..seed(buildGrainSubRecipe());
      final cubit = _setupOver(storage, recipe: _filled('grain'));
      addTearDown(cubit.close);

      // The root states no maximum, so it takes this target in a single
      // batch and the screen's own check finds nothing to refuse. A tenth
      // of the run reaches the sub-recipe, which is produced a gram at a
      // time, so 10001 g is 1001 batches — one past the bound, and the
      // smallest target that is. Deliberately the smallest: an
      // implementation that never passes the bound to the use case has to
      // fail this on the assertions below rather than by exhausting the
      // machine, which is what a target of a hundred million would do.
      await cubit.targetAmountChanged('10001');

      // The discriminating pair: the screen's own check passes, and the
      // run is still refused. A bound enforced only where this state can
      // see it leaves the first line true and the rest false.
      expect(cubit.state.targetExceedsBatchLimit, isFalse);
      expect(cubit.state.status, ProductionSetupStatus.failure);
      expect(cubit.state.error, isA<BatchLimitExceededError>());
      expect(cubit.state.preview, isNull);
      expect(cubit.state.canContinue, isFalse);
    });

    test('a sub-recipe inside the batch limit still calculates', () async {
      final storage = FakeRecipeRepository()
        ..seed(_filled('grain'))
        ..seed(buildGrainSubRecipe());
      final cubit = _setupOver(storage, recipe: _filled('grain'));
      addTearDown(cubit.close);

      // A tenth of this run reaches the sub-recipe, so 10 kg is exactly
      // the thousand one-gram batches the bound admits. A bound spent as
      // one budget across the whole run refuses this, because the root
      // adds a batch of its own.
      await cubit.targetAmountChanged('10000');

      expect(cubit.state.status, ProductionSetupStatus.ready);
      expect(cubit.state.canContinue, isTrue);
    });

    test(
      'a unit the yield cannot convert to is refused before the read',
      () async {
        await cubit.targetAmountChanged('2500');
        storage.calls.clear();

        await cubit.targetUnitChanged(_piece);

        // The domain throws `IncompatibleYieldUnitError` for this pair. The
        // screen says so without calculating, so the operator is not told by
        // a failure they had to cause first.
        expect(cubit.state.targetUnitIsIncompatible, isTrue);
        expect(cubit.state.targetYield, isNull);
        expect(cubit.state.preview, isNull);
        expect(cubit.state.canContinue, isFalse);
        expect(storage.calls, isEmpty);
      },
    );

    test('the unit picker offers the yield dimension, and nothing else', () {
      // Mass and nothing else: a target in millilitres or in trays is one
      // the calculation would throw on.
      expect(cubit.state.unitChoices, [
        Unit.milligram,
        Unit.gram,
        Unit.kilogram,
      ]);
    });

    test('the unit picker offers a chosen unit that does not belong', () async {
      await cubit.targetUnitChanged(_piece);

      // A dropdown whose value is missing from its items throws, and this
      // entry point accepts any unit; the error text is what refuses it.
      expect(cubit.state.unitChoices, contains(_piece));
    });

    test('a recipe-defined yield unit is the only choice there is', () {
      final trays = buildRecipe(
        id: 'focaccia',
        baseYield: Quantity.parse('2', _tray),
      );
      final cubit = _setupOver(
        FakeRecipeRepository()..seed(trays),
        recipe: trays,
      );
      addTearDown(cubit.close);

      // A yield-only unit converts to nothing but itself, so a picker
      // holding the fixed table would offer eight impossible targets — and
      // `portion`, yield-only too, would sit among them looking usable.
      expect(cubit.state.unitChoices, [_tray]);
    });

    test('an archived recipe still calculates and still blocks', () async {
      final archived = _dough(isArchived: true);
      final cubit = _setupOver(
        FakeRecipeRepository()..seed(archived),
        recipe: archived,
      );
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('2500');

      // The design document blocks a run on an archived dependency, and
      // the domain reports it as a warning rather than a throw — so the
      // numbers are there and the run still may not start.
      expect(cubit.state.preview, isNotNull);
      expect(cubit.state.archivedDependencies, ['Dough']);
      expect(cubit.state.canContinue, isFalse);
    });

    test('a recipe archived since it was listed still blocks', () async {
      // The revision the library screen listed says the recipe is live;
      // storage says otherwise, because it was archived after that list
      // was drawn. The calculation reads the stored one.
      final cubit = _setupOver(
        FakeRecipeRepository()..seed(_dough(isArchived: true)),
        recipe: _dough(),
      );
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('2500');

      expect(cubit.state.archivedDependencies, ['Dough']);
      expect(cubit.state.canContinue, isFalse);
    });

    test('an archived sub-recipe blocks the run under its own name', () async {
      final storage = FakeRecipeRepository()
        ..seed(_filled('cream'))
        ..seed(buildRecipe(id: 'cream', name: 'Cream', isArchived: true));
      final cubit = _setupOver(storage, recipe: _filled('cream'));
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('2000');

      // Named out of the run's own snapshot rather than by identifier: the
      // row the operator tapped never mentioned this recipe at all.
      expect(cubit.state.archivedDependencies, ['Cream']);
      expect(cubit.state.canContinue, isFalse);
    });

    test('a free-form component does not block the run', () async {
      final manual = buildRecipeWithManualComponent(id: 'dough');
      final cubit = _setupOver(
        FakeRecipeRepository()..seed(manual),
        recipe: manual,
      );
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('2000');

      // `ManualComponentWarning.isBlocking` is true, so a screen reading
      // that flag rather than the warning's type would refuse every recipe
      // carrying a "to taste" line. Acknowledging it belongs to the
      // production result screen.
      expect(
        cubit.state.preview!.result.warnings,
        contains(const ManualComponentWarning('dough', 'salt')),
      );
      expect(cubit.state.archivedDependencies, isEmpty);
      expect(cubit.state.canContinue, isTrue);
    });

    test('a recipe that is no longer stored is reported as absent', () async {
      final cubit = _setupOver(FakeRecipeRepository());
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('2500');

      expect(cubit.state.status, ProductionSetupStatus.failure);
      expect(cubit.state.error, isA<MissingDependencyError>());
      // The domain tells an absent root apart from a dangling reference,
      // and the screen renders the two differently.
      final error = cubit.state.error! as MissingDependencyError;
      expect(error.recipeId, 'dough');
      expect(error.missingId, 'dough');
      expect(cubit.state.preview, isNull);
      expect(cubit.state.canContinue, isFalse);
    });

    test('a missing sub-recipe is reported by identifier', () async {
      final cubit = _setupOver(
        FakeRecipeRepository()..seed(_filled('ghost')),
        recipe: _filled('ghost'),
      );
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('2000');

      expect(cubit.state.error, isA<MissingDependencyError>());
      final error = cubit.state.error! as MissingDependencyError;
      expect(error.recipeId, 'filled');
      expect(error.missingId, 'ghost');
    });

    test('a cycle in the stored graph is reported with its path', () async {
      final storage = FakeRecipeRepository()
        ..seed(_filled('cream'))
        ..seed(
          buildRecipe(
            id: 'cream',
            name: 'Cream',
            components: [buildSubRecipeComponent('filled')],
          ),
        );
      final cubit = _setupOver(storage, recipe: _filled('cream'));
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('2000');

      expect(cubit.state.error, isA<RecipeCycleError>());
      expect((cubit.state.error! as RecipeCycleError).path, [
        'filled',
        'cream',
        'filled',
      ]);
    });

    test('a stored recipe measured in another unit is reported', () async {
      // The form was laid out from a revision yielding grams; the stored
      // revision yields trays. Nothing the screen can pre-empt — it is the
      // calculation that reads the current revision.
      final cubit = _setupOver(
        FakeRecipeRepository()..seed(
          buildRecipe(id: 'dough', baseYield: Quantity.parse('2', _tray)),
        ),
      );
      addTearDown(cubit.close);

      await cubit.targetAmountChanged('2500');

      expect(cubit.state.error, isA<IncompatibleYieldUnitError>());
      expect(cubit.state.canContinue, isFalse);
    });
  });

  group('ProductionSetupCubit, while a calculation is in flight', () {
    late DeferredLookupRecipeRepository storage;
    late ProductionSetupCubit cubit;

    setUp(() {
      storage = DeferredLookupRecipeRepository(
        FakeRecipeRepository()..seed(_dough()),
      );
      cubit = _setupOver(storage);
    });

    tearDown(() => cubit.close());

    test('the screen says a calculation is running', () async {
      final pending = cubit.targetAmountChanged('2500');
      await pumpEventQueue();

      expect(cubit.state.status, ProductionSetupStatus.calculating);
      expect(cubit.state.preview, isNull);

      await storage.complete(0);
      await pending;

      expect(cubit.state.status, ProductionSetupStatus.ready);
    });

    test('clearing the target abandons it', () async {
      final pending = cubit.targetAmountChanged('2500');
      await pumpEventQueue();

      await cubit.targetAmountChanged('');
      await storage.complete(0);
      await pending;

      // The amount the operator deleted must not come back as a result. An
      // implementation that took its intent number only after deciding it
      // had nothing to calculate would let this one through.
      expect(cubit.state.preview, isNull);
      expect(cubit.state.status, ProductionSetupStatus.idle);
    });

    test('a target above the batch limit abandons one in flight', () async {
      final storage = DeferredLookupRecipeRepository(
        FakeRecipeRepository()..seed(_sheeted()),
      );
      final cubit = _setupOver(storage, recipe: _sheeted());
      addTearDown(cubit.close);

      final pending = cubit.targetAmountChanged('1000');
      await pumpEventQueue();

      // Not awaited: an implementation that let this target through would
      // wait on a lookup nobody answers, and the test would time out
      // rather than say what went wrong.
      unawaited(cubit.targetAmountChanged('400001'));
      await pumpEventQueue();
      await storage.complete(0);
      await pending;

      // A batch plan calculated for the target before this one must not
      // land under a target the screen has refused to calculate at all.
      expect(cubit.state.preview, isNull);
      expect(cubit.state.status, ProductionSetupStatus.idle);
      expect(cubit.state.targetExceedsBatchLimit, isTrue);
    });

    test('a newer target supersedes a slower calculation', () async {
      final first = cubit.targetAmountChanged('2500');
      await pumpEventQueue();
      final second = cubit.targetAmountChanged('4000');
      await pumpEventQueue();

      // The newer calculation lands first and the older one afterwards.
      await storage.complete(1);
      await second;
      await storage.complete(0);
      await first;

      expect(
        cubit.state.preview?.targetYield,
        Quantity.parse('4000', Unit.gram),
      );
    });

    test('one that lands after the screen closed emits nothing', () async {
      final pending = cubit.targetAmountChanged('2500');
      await pumpEventQueue();

      await cubit.close();
      await storage.complete(0);
      await pending;

      // `emit` after a close throws, so an unguarded implementation fails
      // here rather than merely showing something stale.
      expect(cubit.state.preview, isNull);
    });

    test('a failed read is reported', () async {
      final pending = cubit.targetAmountChanged('2500');
      await pumpEventQueue();

      storage.fail(0);
      await pending;

      expect(cubit.state.status, ProductionSetupStatus.failure);
      expect(cubit.state.error, 'the database is unreadable');
      expect(cubit.state.canContinue, isFalse);
    });

    test('a new target clears the failure before it', () async {
      final failing = cubit.targetAmountChanged('2500');
      await pumpEventQueue();
      storage.fail(0);
      await failing;

      final pending = cubit.targetAmountChanged('4000');
      await pumpEventQueue();
      await storage.complete(1);
      await pending;

      // A message from the calculation before this one must not survive
      // under the batch plan of the one that worked.
      expect(cubit.state.error, isNull);
      expect(cubit.state.status, ProductionSetupStatus.ready);
    });
  });
}
