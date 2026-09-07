import 'package:prep_book/domain/domain.dart';
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
      'default_unit_symbol': unitToStorage(ingredient.defaultUnit),
      'category': ingredient.category,
    },
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  @override
  Future<void> delete(String id) =>
      _db.delete('ingredients', where: 'id = ?', whereArgs: [id]);

  Ingredient _fromRow(Map<String, Object?> row) => Ingredient(
    id: row['id']! as String,
    name: row['name']! as String,
    defaultUnit: unitFromStorage(row['default_unit_symbol']! as String),
    category: row['category'] as String?,
  );
}
