import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/presentation.dart';

import '../../application/fakes.dart';
import '../fakes.dart';

/// Three recipes whose id order, name order and `modifiedAt` order all
/// differ, so the expected list matches none of them by accident.
///
/// `FakeRecipeRepository.listLatestRevisions` answers id-ascending, which
/// would be `[Ciabatta, Baguette, Croissant]`. Newest-first is
/// `[Ciabatta, Croissant, Baguette]`; oldest-first, name-ascending and
/// name-descending each produce something else again.
final Recipe _ciabatta = buildRecipe(
  id: 'r-a',
  name: 'Ciabatta',
  modifiedAt: DateTime.utc(2026, 9, 13),
);
final Recipe _baguette = buildRecipe(
  id: 'r-b',
  name: 'Baguette',
  modifiedAt: DateTime.utc(2026, 9, 11),
);
final Recipe _croissant = buildRecipe(
  id: 'r-c',
  name: 'Croissant',
  modifiedAt: DateTime.utc(2026, 9, 12),
);

void main() {
  group('RecipeLibraryCubit', () {
    late FakeRecipeRepository recipes;
    late RecipeLibraryCubit cubit;

    setUp(() {
      recipes = FakeRecipeRepository()
        ..seed(_croissant)
        ..seed(_ciabatta)
        ..seed(_baguette);
      cubit = RecipeLibraryCubit(
        ListLibrary(recipes),
        SearchLibrary(recipes),
        // Collapsed so a search resolves within one turn of the event
        // queue. The window's real length is pinned by the widget suite,
        // which runs on a fake clock and can advance it for free.
        searchDebounce: Duration.zero,
      );
    });

    tearDown(() => cubit.close());

    test('starts loading, with nothing to show yet', () {
      expect(cubit.state.status, RecipeLibraryStatus.loading);
      expect(cubit.state.recipes, isEmpty);
      expect(cubit.state.query, isEmpty);
      expect(cubit.state.showArchived, isFalse);
    });

    test('load orders by modifiedAt, newest first', () async {
      await cubit.load();

      expect(cubit.state.status, RecipeLibraryStatus.loaded);
      expect(cubit.state.recipes.map((recipe) => recipe.name), [
        'Ciabatta',
        'Croissant',
        'Baguette',
      ]);
    });

    test('load breaks a modifiedAt tie by name', () async {
      final sameMoment = DateTime.utc(2026, 9, 14);
      final repository = FakeRecipeRepository()
        // Id order is the reverse of name order, so a sort that keeps the
        // repository's own id-ascending order on a tie fails this.
        ..seed(
          buildRecipe(id: 'r-t1', name: 'Zwieback', modifiedAt: sameMoment),
        )
        ..seed(
          buildRecipe(id: 'r-t2', name: 'Ale bread', modifiedAt: sameMoment),
        );
      final tied = RecipeLibraryCubit(
        ListLibrary(repository),
        SearchLibrary(repository),
      );
      addTearDown(tied.close);

      await tied.load();

      expect(tied.state.recipes.map((recipe) => recipe.name), [
        'Ale bread',
        'Zwieback',
      ]);
    });

    test('search records the query and filters by name', () async {
      await cubit.search('cia');

      expect(cubit.state.query, 'cia');
      expect(cubit.state.recipes.map((recipe) => recipe.name), ['Ciabatta']);
      expect(cubit.state.status, RecipeLibraryStatus.loaded);
    });
  });

  group('RecipeLibraryCubit, against reads it completes by hand', () {
    late DeferredRecipeRepository repository;
    late RecipeLibraryCubit cubit;

    setUp(() {
      repository = DeferredRecipeRepository();
      cubit = RecipeLibraryCubit(
        ListLibrary(repository),
        SearchLibrary(repository),
        searchDebounce: Duration.zero,
      );
    });

    tearDown(() => cubit.close());

    test(
      'showArchived re-filters what is loaded, without reading again',
      () async {
        final focaccia = buildRecipe(
          id: 'r-x',
          name: 'Summer focaccia',
          isArchived: true,
          modifiedAt: DateTime.utc(2026, 9, 14),
        );
        unawaited(cubit.load());
        repository.complete(0, [focaccia, _ciabatta, _croissant, _baguette]);
        await pumpEventQueue();

        expect(cubit.state.recipes, hasLength(4));
        expect(
          cubit.state.visibleRecipes.map((recipe) => recipe.name),
          isNot(contains('Summer focaccia')),
        );

        cubit.showArchived(show: true);

        expect(cubit.state.showArchived, isTrue);
        expect(cubit.state.visibleRecipes.map((recipe) => recipe.name), [
          'Summer focaccia',
          'Ciabatta',
          'Croissant',
          'Baguette',
        ]);

        cubit.showArchived(show: false);

        expect(cubit.state.visibleRecipes, hasLength(3));
        expect(repository.readCount, 1);
      },
    );

    test(
      'a toggle made while a read is in flight survives it landing',
      () async {
        final focaccia = buildRecipe(
          id: 'r-x',
          name: 'Summer focaccia',
          isArchived: true,
          modifiedAt: DateTime.utc(2026, 9, 14),
        );
        unawaited(cubit.load());

        // Flipped while the read is still in flight, which is reachable on
        // the opening screen and again whenever a search's window has
        // elapsed and its read has not answered yet.
        cubit.showArchived(show: true);
        repository.complete(0, [focaccia, _ciabatta]);
        await pumpEventQueue();

        // Rejects building the loaded state from a `state` read before the
        // await: that snapshot predates the toggle, so emitting it rolls the
        // switch back off and hides the archived rows again.
        expect(cubit.state.showArchived, isTrue);
        expect(cubit.state.visibleRecipes.map((recipe) => recipe.name), [
          'Summer focaccia',
          'Ciabatta',
        ]);
      },
    );

    test('a failed read reports failure and drops the rows it had', () async {
      unawaited(cubit.load());
      repository.complete(0, [_ciabatta]);
      await pumpEventQueue();
      expect(cubit.state.recipes, hasLength(1));

      unawaited(cubit.load());
      repository.fail(1);
      await pumpEventQueue();

      expect(cubit.state.status, RecipeLibraryStatus.failure);
      expect(cubit.state.recipes, isEmpty);
    });

    test(
      'retry reads the current query again, not the whole library',
      () async {
        unawaited(cubit.search('cia'));
        // The search reads once its window elapses, not when it is called.
        await pumpEventQueue();
        repository.fail(0);
        await pumpEventQueue();
        expect(cubit.state.status, RecipeLibraryStatus.failure);

        unawaited(cubit.retry());

        // Rejects retrying through `search`, which emits no status, would
        // leave the error body on screen while the read runs, and would not
        // even start the read until the window it does not deserve elapsed.
        expect(cubit.state.status, RecipeLibraryStatus.loading);
        expect(repository.readCount, 2);

        repository.complete(1, [_ciabatta, _croissant]);
        await pumpEventQueue();

        // Rejects retrying through `load`, which reads the whole library and
        // would keep Croissant against a query that excludes it.
        expect(cubit.state.query, 'cia');
        expect(cubit.state.recipes.map((recipe) => recipe.name), ['Ciabatta']);
      },
    );

    test('search keeps the loaded rows on screen while it runs', () async {
      unawaited(cubit.load());
      repository.complete(0, [_ciabatta, _croissant]);
      await pumpEventQueue();

      unawaited(cubit.search('cia'));

      expect(cubit.state.query, 'cia');
      expect(cubit.state.status, RecipeLibraryStatus.loaded);
      expect(cubit.state.recipes, hasLength(2));

      await pumpEventQueue();
      repository.complete(1, [_ciabatta, _croissant]);
      await pumpEventQueue();
    });

    test('two keystrokes inside one window read once, for the last', () async {
      unawaited(cubit.search('c'));
      unawaited(cubit.search('cia'));
      await pumpEventQueue();

      // Rejects the undebounced implementation, which starts a read per
      // keystroke. Each one re-reads the whole library before filtering it,
      // so the cost is not the filter but the read the filter runs on.
      expect(repository.readCount, 1);

      repository.complete(0, [_ciabatta, _croissant]);
      await pumpEventQueue();

      // And the read that survived is the last keystroke's, not the first:
      // 'c' matches both of these, 'cia' matches one.
      expect(cubit.state.query, 'cia');
      expect(cubit.state.recipes.map((recipe) => recipe.name), ['Ciabatta']);
    });

    test('a retry cancels a keystroke still waiting out its window', () async {
      unawaited(cubit.search('cia'));
      unawaited(cubit.retry());
      await pumpEventQueue();

      // One read, not two: the retry reads now and takes the newer intent,
      // which the waiting keystroke checks before it starts a read of its
      // own. It reads the same query either way, so only the count says
      // whether the pending one was abandoned or merely overtaken.
      expect(repository.readCount, 1);

      repository.complete(0, [_ciabatta, _croissant]);
      await pumpEventQueue();

      expect(cubit.state.query, 'cia');
      expect(cubit.state.recipes.map((recipe) => recipe.name), ['Ciabatta']);
    });

    test('a read overtaken by a newer one is discarded', () async {
      unawaited(cubit.load());
      unawaited(cubit.search('cia'));
      await pumpEventQueue();
      expect(repository.readCount, 2);

      // The search answers first, then the full library read lands late.
      repository.complete(1, [_ciabatta, _croissant]);
      await pumpEventQueue();
      repository.complete(0, [_ciabatta, _croissant]);
      await pumpEventQueue();

      expect(cubit.state.query, 'cia');
      expect(cubit.state.recipes.map((recipe) => recipe.name), ['Ciabatta']);
    });

    test('a read that lands after close emits nothing', () async {
      unawaited(cubit.load());
      await cubit.close();

      // Without the `isClosed` guard this throws "Cannot emit new states
      // after calling close", as an unhandled error on the load future.
      repository.complete(0, [_ciabatta]);
      await pumpEventQueue();

      expect(cubit.state.status, RecipeLibraryStatus.loading);
    });
  });
}
