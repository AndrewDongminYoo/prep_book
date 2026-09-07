import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/ingredient_repository.dart';
import 'package:prep_book/persistence/sqflite/production_run_repository.dart';
import 'package:prep_book/persistence/sqflite/quantity_columns.dart';
import 'package:prep_book/persistence/sqflite/recipe_repository.dart';
import 'package:prep_book/persistence/sqflite/result_codec.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A one-component recipe, built through the domain's real factory. Kept
/// independent of the other suites' fixtures, matching this directory's
/// convention of self-contained per-file fixtures.
Recipe buildRecipe({String id = 'r', int revision = 1}) => Recipe(
  id: id,
  revision: revision,
  name: 'Test recipe',
  baseYield: Quantity.parse('1000', Unit.gram),
  modifiedAt: DateTime.utc(2026, 9, 7),
  components: [
    RecipeComponent(
      id: 'flour',
      target: const IngredientRef('flour'),
      baseQuantity: Quantity.parse('500', Unit.gram),
      behavior: ScalingBehavior.proportional,
      displayOrder: 0,
    ),
  ],
);

/// A run computed from [buildRecipe], scaled 1:1.
ProductionRun buildRun({String id = 'run-1'}) {
  final recipe = buildRecipe();
  final targetYield = recipe.baseYield;
  return ProductionRun(
    id: id,
    createdAt: DateTime.utc(2026, 9, 7),
    recipe: recipe,
    dependencySnapshot: const {},
    targetYield: targetYield,
    result: const ProductionCalculator().calculate(
      recipe: recipe,
      targetYield: targetYield,
    ),
  );
}

/// Matches a [CorruptDatabaseError] whose message contains [fragment], so a
/// test proves *which* guard fired rather than only that something did.
Matcher corruptRowNaming(String fragment) => isA<CorruptDatabaseError>().having(
  (error) => error.message,
  'message',
  contains(fragment),
);

void main() {
  setUpAll(sqfliteFfiInit);

  late Database db;
  late SqfliteIngredientRepository ingredients;
  late SqfliteRecipeRepository recipes;
  late SqfliteProductionRunRepository runs;

  setUp(() async {
    db = await openPrepBookDatabase(
      path: inMemoryDatabasePath,
      factory: databaseFactoryFfi,
    );
    ingredients = SqfliteIngredientRepository(db);
    recipes = SqfliteRecipeRepository(db);
    runs = SqfliteProductionRunRepository(db);
  });

  tearDown(() => db.close());

  test(
    'an unknown unit symbol in a stored row throws rather than guessing',
    () async {
      await db.insert('ingredients', <String, Object?>{
        'id': 'x',
        'name': 'X',
        'default_unit_symbol': 'parsec',
        'category': null,
      });

      await expectLater(
        ingredients.findById('x'),
        throwsA(corruptRowNaming('unknown unit symbol: parsec')),
      );
    },
  );

  // `production_run_repository_test.dart` reaches the same guard from the
  // other direction, on a row `save` wrote and a later `UPDATE` corrupted,
  // to show `listSummaries` never decodes the payload. This one inserts the
  // row directly instead: `findById` must reject a `result_json` it cannot
  // parse even for a row no `save` of this build ever produced, which is the
  // shape a restored or hand-edited database actually has.
  test(
    'unparseable result_json throws rather than returning a partial run',
    () async {
      await db.insert('production_runs', <String, Object?>{
        'id': 'broken',
        'recipe_id': 'r',
        'recipe_revision': 1,
        'target_numerator': '1',
        'target_denominator': '1',
        'target_unit': 'kg',
        'created_at': DateTime.utc(2026).toIso8601String(),
        'result_json': '{not json',
      });

      await expectLater(
        runs.findById('broken'),
        throwsA(corruptRowNaming('run payload is not valid JSON')),
      );
    },
  );

  // The brief's third corruption test targeted `ingredients`, whose
  // `default_unit_symbol` is `NOT NULL` and so cannot be set to NULL at all.
  // `recipe_components.base_numerator` is legitimately nullable — a manual
  // component stores the whole group as NULL — so a group filled in *part
  // way* is the hazard that can really occur: `_componentFromRow` decides
  // whether to read a quantity by looking at `base_unit` alone.
  test(
    'a half-filled quantity group throws rather than defaulting to zero',
    () async {
      await recipes.saveRevision(buildRecipe());
      await db.rawUpdate('UPDATE recipe_components SET base_numerator = NULL');

      await expectLater(
        recipes.findLatest('r'),
        throwsA(corruptRowNaming('incomplete quantity in column group base')),
      );
    },
  );

  // SQLite has type affinity rather than strict typing, and TEXT affinity
  // leaves a BLOB alone while it would convert a number to text. So a BLOB
  // written into any `TEXT NOT NULL` column comes back from sqflite as a
  // `Uint8List` and reaches the row reader's unchecked cast. Without the
  // guard the cast throws a bare `TypeError` that names no row at all.
  test('a BLOB in an ingredients TEXT column is a corrupt row', () async {
    await db.insert('ingredients', <String, Object?>{
      'id': 'blob',
      'name': Uint8List.fromList(const [1, 2, 3]),
      'default_unit_symbol': 'g',
      'category': null,
    });

    await expectLater(
      ingredients.findById('blob'),
      throwsA(corruptRowNaming('ingredients row blob')),
    );
  });

  // The INTEGER half of the same hazard: INTEGER affinity converts a string
  // only when it looks like a number, so a non-numeric one stays TEXT and
  // reaches `_recipeFromRow`'s `as int`.
  test('a non-numeric recipes.revision is a corrupt row', () async {
    await recipes.saveRevision(
      Recipe(
        id: 'r',
        revision: 1,
        name: 'No components',
        baseYield: Quantity.parse('1000', Unit.gram),
        modifiedAt: DateTime.utc(2026, 9, 7),
        components: const [],
      ),
    );
    await db.rawUpdate("UPDATE recipes SET revision = 'not-an-integer'");

    await expectLater(
      recipes.findLatest('r'),
      throwsA(corruptRowNaming('recipes row r revision not-an-integer')),
    );
  });

  // A component's own guard, proven separately from the recipe's: the
  // message must name the `recipe_components` row, not the `recipes` row
  // that reads it, or a corrupt component would be reported against the
  // wrong table.
  test('a BLOB in a recipe_components TEXT column is a corrupt row', () async {
    await recipes.saveRevision(buildRecipe());
    await db.update('recipe_components', <String, Object?>{
      'component_id': Uint8List.fromList(const [4, 5, 6]),
    });

    await expectLater(
      recipes.findLatest('r'),
      throwsA(corruptRowNaming('recipe_components row r revision 1')),
    );
  });

  // `Rational` throws `ArgumentError` on a zero denominator, which is an
  // `Error` rather than an `Exception` and is not a `TypeError` either, so
  // it escapes every shape guard this layer has. Both places that rebuild a
  // stored numerator/denominator pair go through `parseStoredRational`; each
  // is covered here so neither can regress to a raw `Rational` call.
  test('a zero denominator in a stored quantity group is corrupt', () {
    expect(
      () => quantityFromColumns(<String, Object?>{
        'base_numerator': '1',
        'base_denominator': '0',
        'base_unit': 'g',
      }, 'base'),
      throwsA(corruptRowNaming('column group base has a zero denominator')),
    );
  });

  test('a zero denominator in a stored run payload is corrupt', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRun())) as Map<String, Object?>;
    final recipe = encoded['recipe']! as Map<String, Object?>;
    (recipe['baseYield']! as Map<String, Object?>)['d'] = '0';

    expect(
      () => decodeRunPayload(jsonEncode(encoded)),
      throwsA(corruptRowNaming('a run payload quantity has a zero')),
    );
  });

  // The other way `parseStoredRational` can fail: `BigInt.parse` throws a
  // `FormatException`, which is not an `Error` and so would have escaped
  // past a handler that only caught `ArgumentError`.
  test('a non-integer stored amount is corrupt', () {
    expect(
      () => quantityFromColumns(<String, Object?>{
        'base_numerator': 'half',
        'base_denominator': '1',
        'base_unit': 'g',
      }, 'base'),
      throwsA(corruptRowNaming('column group base is not an integer pair')),
    );
  });
}
