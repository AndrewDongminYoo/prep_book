/// The application unit's public surface.
///
/// Exports the use cases that orchestrate the domain and persistence layers
/// on the presentation layer's behalf. Its own boundary test
/// (`test/application/application_boundary_test.dart`) enforces which
/// packages code under this directory may import.
library;

export 'delete_ingredient.dart';
export 'dependency_closure.dart';
export 'production_history.dart';
export 'production_run_edits.dart';
export 'recipe_library.dart';
export 'recipe_lifecycle.dart';
export 'save_recipe_revision.dart';
export 'start_production_run.dart';
