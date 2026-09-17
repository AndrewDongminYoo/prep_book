part of 'recipe_library_cubit.dart';

/// What the library screen is currently showing.
enum RecipeLibraryStatus {
  /// A read is in flight and no result has arrived yet.
  loading,

  /// The last read succeeded; [RecipeLibraryState.recipes] is its result.
  loaded,

  /// The last read failed.
  failure,
}

/// One of the row actions the library performs on a stored recipe, named so
/// a failure can say which one did not happen.
enum RecipeLibraryAction {
  /// Setting a recipe's archived flag.
  archive,

  /// Clearing a recipe's archived flag.
  unarchive,

  /// Storing a copy of a recipe under a new id.
  duplicate,
}

/// A one-shot signal about a row action, which the screen turns into a
/// notice or a navigation exactly once.
///
/// Carried in [RecipeLibraryState.notice] and compared by identity, never
/// by value: two archives in a row produce two distinct instances, and the
/// screen reacts to each one, where a value comparison would swallow the
/// second. Nothing clears it — a later `copyWith` carries it along
/// unchanged, and the screen's identity check is what keeps a stale one
/// from firing again.
@immutable
sealed class RecipeLibraryNotice {
  const new();
}

/// [recipe]'s archived flag was set to [isArchived] and the rows were read
/// again.
///
/// Carries the recipe so the screen can offer to reverse it — the same
/// call with the opposite flag — without keeping its own record of what
/// was just archived.
final class RecipeArchivedNotice extends RecipeLibraryNotice {
  /// Creates the notice.
  const new(this.recipe, {required this.isArchived});

  /// The recipe as it was before the flag moved.
  final Recipe recipe;

  /// The flag that was applied.
  final bool isArchived;
}

/// [copy] was stored as a new recipe and the rows were read again.
///
/// The screen opens the editor on [copy] so the operator can rename it.
/// Handled at the screen level rather than by the row that asked, because
/// the re-read that precedes this notice replaces the list with a spinner
/// for a frame, and the row's own element is gone by the time the copy is
/// known.
final class RecipeDuplicatedNotice extends RecipeLibraryNotice {
  /// Creates the notice.
  const new(this.copy);

  /// The stored copy, at revision 1.
  final Recipe copy;
}

/// [action] threw before anything was re-read; the rows on screen are the
/// ones from before it.
final class RecipeActionFailedNotice extends RecipeLibraryNotice {
  /// Creates the notice.
  const new(this.action);

  /// Which action failed.
  final RecipeLibraryAction action;
}

/// View state for the recipe library screen.
///
/// Equality is deliberately left at identity, matching the domain layer's
/// rule that only the types something compares by value define `==`.
/// Nothing compares two of these: the view reads fields, and so do the
/// tests, so `emit` re-emitting an equal state is harmless — the screen
/// rebuilds from the same fields either way.
@immutable
final class RecipeLibraryState {
  /// Creates a state. The defaults are the state the cubit starts in: a
  /// read is assumed to be in flight, because `load` is called immediately.
  const new({
    this.status = RecipeLibraryStatus.loading,
    this.recipes = const [],
    this.query = '',
    this.resultsQuery = '',
    this.showArchived = false,
    this.selectedCategory,
    this.isDuplicating = false,
    this.notice,
  });

  /// Whether the last read is in flight, succeeded, or failed.
  final RecipeLibraryStatus status;

  /// Everything the last read returned, newest first, archived recipes
  /// included. [visibleRecipes] is what the list renders.
  final List<Recipe> recipes;

  /// The current search text. An empty query matches everything.
  final String query;

  /// The query [recipes] answers. Trails [query] while a read is pending.
  ///
  /// The field shows [query], and the empty state explains [recipes], so
  /// the two read different fields: after a no-match search is cleared,
  /// [query] is empty at once while [recipes] still holds that search's
  /// nothing until the debounce and the read have run. Judging the empty
  /// state on [query] there calls the library unfilled, and offers to
  /// create a recipe over one that holds several.
  final String resultsQuery;

  /// Whether archived recipes are included in [visibleRecipes].
  final bool showArchived;

  /// The category [visibleRecipes] is narrowed to, or `null` for every
  /// category.
  ///
  /// Held here rather than in the widget tree so it survives the screen
  /// re-laying itself out from one pane to two, the same as [showArchived]
  /// and [query] do.
  final String? selectedCategory;

  /// Whether a duplicate this screen started is still in flight: the copy
  /// is being stored, or the rows are being read again after it was.
  ///
  /// The screen disables its Duplicate controls while this is set, and the
  /// cubit drops a second `duplicate` call that arrives anyway. One flag for
  /// the whole screen rather than a set of source ids, because a single
  /// operator taps one control at a time; what this exists to stop is a
  /// double tap, not two people. Archiving carries no such flag: setting
  /// the same flag twice stores the same thing, so a repeated archive costs
  /// a second notice and nothing else.
  final bool isDuplicating;

  /// The most recent row action's outcome, for the screen to react to once.
  /// See [RecipeLibraryNotice] for why it is compared by identity.
  final RecipeLibraryNotice? notice;

  /// The categories the filter offers, distinct and sorted.
  ///
  /// Drawn from [recipes] — the current result set, so a search narrows the
  /// chips along with the rows — plus [selectedCategory] whenever the
  /// result set no longer holds it. Without that addition, selecting a
  /// category and then typing a search that excludes every recipe in it
  /// would take the chip away while its filter stayed in force, leaving no
  /// visible way to turn it off. Empty when no result carries a category
  /// and none is selected, which is what tells the screen to leave the
  /// whole row out: at load that is a library with no category at all, and
  /// under a search it is a result set with none, so a search matching only
  /// uncategorised recipes takes the row with the chips and clearing it
  /// brings both back. The state holds no other set to draw from — a read
  /// answers one query — and a chip for a category the results do not hold
  /// would filter them down to nothing.
  List<String> get categories {
    final distinct = <String>{
      for (final recipe in recipes) ?recipe.category,
      ?selectedCategory,
    };
    return distinct.toList()..sort();
  }

  /// [recipes] narrowed to [selectedCategory], archived rows included.
  ///
  /// The list every other filter builds on: [visibleRecipes] takes the
  /// archived rows out of this, and [hasHiddenArchived] asks about the
  /// archived rows *in* this, so the two never disagree about which rows
  /// the category has already excluded.
  List<Recipe> get categoryFiltered => selectedCategory == null
      ? recipes
      : [
          for (final recipe in recipes)
            if (recipe.category == selectedCategory) recipe,
        ];

  /// The rows the screen shows.
  ///
  /// Archived recipes are filtered here rather than in the use case:
  /// `ListLibrary` returns them by contract, so the screen is what decides
  /// whether they are shown, and toggling the switch re-filters what is
  /// already loaded instead of reading again. The category filter is
  /// applied the same way, and for the same reason.
  List<Recipe> get visibleRecipes => showArchived
      ? categoryFiltered
      : [
          for (final recipe in categoryFiltered)
            if (!recipe.isArchived) recipe,
        ];

  /// Whether the switch is hiding at least one row the last read returned
  /// that the category filter would otherwise show.
  ///
  /// The empty state reads this to tell "there is nothing here" apart from
  /// "everything here is archived", which are different situations with
  /// different fixes — the second one is undone by the switch, and a
  /// message chosen from [query] alone pointed away from it. After a
  /// search this is still exact, because [recipes] holds that search's own
  /// matches: the hidden rows are the matches the switch is suppressing.
  ///
  /// Judged on [categoryFiltered], not [recipes]: an archived recipe in a
  /// category other than the selected one is not what the switch is
  /// hiding, and counting it would point at a switch that shows nothing.
  bool get hasHiddenArchived => !showArchived && categoryFiltered.any((recipe) => recipe.isArchived);

  /// This state with the named fields replaced.
  ///
  /// [clearSelectedCategory] is how the selection returns to every
  /// category: a `null` argument reads as "keep the current one", so
  /// clearing needs its own flag, the same shape the editor's `copyWith`
  /// uses for its save error.
  RecipeLibraryState copyWith({
    RecipeLibraryStatus? status,
    List<Recipe>? recipes,
    String? query,
    String? resultsQuery,
    bool? showArchived,
    String? selectedCategory,
    bool clearSelectedCategory = false,
    bool? isDuplicating,
    RecipeLibraryNotice? notice,
  }) => RecipeLibraryState(
    status: status ?? this.status,
    recipes: recipes ?? this.recipes,
    query: query ?? this.query,
    resultsQuery: resultsQuery ?? this.resultsQuery,
    showArchived: showArchived ?? this.showArchived,
    selectedCategory: clearSelectedCategory ? null : selectedCategory ?? this.selectedCategory,
    isDuplicating: isDuplicating ?? this.isDuplicating,
    notice: notice ?? this.notice,
  );
}
