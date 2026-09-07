/// The persistence unit's public surface.
///
/// `schema/v1.dart` is deliberately absent: its DDL is an implementation
/// detail of `openPrepBookDatabase` rather than something a caller of this
/// unit reaches for. Every other file that declares public API is here, so
/// the barrel states the boundary instead of describing part of it.
library;

export 'database.dart';
export 'errors.dart';
export 'repositories.dart';
export 'sqflite/ingredient_repository.dart';
export 'sqflite/production_run_repository.dart';
export 'sqflite/quantity_columns.dart';
export 'sqflite/recipe_repository.dart';
export 'sqflite/result_codec.dart';
export 'sqflite/timestamps.dart';
