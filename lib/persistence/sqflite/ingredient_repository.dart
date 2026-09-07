import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/repositories.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';
import 'package:sqflite/sqflite.dart';

/// [IngredientRepository] backed by the `ingredients` table.
final class SqfliteIngredientRepository implements IngredientRepository {
  /// Creates a repository over the already-open database [_db].
  const SqfliteIngredientRepository(this._db);

  final Database _db;

  @override
  Future<List<Ingredient>> listAll() async {
    final rows = await _db.query('ingredients', orderBy: 'name');
    return rows.map(_fromRow).toList();
  }

  @override
  Future<Ingredient?> findById(String id) async {
    final rows = await _db.query(
      'ingredients',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.single);
  }

  @override
  Future<void> upsert(Ingredient ingredient) => _db.insert(
    'ingredients',
    <String, Object?>{
      'id': ingredient.id,
      'name': ingredient.name,
      'default_unit': unitToStorage(ingredient.defaultUnit),
      'category': ingredient.category,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<void> delete(String id) =>
      _db.delete('ingredients', where: 'id = ?', whereArgs: [id]);

  /// Rebuilds the [Ingredient] an `ingredients` row holds.
  ///
  /// The column casts below are unchecked, and a value can reach them at a
  /// type its column does not declare: SQLite's TEXT affinity converts a
  /// number to text but leaves a BLOB alone, so a BLOB written into any of
  /// these `TEXT` columns comes back from sqflite as a `Uint8List` and the
  /// cast throws a bare `TypeError` naming no row. Restating it as a
  /// [CorruptDatabaseError] here mirrors `decodeRunPayload`'s handling of
  /// the same shape. A domain rejection is not swallowed by this: every
  /// modelled domain failure extends `DomainError`, never `TypeError`.
  Ingredient _fromRow(Map<String, Object?> row) {
    // Shared by this method's own guard and the [unitFromStorage] call
    // inside it, so a row that fails on its stored unit is named the same
    // way as one that fails on a cast — `listAll` scans the whole table, so
    // an unnamed failure would say only that some ingredient somewhere was
    // unreadable. Reads the raw id rather than the cast below, because the
    // label has to survive the corruption it describes.
    final rowLabel = 'ingredients row ${row['id']}';
    try {
      return Ingredient(
        id: row['id']! as String,
        name: row['name']! as String,
        defaultUnit: unitFromStorage(
          row['default_unit']! as String,
          location: rowLabel,
        ),
        category: row['category'] as String?,
      );
      // A wrong-typed column is a corrupt row, not a programmer bug, so its
      // `TypeError` is caught rather than left to escape — see the doc
      // comment above.
      // ignore: avoid_catching_errors
    } on TypeError catch (error) {
      throw CorruptDatabaseError(
        '$rowLabel holds a column of the wrong type: $error',
      );
    }
  }
}
