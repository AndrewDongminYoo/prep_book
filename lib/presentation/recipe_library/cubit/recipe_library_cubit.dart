import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';

part 'recipe_library_state.dart';

/// Drives the recipe library screen.
///
/// Depends on the two use cases, never on a repository: the screen is one
/// step further from storage than the application layer is, and injecting
/// the use cases is what keeps that true rather than merely documented.
final class RecipeLibraryCubit extends Cubit<RecipeLibraryState> {
  /// Creates the cubit over the use cases it reads through.
  ///
  /// [searchDebounce] is how long the search field must stay quiet before a
  /// search reads. Not zero, because a search is not the in-memory filter
  /// the field makes it look like: `SearchLibrary` reads the whole library
  /// out of storage and only then filters it, and that read costs one query
  /// per recipe plus one for the list. Without the wait, every keystroke
  /// paid all of them.
  RecipeLibraryCubit(
    this._listLibrary,
    this._searchLibrary, {
    Duration searchDebounce = const Duration(milliseconds: 250),
  }) : _debounce = searchDebounce,
       super(const RecipeLibraryState());

  final ListLibrary _listLibrary;
  final SearchLibrary _searchLibrary;
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
    await _apply(++_intents, _listLibrary());
  }

  /// Filters the library by [query], keeping the previous rows on screen
  /// while the filtered read runs.
  ///
  /// [query] is recorded at once, because the field and the empty-state
  /// message read it, but the read itself waits out the debounce and is
  /// abandoned entirely if another keystroke, a retry, or a reload arrives
  /// first. Waiting does not cancel a read already in flight; it keeps the
  /// next one from starting, which is where the cost is.
  Future<void> search(String query) async {
    emit(state.copyWith(query: query));
    final intent = ++_intents;
    await Future<void>.delayed(_debounce);
    if (isClosed || intent != _intents) return;
    await _apply(intent, _searchLibrary(query));
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
  Future<void> retry() async {
    emit(state.copyWith(status: RecipeLibraryStatus.loading));
    await _apply(++_intents, _searchLibrary(state.query));
  }

  /// Shows or hides archived recipes. Re-filters what is already loaded.
  void showArchived({required bool show}) =>
      emit(state.copyWith(showArchived: show));

  /// Awaits [read] and emits its outcome, unless a newer intent than
  /// [intent] arrived while it was in flight or the cubit was closed in the
  /// meantime.
  Future<void> _apply(int intent, Future<List<Recipe>> read) async {
    final next = await _outcomeOf(read);
    if (isClosed || intent != _intents) return;
    emit(next);
  }

  /// The state [read] produces, whether it succeeds or throws.
  ///
  /// Both branches build on the `state` as it is once [read] has finished,
  /// never on a snapshot taken before it suspended: `showArchived` can be
  /// flipped while a read is in flight, and emitting a pre-toggle snapshot
  /// over it would roll the switch back off. That is why the await is
  /// hoisted out of the `copyWith` argument list — Dart evaluates the
  /// receiver `state` before the arguments, so an inline `await read` there
  /// reads `state` at call time.
  Future<RecipeLibraryState> _outcomeOf(Future<List<Recipe>> read) async {
    try {
      final rows = await read;
      return state.copyWith(
        status: RecipeLibraryStatus.loaded,
        recipes: _newestFirst(rows),
      );
    } on Object catch (error, stackTrace) {
      // Reported as well as rendered: the screen only says the read
      // failed, and `AppBlocObserver` is where the reason is logged.
      addError(error, stackTrace);
      return state.copyWith(
        status: RecipeLibraryStatus.failure,
        recipes: const [],
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
