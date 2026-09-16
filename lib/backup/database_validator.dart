import 'package:prep_book/application/application.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite/sqflite.dart';

/// Validates a staged database without sharing its handle with the live one.
final class BackupDatabaseValidator {
  /// Creates a validator over the platform or test database [factory].
  BackupDatabaseValidator({required DatabaseFactory factory}) : this._(factory);

  const BackupDatabaseValidator._(this._factory);

  final DatabaseFactory _factory;

  /// Validates the candidate at [candidatePath].
  Future<void> validate({
    required String candidatePath,
    required int manifestSchemaVersion,
  }) async {
    try {
      final storedVersion = await _readStoredVersion(candidatePath);
      if (storedVersion > currentSchemaVersion) {
        _throwValidationFailure(LibraryBackupFailureKind.incompatibleSchema);
      }
      if (storedVersion <= 0 || storedVersion != manifestSchemaVersion) {
        _throwValidationFailure(LibraryBackupFailureKind.invalidDatabase);
      }

      final db = await openPrepBookDatabase(
        path: candidatePath,
        factory: _factory,
        singleInstance: false,
      );
      try {
        await _validateOpenedDatabase(db);
      } finally {
        await db.close();
      }
    } on LibraryBackupException {
      rethrow;
    } on Object catch (error, stackTrace) {
      throw LibraryBackupException(
        LibraryBackupFailureKind.invalidDatabase,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _validateOpenedDatabase(Database db) async {
    final integrityRows = await db.rawQuery('PRAGMA integrity_check');
    if (integrityRows.length != 1 ||
        integrityRows.single.values.single != 'ok') {
      throw const FormatException('SQLite integrity check failed.');
    }
    final foreignKeyRows = await db.rawQuery('PRAGMA foreign_key_check');
    if (foreignKeyRows.isNotEmpty) {
      throw const FormatException('SQLite foreign key check failed.');
    }
    await validatePrepBookSchema(db);

    final ingredients = SqfliteIngredientRepository(db);
    final ingredientRows = await db.query('ingredients', columns: ['id']);
    for (final row in ingredientRows) {
      final id = row['id']! as String;
      await ingredients.findById(id);
    }

    final recipes = SqfliteRecipeRepository(db);
    final recipeRows = await db.query('recipes', columns: ['id', 'revision']);
    for (final row in recipeRows) {
      final id = row['id']! as String;
      final revision = row['revision']! as int;
      await recipes.findRevision(id, revision);
    }

    final runs = SqfliteProductionRunRepository(db);
    final runRows = await db.query('production_runs', columns: ['id']);
    for (final row in runRows) {
      final id = row['id']! as String;
      await runs.findById(id);
    }

    final latest = await recipes.listLatestRevisions();
    final graph = RecipeDependencyGraph({
      for (final recipe in latest) recipe.id: recipe,
    });
    for (final recipe in latest) {
      if (graph.findCycleFrom(recipe.id) != null) {
        throw FormatException(
          'The latest recipe graph contains a cycle from ${recipe.id}.',
        );
      }
    }
  }

  Future<int> _readStoredVersion(String candidatePath) async {
    final db = await _factory.openDatabase(
      candidatePath,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    try {
      return await db.getVersion();
    } finally {
      await db.close();
    }
  }
}

Never _throwValidationFailure(LibraryBackupFailureKind kind) {
  throw LibraryBackupException(
    kind,
    cause: const FormatException('The candidate database is invalid.'),
    stackTrace: StackTrace.current,
  );
}
