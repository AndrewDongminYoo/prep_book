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
        ArchiveRecipe(recipes),
        DuplicateRecipe(recipes, const FixedClock()),
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
      expect(cubit.state.selectedCategory, isNull);
      expect(cubit.state.categories, isEmpty);
      expect(cubit.state.isDuplicating, isFalse);
      expect(cubit.state.notice, isNull);
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
        ArchiveRecipe(repository),
        DuplicateRecipe(repository, const FixedClock()),
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
        ArchiveRecipe(repository),
        DuplicateRecipe(repository, const FixedClock()),
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

  group('RecipeLibraryCubit, row actions', () {
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
        ArchiveRecipe(recipes),
        DuplicateRecipe(recipes, const FixedClock()),
        searchDebounce: Duration.zero,
      );
    });

    tearDown(() => cubit.close());

    test('archive sets the flag, re-reads, and offers the reversal', () async {
      await cubit.load();

      await cubit.archive(_ciabatta, isArchived: true);

      expect(recipes.calls, contains('setArchived:r-a:true'));
      expect(cubit.state.status, RecipeLibraryStatus.loaded);
      // Re-read, not patched in place: the row now carries the stored flag.
      final stored = cubit.state.recipes.singleWhere((r) => r.id == 'r-a');
      expect(stored.isArchived, isTrue);
      expect(
        cubit.state.visibleRecipes.map((recipe) => recipe.name),
        isNot(contains('Ciabatta')),
      );
      expect(cubit.state.notice, isA<RecipeArchivedNotice>());
      final notice = cubit.state.notice! as RecipeArchivedNotice;
      expect(notice.recipe.id, 'r-a');
      expect(notice.isArchived, isTrue);
    });

    test('unarchive clears the flag and says so', () async {
      recipes.seed(
        buildRecipe(
          id: 'r-x',
          name: 'Summer focaccia',
          isArchived: true,
          modifiedAt: DateTime.utc(2026, 9, 14),
        ),
      );
      await cubit.load();
      final focaccia = cubit.state.recipes.first;
      expect(focaccia.isArchived, isTrue);

      await cubit.archive(focaccia, isArchived: false);

      expect(recipes.calls, contains('setArchived:r-x:false'));
      expect(cubit.state.visibleRecipes.map((recipe) => recipe.name), [
        'Summer focaccia',
        'Ciabatta',
        'Croissant',
        'Baguette',
      ]);
      final notice = cubit.state.notice;
      expect(notice, isA<RecipeArchivedNotice>());
      expect((notice! as RecipeArchivedNotice).isArchived, isFalse);
    });

    test(
      'archive re-reads the current search, not the whole library',
      () async {
        await cubit.search('cia');
        expect(cubit.state.recipes.map((recipe) => recipe.name), ['Ciabatta']);

        await cubit.archive(_ciabatta, isArchived: true);

        // Rejects re-reading through `load`, which would list Croissant and
        // Baguette under a field still showing "cia".
        expect(cubit.state.query, 'cia');
        expect(cubit.state.recipes.map((recipe) => recipe.name), ['Ciabatta']);
        expect(cubit.state.recipes.single.isArchived, isTrue);
      },
    );

    test(
      'duplicate stores the copy under a slug of its name, then re-reads',
      () async {
        final categorised = buildRecipe(
          id: 'r-cat',
          name: 'Country loaf',
          category: 'Breads',
          modifiedAt: DateTime.utc(2026, 9, 10),
        );
        recipes.seed(categorised);
        await cubit.load();

        await cubit.duplicate(categorised, name: 'Country loaf (copy)');

        final copy = await recipes.findLatest('country-loaf-copy');
        expect(copy, isNotNull);
        expect(copy!.revision, 1);
        expect(copy.name, 'Country loaf (copy)');
        expect(copy.category, 'Breads');
        expect(copy.isArchived, isFalse);
        // Stamped by the clock, not copied from the source.
        expect(copy.modifiedAt, const FixedClock().now());
        // Re-read, so the copy is a row now.
        expect(
          cubit.state.recipes.map((recipe) => recipe.id),
          contains('country-loaf-copy'),
        );
        final notice = cubit.state.notice;
        expect(notice, isA<RecipeDuplicatedNotice>());
        expect(
          (notice! as RecipeDuplicatedNotice).copy.id,
          'country-loaf-copy',
        );
      },
    );

    test('duplicate avoids an id the current search does not show', () async {
      // Occupies the slug the copy would take, under a name the search
      // below excludes — so a slug drawn from the filtered rows collides.
      recipes.seed(
        buildRecipe(
          id: 'ciabatta-copy',
          name: 'Something else',
          modifiedAt: DateTime.utc(2026, 9),
        ),
      );
      await cubit.search('cia');
      expect(cubit.state.recipes.map((recipe) => recipe.name), ['Ciabatta']);

      await cubit.duplicate(_ciabatta, name: 'Ciabatta (copy)');

      // Rejects slugging against `state.recipes`: `DuplicateRecipe` refuses
      // an occupied id, so that variant surfaces a failure here instead.
      expect(cubit.state.notice, isA<RecipeDuplicatedNotice>());
      expect(await recipes.findLatest('ciabatta-copy-2'), isNotNull);
      expect(
        (await recipes.findLatest('ciabatta-copy'))!.name,
        'Something else',
      );
      // The re-read keeps the search applied, and the copy matches it. The
      // copy lists second because the fixed clock predates the fixtures.
      expect(cubit.state.query, 'cia');
      expect(cubit.state.recipes.map((recipe) => recipe.name), [
        'Ciabatta',
        'Ciabatta (copy)',
      ]);
    });

    test('two duplicates in flight at once store one copy', () async {
      await cubit.load();
      final notices = <RecipeLibraryNotice>[];
      final subscription = cubit.stream.listen((state) {
        final notice = state.notice;
        if (notice != null && (notices.isEmpty || !identical(notices.last, notice))) {
          notices.add(notice);
        }
      });
      addTearDown(subscription.cancel);

      // A double tap: the second call lands before the first has read the
      // library, let alone written to it.
      final first = cubit.duplicate(_ciabatta, name: 'Ciabatta (copy)');
      final second = cubit.duplicate(_ciabatta, name: 'Ciabatta (copy)');
      expect(cubit.state.isDuplicating, isTrue);
      await Future.wait([first, second]);
      // The stream hands the listener each state a microtask after it was
      // emitted, so the last one is drained before the notices are counted.
      await pumpEventQueue();

      // Rejects the unguarded cubit, where both calls slugged the same id
      // against the same snapshot: the second then either stored the same
      // content as revision 2 of the copy or failed on the occupied id.
      expect(recipes.calls.where((call) => call.startsWith('saveRevision:')), [
        'saveRevision:ciabatta-copy:1',
      ]);
      expect((await recipes.findLatest('ciabatta-copy'))!.revision, 1);
      expect(await recipes.findLatest('ciabatta-copy-2'), isNull);
      // One outcome, not two, and not a failure beside a success.
      expect(notices, [isA<RecipeDuplicatedNotice>()]);
      expect(cubit.state.isDuplicating, isFalse);

      // The flag came down with the outcome: a deliberate second copy,
      // asked for once the first is stored, is a second copy.
      await cubit.duplicate(_ciabatta, name: 'Ciabatta (copy)');
      await pumpEventQueue();

      expect(await recipes.findLatest('ciabatta-copy-2'), isNotNull);
      expect(notices, hasLength(2));
    });

    test('an archive whose cubit closes mid-write emits nothing', () async {
      await cubit.load();

      final pending = cubit.archive(_ciabatta, isArchived: true);
      await cubit.close();
      // Without the guard at the top of `retry`, the `loading` emit there
      // throws "Cannot emit new states after calling close" — after the
      // write below has already landed, and to a caller the page never
      // awaits, so as an unhandled error.
      await pending;

      // The write is not rolled back: there is no screen left to tell, but
      // the flag the operator asked for is stored.
      expect(recipes.calls, contains('setArchived:r-a:true'));
      expect(cubit.state.status, RecipeLibraryStatus.loaded);
      expect(cubit.state.notice, isNull);
    });

    test('a duplicate whose cubit closes mid-write emits nothing', () async {
      await cubit.load();

      final pending = cubit.duplicate(_ciabatta, name: 'Ciabatta (copy)');
      await cubit.close();
      await pending;

      expect(await recipes.findLatest('ciabatta-copy'), isNotNull);
      expect(cubit.state.status, RecipeLibraryStatus.loaded);
      expect(cubit.state.notice, isNull);
    });
  });

  group('RecipeLibraryCubit, against writes that fail', () {
    late FailingLifecycleRecipeRepository repository;
    late RecipeLibraryCubit cubit;

    setUp(() {
      repository = FailingLifecycleRecipeRepository(
        FakeRecipeRepository()
          ..seed(_croissant)
          ..seed(_ciabatta)
          ..seed(
            buildRecipe(
              id: 'r-x',
              name: 'Summer focaccia',
              isArchived: true,
              modifiedAt: DateTime.utc(2026, 9, 14),
            ),
          ),
      );
      cubit = RecipeLibraryCubit(
        ListLibrary(repository),
        SearchLibrary(repository),
        ArchiveRecipe(repository),
        DuplicateRecipe(repository, const FixedClock()),
        searchDebounce: Duration.zero,
      );
    });

    tearDown(() => cubit.close());

    test('a failed archive names the action and keeps the rows', () async {
      await cubit.load();
      final before = cubit.state.recipes;
      expect(repository.readCount, 1);

      await cubit.archive(_ciabatta, isArchived: true);

      final notice = cubit.state.notice;
      expect(notice, isA<RecipeActionFailedNotice>());
      expect(
        (notice! as RecipeActionFailedNotice).action,
        RecipeLibraryAction.archive,
      );
      // Nothing was written, so nothing is re-read: the rows are the same
      // list, not a fresh copy of it, and the status never left `loaded`.
      expect(identical(cubit.state.recipes, before), isTrue);
      expect(cubit.state.status, RecipeLibraryStatus.loaded);
      expect(repository.readCount, 1);
    });

    test('a failed unarchive names that action instead', () async {
      await cubit.load();
      final focaccia = cubit.state.recipes.first;

      await cubit.archive(focaccia, isArchived: false);

      expect(
        (cubit.state.notice! as RecipeActionFailedNotice).action,
        RecipeLibraryAction.unarchive,
      );
      expect(repository.readCount, 1);
    });

    test('a failed duplicate names the action and keeps the rows', () async {
      await cubit.load();
      final before = cubit.state.recipes;

      await cubit.duplicate(_ciabatta, name: 'Ciabatta (copy)');

      expect(
        (cubit.state.notice! as RecipeActionFailedNotice).action,
        RecipeLibraryAction.duplicate,
      );
      expect(identical(cubit.state.recipes, before), isTrue);
      // One read for the slug's taken set, none after the failed write.
      expect(repository.readCount, 2);
    });

    test('a failed duplicate lets the next attempt run', () async {
      await cubit.load();

      await cubit.duplicate(_ciabatta, name: 'Ciabatta (copy)');
      final first = cubit.state.notice;

      // Rejects clearing the in-flight flag on the success path only, which
      // would leave Duplicate dead for the rest of the screen's life after
      // one failed write, with the failure message as the only clue.
      expect(cubit.state.isDuplicating, isFalse);

      await cubit.duplicate(_ciabatta, name: 'Ciabatta (copy)');

      // The second attempt reached storage — it read the library for its
      // slug — and reported its own failure rather than being dropped.
      expect(repository.readCount, 3);
      expect(cubit.state.notice, isA<RecipeActionFailedNotice>());
      expect(identical(cubit.state.notice, first), isFalse);
    });

    test('two failures in a row are two notices', () async {
      await cubit.load();

      await cubit.archive(_ciabatta, isArchived: true);
      final first = cubit.state.notice;
      await cubit.archive(_ciabatta, isArchived: true);

      // Distinct instances, because the screen tells a new notice from a
      // stale one by identity and must react to the second failure too.
      expect(identical(cubit.state.notice, first), isFalse);
    });
  });

  group('RecipeLibraryCubit, category filter', () {
    late FakeRecipeRepository recipes;
    late RecipeLibraryCubit cubit;

    final countryLoaf = buildRecipe(
      id: 'r-bread-1',
      name: 'Country loaf',
      category: 'Breads',
      modifiedAt: DateTime.utc(2026, 9, 14),
    );
    final focaccia = buildRecipe(
      id: 'r-bread-2',
      name: 'Summer focaccia',
      category: 'Breads',
      isArchived: true,
      modifiedAt: DateTime.utc(2026, 9, 13),
    );
    final croissantDough = buildRecipe(
      id: 'r-dough',
      name: 'Croissant dough',
      category: 'Doughs',
      modifiedAt: DateTime.utc(2026, 9, 12),
    );
    final uncategorised = buildRecipe(
      id: 'r-none',
      name: 'Pastry cream',
      modifiedAt: DateTime.utc(2026, 9, 11),
    );

    setUp(() {
      recipes = FakeRecipeRepository()
        ..seed(croissantDough)
        ..seed(countryLoaf)
        ..seed(uncategorised)
        ..seed(focaccia);
      cubit = RecipeLibraryCubit(
        ListLibrary(recipes),
        SearchLibrary(recipes),
        ArchiveRecipe(recipes),
        DuplicateRecipe(recipes, const FixedClock()),
        searchDebounce: Duration.zero,
      );
    });

    tearDown(() => cubit.close());

    test('categories are the distinct non-null ones, sorted', () async {
      await cubit.load();

      // Two Breads collapse to one chip, the uncategorised recipe adds
      // none, and Breads sorts before Doughs whatever order the read used.
      expect(cubit.state.categories, ['Breads', 'Doughs']);
    });

    test('selecting a category narrows the rows without reading', () async {
      await cubit.load();

      cubit.selectCategory('Doughs');

      expect(cubit.state.selectedCategory, 'Doughs');
      expect(cubit.state.visibleRecipes.map((recipe) => recipe.name), [
        'Croissant dough',
      ]);
      // Re-filtered, not re-read: the loaded rows are untouched.
      expect(cubit.state.recipes, hasLength(4));
      expect(cubit.state.status, RecipeLibraryStatus.loaded);

      cubit.selectCategory(null);

      // Rejects a `copyWith` whose `null` means "keep": the filter must
      // actually come off.
      expect(cubit.state.selectedCategory, isNull);
      expect(cubit.state.visibleRecipes, hasLength(3));
    });

    test('the category filter composes with the archived switch', () async {
      await cubit.load();

      cubit.selectCategory('Breads');

      expect(cubit.state.visibleRecipes.map((recipe) => recipe.name), [
        'Country loaf',
      ]);
      expect(cubit.state.hasHiddenArchived, isTrue);

      cubit.showArchived(show: true);

      expect(cubit.state.visibleRecipes.map((recipe) => recipe.name), [
        'Country loaf',
        'Summer focaccia',
      ]);
      expect(cubit.state.hasHiddenArchived, isFalse);
    });

    test('an archived recipe outside the category is not "hidden"', () async {
      await cubit.load();

      cubit.selectCategory('Doughs');

      // The only archived recipe is a Bread. With Doughs selected the
      // switch would show nothing, so the empty state must not point at it.
      expect(cubit.state.hasHiddenArchived, isFalse);
    });

    test('the category filter composes with a search', () async {
      await cubit.load();
      cubit.selectCategory('Breads');

      await cubit.search('crois');

      // The read narrowed the rows to a Dough; the filter still excludes it.
      expect(cubit.state.recipes.map((recipe) => recipe.name), [
        'Croissant dough',
      ]);
      expect(cubit.state.visibleRecipes, isEmpty);
      // And the selection stays offered, or there would be no way to clear
      // a filter whose only chip the search took away.
      expect(cubit.state.selectedCategory, 'Breads');
      expect(cubit.state.categories, ['Breads', 'Doughs']);
    });

    test('a selection made while a read is in flight survives it', () async {
      final deferred = DeferredRecipeRepository();
      final slow = RecipeLibraryCubit(
        ListLibrary(deferred),
        SearchLibrary(deferred),
        ArchiveRecipe(deferred),
        DuplicateRecipe(deferred, const FixedClock()),
        searchDebounce: Duration.zero,
      );
      addTearDown(slow.close);
      unawaited(slow.load());

      slow.selectCategory('Breads');
      deferred.complete(0, [countryLoaf, croissantDough]);
      await pumpEventQueue();

      // The same guard `showArchived` has: the loaded state is built from
      // the state as it is when the read lands, selection included.
      expect(slow.state.selectedCategory, 'Breads');
      expect(slow.state.visibleRecipes.map((recipe) => recipe.name), [
        'Country loaf',
      ]);
    });
  });
}
