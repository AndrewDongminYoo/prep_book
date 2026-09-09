/// The presentation unit's public surface.
///
/// Screens, their view state, and nothing else. Its own boundary test
/// (`test/presentation/presentation_boundary_test.dart`) enforces which
/// packages code under this directory may import, and in particular that it
/// reaches storage only through the application layer's use cases.
library;

export 'production_setup/production_setup.dart';
export 'recipe_editor/recipe_editor.dart';
export 'recipe_library/recipe_library.dart';
