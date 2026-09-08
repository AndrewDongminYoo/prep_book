import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:prep_book/persistence/sqflite/ingredient_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late SqfliteIngredientRepository repository;

  setUp(() async {
    db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    repository = SqfliteIngredientRepository(db);
  });

  tearDown(() => db.close());

  // `Ingredient` has no `operator ==` (only `Unit` and `Quantity` do), so a
  // round-trip is checked field by field rather than with a single `expect`
  // against the original instance.
  test('an ingredient round-trips', () async {
    final flour = Ingredient(
      id: 'flour',
      name: 'Flour',
      defaultUnit: Unit.gram,
    );
    await repository.upsert(flour);

    final found = await repository.findById('flour');
    expect(found?.id, flour.id);
    expect(found?.name, flour.name);
    expect(found?.defaultUnit, flour.defaultUnit);
    expect(found?.category, flour.category);
  });

  test('a missing id reads as null rather than throwing', () async {
    expect(await repository.findById('absent'), isNull);
  });

  test('upsert replaces rather than duplicating', () async {
    final first = Ingredient(id: 'f', name: 'Flour', defaultUnit: Unit.gram);
    final renamed = Ingredient(
      id: 'f',
      name: 'Bread flour',
      defaultUnit: Unit.gram,
    );
    await repository.upsert(first);
    await repository.upsert(renamed);

    expect(await repository.listAll(), hasLength(1));
    expect((await repository.findById('f'))!.name, 'Bread flour');
  });

  test('delete removes the row', () async {
    final flour = Ingredient(
      id: 'flour',
      name: 'Flour',
      defaultUnit: Unit.gram,
    );
    await repository.upsert(flour);
    await repository.delete('flour');

    expect(await repository.listAll(), isEmpty);
  });

  // A count unit is stored as `count:<symbol>` by `unitToStorage`, not as
  // its bare symbol — writing `defaultUnit.symbol` directly (the brief's
  // original pseudocode) would make this ingredient unreadable, because
  // `each` alone matches no fixed unit and `unitFromStorage` would reject it
  // as a corrupt row instead of reconstructing `Unit.count('each')`.
  test(
    'an ingredient whose default unit is a custom count unit round-trips',
    () async {
      final widget = Ingredient(
        id: 'widget',
        name: 'Widget',
        defaultUnit: Unit.count('each'),
      );
      await repository.upsert(widget);

      final found = await repository.findById('widget');
      expect(found?.defaultUnit, Unit.count('each'));
    },
  );
}
