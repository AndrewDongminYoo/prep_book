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
  const RecipeLibraryState({
    this.status = RecipeLibraryStatus.loading,
    this.recipes = const [],
    this.query = '',
    this.showArchived = false,
  });

  /// Whether the last read is in flight, succeeded, or failed.
  final RecipeLibraryStatus status;

  /// Everything the last read returned, newest first, archived recipes
  /// included. [visibleRecipes] is what the list renders.
  final List<Recipe> recipes;

  /// The current search text. An empty query matches everything.
  final String query;

  /// Whether archived recipes are included in [visibleRecipes].
  final bool showArchived;

  /// The rows the screen shows.
  ///
  /// Archived recipes are filtered here rather than in the use case:
  /// `ListLibrary` returns them by contract, so the screen is what decides
  /// whether they are shown, and toggling the switch re-filters what is
  /// already loaded instead of reading again.
  List<Recipe> get visibleRecipes => showArchived
      ? recipes
      : [
          for (final recipe in recipes)
            if (!recipe.isArchived) recipe,
        ];

  /// Whether the switch is hiding at least one row the last read returned.
  ///
  /// The empty state reads this to tell "there is nothing here" apart from
  /// "everything here is archived", which are different situations with
  /// different fixes — the second one is undone by the switch, and a
  /// message chosen from [query] alone pointed away from it. After a
  /// search this is still exact, because [recipes] holds that search's own
  /// matches: the hidden rows are the matches the switch is suppressing.
  bool get hasHiddenArchived =>
      !showArchived && recipes.any((recipe) => recipe.isArchived);

  /// This state with the named fields replaced.
  RecipeLibraryState copyWith({
    RecipeLibraryStatus? status,
    List<Recipe>? recipes,
    String? query,
    bool? showArchived,
  }) => RecipeLibraryState(
    status: status ?? this.status,
    recipes: recipes ?? this.recipes,
    query: query ?? this.query,
    showArchived: showArchived ?? this.showArchived,
  );
}
