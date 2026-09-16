import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/presentation/identifiers/unique_slug.dart';

part 'recipe_library_state.dart';

/// Drives the recipe library screen.
///
/// Depends on the four use cases, never on a repository: the screen is one
/// step further from storage than the application layer is, and injecting
/// the use cases is what keeps that true rather than merely documented.
final class RecipeLibraryCubit extends Cubit<RecipeLibraryState> {
  /// Creates the cubit over the use cases it reads and writes through: the
  /// two reads first, then the two row actions.
  ///
  /// [searchDebounce] is how long the search field must stay quiet before a
  /// search reads. Not zero, because a search is not the in-memory filter
  /// the field makes it look like: `SearchLibrary` reads the whole library
  /// out of storage and only then filters it, and that read costs one query
  /// per recipe plus one for the list. Without the wait, every keystroke
  /// paid all of them.
  RecipeLibraryCubit(
    this._listLibrary,
    this._searchLibrary,
    this._archiveRecipe,
    this._duplicateRecipe, {
    Duration searchDebounce = const Duration(milliseconds: 250),
  }) : _debounce = searchDebounce,
       super(const RecipeLibraryState());

  final ListLibrary _listLibrary;
  final SearchLibrary _searchLibrary;
  final ArchiveRecipe _archiveRecipe;
  final DuplicateRecipe _duplicateRecipe;
  final Duration _debounce;

  /// Counts intents, so a slow read cannot overwrite a newer result and a
  /// debounced search that a newer intent superseded never reads at all.
  ///
  /// Every entry point that reads takes the next number, and both the
  /// debounce in [search] and the guard in [_apply] compare against the
  /// latest one — which is why a reload or a retry abandons a keystroke
  /// still waiting out its window, with no separate cancellation to keep
  /// in step.
  int _intents = 0;

  /// Reads the whole library.
  Future<void> load() async {
    emit(state.copyWith(status: RecipeLibraryStatus.loading));
    await _apply(++_intents, _listLibrary(), query: '');
  }

  /// Filters the library by [query], keeping the previous rows on screen
  /// while the filtered read runs.
  ///
  /// [query] is recorded at once, because the field reads it, but the read
  /// itself waits out the debounce and is abandoned entirely if another
  /// keystroke, a retry, or a reload arrives first. Waiting does not cancel
  /// a read already in flight; it keeps the next one from starting, which
  /// is where the cost is. The empty state reads `resultsQuery` instead,
  /// which only moves when the read lands: see its doc comment.
  Future<void> search(String query) async {
    emit(state.copyWith(query: query));
    final intent = ++_intents;
    await Future<void>.delayed(_debounce);
    if (isClosed || intent != _intents) return;
    await _apply(intent, _searchLibrary(query), query: query);
  }

  /// Reads again after a failure, keeping the current query.
  ///
  /// Not [load]: that reads the whole library, which would list every
  /// recipe underneath a search field still showing what was typed. An
  /// empty query matches everything, so this covers a failed first read
  /// too, and it emits `loading` because a retry that reads should say so.
  ///
  /// Reads immediately rather than through [search]'s window: this is a
  /// deliberate tap, not a keystroke, and it must show `loading` now.
  ///
  /// Nothing at all once the cubit is closed. Every caller but the retry
  /// button reaches this after an await — a stored write in [archive] and
  /// [duplicate], the editor route closing on the page — and a close that
  /// landed during that await would otherwise turn the `loading` emit into
  /// a `StateError` on a future nobody awaits. Guarded here, at the emit,
  /// rather than at each of those call sites, so the next one is covered
  /// too.
  Future<void> retry() async {
    if (isClosed) return;
    emit(state.copyWith(status: RecipeLibraryStatus.loading));
    final query = state.query;
    await _apply(++_intents, _searchLibrary(query), query: query);
  }

  /// Shows or hides archived recipes. Re-filters what is already loaded.
  void showArchived({required bool show}) =>
      emit(state.copyWith(showArchived: show));

  /// Narrows the rows to [category], or to every category when it is
  /// `null`. Re-filters what is already loaded, the same as [showArchived].
  void selectCategory(String? category) => emit(
    category == null
        ? state.copyWith(clearSelectedCategory: true)
        : state.copyWith(selectedCategory: category),
  );

  /// Sets [recipe]'s archived flag to [isArchived], then reads again
  /// through [retry] so the current search stays applied.
  ///
  /// On success the state carries a [RecipeArchivedNotice], which is how
  /// the screen learns to offer the reversal. A failure emits a
  /// [RecipeActionFailedNotice] and nothing else: the rows on screen are
  /// still right, because nothing was written, so they are not re-read.
  ///
  /// A close that lands while the write or the re-read is in flight ends
  /// the call with no emit and no error. The write is not rolled back —
  /// the operator asked for it, and the screen that would have shown the
  /// outcome is the only thing that is gone.
  Future<void> archive(Recipe recipe, {required bool isArchived}) async {
    final action = isArchived
        ? RecipeLibraryAction.archive
        : RecipeLibraryAction.unarchive;
    try {
      await _archiveRecipe(recipe.id, isArchived: isArchived);
    } on Object catch (error, stackTrace) {
      _fail(action, error, stackTrace);
      return;
    }
    // `retry` guards its own emit against a close during the write; this
    // guards the notice against a close during the read it ran.
    await retry();
    if (isClosed) return;
    emit(
      state.copyWith(
        notice: RecipeArchivedNotice(recipe, isArchived: isArchived),
      ),
    );
  }

  /// Stores a copy of [source] called [name], then reads again through
  /// [retry] so the current search stays applied.
  ///
  /// [name] is the caller's, because what a copy is called is a product
  /// decision the screen makes in the operator's language; this cubit holds
  /// use cases, not localizations.
  ///
  /// The copy's id is slugged from [name] the way the editor slugs a new
  /// recipe's, against every id in the *whole* library — read here, rather
  /// than taken from `state.recipes`, because after a search those rows are
  /// the filtered set, and a slug unique among them can still collide with
  /// a stored recipe the query excludes. `DuplicateRecipe` refuses an
  /// occupied id, so the collision would surface as a failure rather than
  /// as a lost recipe, but a failure the screen could have avoided is still
  /// a failure.
  ///
  /// On success the state carries a [RecipeDuplicatedNotice] with the
  /// stored copy, which is what the screen opens the editor on. A failure
  /// emits a [RecipeActionFailedNotice] and leaves the rows as they were.
  /// A close mid-flight ends the call silently with the copy stored, as
  /// [archive] describes.
  ///
  /// One at a time. A second call that arrives while the first is in
  /// flight returns at once and emits nothing — not a failure notice,
  /// because the tap it came from was a double tap, and the copy it asked
  /// for is the one already being stored. Without this, the second call
  /// slugged its id against the same library snapshot, before either write
  /// had landed, and the two then raced into `DuplicateRecipe`: the second
  /// either found the id occupied and reported a failure beside a success,
  /// or found it free and stored the same content as revision 2 of the
  /// copy, and either way the screen opened two editors. The flag is set
  /// before the first `await`, so the check-and-set cannot interleave with
  /// another call, and [RecipeLibraryState.isDuplicating] states why the
  /// flag is one bool and why [archive] has none.
  Future<void> duplicate(Recipe source, {required String name}) async {
    if (state.isDuplicating) return;
    emit(state.copyWith(isDuplicating: true));
    final Recipe copy;
    try {
      final library = await _listLibrary();
      copy = await _duplicateRecipe(
        sourceId: source.id,
        newId: uniqueSlug(name, {
          for (final recipe in library) recipe.id,
        }, fallback: 'recipe'),
        name: name,
      );
    } on Object catch (error, stackTrace) {
      // The flag comes down whatever the outcome: one that outlived a
      // failure would leave Duplicate dead for the rest of the screen's
      // life, with the failure message as the only clue. Its own emit,
      // ahead of the notice `_fail` renders, and one that carries the
      // previous notice along unchanged, so the screen's identity check
      // does not fire on it.
      if (!isClosed) emit(state.copyWith(isDuplicating: false));
      _fail(RecipeLibraryAction.duplicate, error, stackTrace);
      return;
    }
    // The same two windows `archive` names: `retry` covers the write, this
    // covers the read.
    await retry();
    if (isClosed) return;
    emit(
      state.copyWith(
        isDuplicating: false,
        notice: RecipeDuplicatedNotice(copy),
      ),
    );
  }

  /// Reports that [action] threw [error], on the state and to the observer.
  ///
  /// Reported as well as rendered, for the reason [_outcomeOf] gives: the
  /// screen only says which action failed, and `AppBlocObserver` is where
  /// the reason is logged.
  void _fail(RecipeLibraryAction action, Object error, StackTrace stackTrace) {
    addError(error, stackTrace);
    if (isClosed) return;
    emit(state.copyWith(notice: RecipeActionFailedNotice(action)));
  }

  /// Awaits [read], the read for [query], and emits its outcome, unless a
  /// newer intent than [intent] arrived while it was in flight or the cubit
  /// was closed in the meantime.
  Future<void> _apply(
    int intent,
    Future<List<Recipe>> read, {
    required String query,
  }) async {
    final next = await _outcomeOf(read, query: query);
    if (isClosed || intent != _intents) return;
    emit(next);
  }

  /// The state [read], the read for [query], produces, whether it succeeds
  /// or throws.
  ///
  /// Both branches build on the `state` as it is once [read] has finished,
  /// never on a snapshot taken before it suspended: `showArchived` can be
  /// flipped while a read is in flight, and emitting a pre-toggle snapshot
  /// over it would roll the switch back off. That is why the await is
  /// hoisted out of the `copyWith` argument list — Dart evaluates the
  /// receiver `state` before the arguments, so an inline `await read` there
  /// reads `state` at call time. Both also record [query] as what the rows
  /// now answer, a failure included: its empty rows are that query's.
  Future<RecipeLibraryState> _outcomeOf(
    Future<List<Recipe>> read, {
    required String query,
  }) async {
    try {
      final rows = await read;
      return state.copyWith(
        status: RecipeLibraryStatus.loaded,
        recipes: _newestFirst(rows),
        resultsQuery: query,
      );
    } on Object catch (error, stackTrace) {
      // Reported as well as rendered: the screen only says the read
      // failed, and `AppBlocObserver` is where the reason is logged.
      addError(error, stackTrace);
      return state.copyWith(
        status: RecipeLibraryStatus.failure,
        recipes: const [],
        resultsQuery: query,
      );
    }
  }

  /// [recipes] ordered by `modifiedAt`, newest first.
  ///
  /// Sorted here rather than in `ListLibrary`: the application layer's
  /// contract is "every recipe's latest revision" and moving this into SQL
  /// later would not change the screen. Name breaks a tie, because
  /// `List.sort` is not guaranteed stable and two recipes saved in the same
  /// moment must still list in a fixed order.
  static List<Recipe> _newestFirst(List<Recipe> recipes) =>
      [...recipes]..sort((a, b) {
        final byModifiedAt = b.modifiedAt.compareTo(a.modifiedAt);
        return byModifiedAt != 0 ? byModifiedAt : a.name.compareTo(b.name);
      });
}
