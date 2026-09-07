import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/database.dart';
import 'package:prep_book/persistence/errors.dart';
import 'package:prep_book/persistence/sqflite/ingredient_repository.dart';
import 'package:prep_book/persistence/sqflite/production_run_repository.dart';
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

/// The label the repositories would thread into [decodeRunPayload]. The two
/// payload tests in this file call the codec directly on a payload that
/// belongs to no stored row, so the label only has to be present.
const _payloadRowLabel = 'production_runs row run-1';

/// Matches a [CorruptDatabaseError] whose message names [row] *and* contains
/// [detail], so a test proves both that the failure identifies the stored row
/// and *which* guard fired.
///
/// The row is a separate argument rather than one half of a single fragment
/// because a one-argument matcher can certify a message that names no row at
/// all — which is what this file exists to rule out, and what an earlier
/// revision of this suite pinned as correct for `unknown unit symbol`.
/// Splitting the two makes that omission impossible to write down.
Matcher corruptRowNaming(String row, String detail) =>
    isA<CorruptDatabaseError>().having(
      (error) => error.message,
      'message',
      allOf(contains(row), contains(detail)),
    );

/// Matches a [CorruptDatabaseError] raised inside a run payload, whose
/// message names a position within that payload rather than a row.
///
/// Exists only for those messages: a separate ruling on this branch left
/// the payload-internal failures naming their position, and the row they
/// came from is named by the two decoder messages that carry it
/// ([decodeRunPayload]'s parse failure and an unknown warning kind).
/// It is not an escape hatch from [corruptRowNaming]'s row argument — a
/// failure that reads a stored *column* must use that matcher.
Matcher corruptPayloadDetail(String detail) =>
    isA<CorruptDatabaseError>().having(
      (error) => error.message,
      'message',
      contains(detail),
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
        throwsA(
          corruptRowNaming(
            'ingredients row x',
            'unknown unit symbol in ingredients row x: parsec',
          ),
        ),
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
        throwsA(
          corruptRowNaming(
            'production_runs row broken',
            'run payload of production_runs row broken is not valid JSON',
          ),
        ),
      );
    },
  );

  // The brief's third corruption test targeted `ingredients`, whose
  // `default_unit_symbol` is `NOT NULL` and so cannot be set to NULL at all.
  // `recipe_components.base_numerator` is legitimately nullable — a manual
  // component stores the whole group as NULL — so a group filled in *part
  // way* is the hazard that can really occur: `_componentFromRow` decides
  // whether to read a quantity by looking at `base_unit` alone.
  //
  // The asserted fragment carries the row label as well as the column group.
  // `base` and `target` name column groups on more than one table, so the
  // group alone would leave the reader knowing only that some quantity
  // somewhere was incomplete — which is what this whole file exists to
  // rule out.
  test(
    'a half-filled quantity group throws rather than defaulting to zero',
    () async {
      await recipes.saveRevision(buildRecipe());
      await db.rawUpdate('UPDATE recipe_components SET base_numerator = NULL');

      await expectLater(
        recipes.findLatest('r'),
        throwsA(
          corruptRowNaming(
            'recipe_components row r revision 1 component flour',
            'incomplete quantity in column group base',
          ),
        ),
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
      throwsA(
        corruptRowNaming(
          'ingredients row blob',
          'holds a column of the wrong type',
        ),
      ),
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
      throwsA(
        corruptRowNaming(
          'recipes row r revision not-an-integer',
          'holds a column of the wrong type',
        ),
      ),
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

    // The corrupted column is the one the label itself names, so the label
    // reports the BLOB rather than a component id — which is the point: it
    // is built from the raw values so it survives the corruption it
    // describes. `holds a column of the wrong type` pins which of this
    // block's two clauses fired.
    await expectLater(
      recipes.findLatest('r'),
      throwsA(
        corruptRowNaming(
          'recipe_components row r revision 1 component [4, 5, 6]',
          'holds a column of the wrong type',
        ),
      ),
    );
  });

  // --- the row label each caller threads into quantityFromColumns ---------
  //
  // A quantity group knows its column prefix but not its table, and the
  // prefixes repeat: `base` is on `recipe_components`, `base_yield` on
  // `recipes`, `target` on `production_runs`, `override` on `run_overrides`.
  // Each caller therefore passes a row label, and each label needs a test
  // that pins it — otherwise a wrong label is invisible, since the guard
  // still throws the right *type*. The four tests below corrupt the same way
  // in four tables and assert that the four messages differ.
  //
  // They corrupt by writing a BLOB rather than a NULL: only
  // `recipe_components.base_*` is nullable, so `UPDATE … SET
  // base_yield_numerator = NULL` is refused by the `NOT NULL` constraint
  // before the read ever happens. A BLOB satisfies the constraint and still
  // fails `quantityFromColumns`'s `is! String` check, which is the branch
  // under test.

  test('a wrong-typed quantity column names the recipes row', () async {
    await recipes.saveRevision(buildRecipe());
    await db.update('recipes', <String, Object?>{
      'base_yield_numerator': Uint8List.fromList(const [1]),
    });

    await expectLater(
      recipes.findLatest('r'),
      throwsA(
        corruptRowNaming(
          'recipes row r revision 1',
          'incomplete quantity in column group base_yield',
        ),
      ),
    );
  });

  // The worst case the row label exists for: `listSummaries` walks the whole
  // run history, so a message naming only the column group would say a
  // quantity somewhere in the table was incomplete and leave the reader to
  // find which run.
  test(
    'a wrong-typed target column names the run on the summary path',
    () async {
      await runs.save(buildRun());
      await db.update('production_runs', <String, Object?>{
        'target_numerator': Uint8List.fromList(const [1]),
      });

      await expectLater(
        runs.listSummaries(),
        throwsA(
          corruptRowNaming(
            'production_runs row run-1',
            'incomplete quantity in column group target',
          ),
        ),
      );
    },
  );

  test(
    'a wrong-typed target column names the run on the findById path',
    () async {
      await runs.save(buildRun());
      await db.update('production_runs', <String, Object?>{
        'target_numerator': Uint8List.fromList(const [1]),
      });

      await expectLater(
        runs.findById('run-1'),
        throwsA(
          corruptRowNaming(
            'production_runs row run-1',
            'incomplete quantity in column group target',
          ),
        ),
      );
    },
  );

  test('a wrong-typed override column names the override row', () async {
    await runs.save(buildRun());
    await runs.recordOverride(
      'run-1',
      ('r', 'flour'),
      Quantity.parse('5', Unit.gram),
    );
    await db.update('run_overrides', <String, Object?>{
      'override_numerator': Uint8List.fromList(const [1]),
    });

    await expectLater(
      runs.findById('run-1'),
      throwsA(
        corruptRowNaming(
          'run_overrides row for run run-1 recipe r component flour',
          'incomplete quantity in column group override',
        ),
      ),
    );
  });

  // `Rational` throws `ArgumentError` on a zero denominator, which is an
  // `Error` rather than an `Exception` and is not a `TypeError` either, so
  // it escapes every shape guard this layer has. Both places that rebuild a
  // stored numerator/denominator pair go through `parseStoredRational`; each
  // is covered here so neither can regress to a raw `Rational` call.
  // Driven through the repository rather than by calling
  // `quantityFromColumns` on a hand-built map, so the assertion pins the row
  // label the caller threads in as well as the guard itself. A synthetic map
  // belongs to no table and could not tell the two apart.
  test(
    'a zero denominator in a stored quantity group is corrupt',
    () async {
      await recipes.saveRevision(buildRecipe());
      await db.rawUpdate("UPDATE recipe_components SET base_denominator = '0'");

      await expectLater(
        recipes.findLatest('r'),
        throwsA(
          corruptRowNaming(
            'recipe_components row r revision 1 component flour',
            'has a zero denominator',
          ),
        ),
      );
    },
  );

  test('a zero denominator in a stored run payload is corrupt', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRun())) as Map<String, Object?>;
    final recipe = encoded['recipe']! as Map<String, Object?>;
    (recipe['baseYield']! as Map<String, Object?>)['d'] = '0';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _payloadRowLabel),
      throwsA(
        corruptPayloadDetail('a run payload quantity has a zero denominator'),
      ),
    );
  });

  // The other way `parseStoredRational` can fail: `BigInt.parse` throws a
  // `FormatException`, which is not an `Error` and so would have escaped
  // past a handler that only caught `ArgumentError`.
  test('a non-integer stored amount is corrupt', () async {
    await recipes.saveRevision(buildRecipe());
    await db.rawUpdate("UPDATE recipe_components SET base_numerator = 'half'");

    await expectLater(
      recipes.findLatest('r'),
      throwsA(
        corruptRowNaming(
          'recipe_components row r revision 1 component flour',
          'is not an integer pair',
        ),
      ),
    );
  });

  // --- production_runs and its two side tables ----------------------------
  //
  // The same wrong-typed-column hazard as `ingredients` and `recipes`, on the
  // fourth repository. `findById` is the reason these matter beyond
  // symmetry: `_overridesFor` and `_acknowledgementsFor` are read on its own
  // call path, so without a guard there a corrupt override row surfaces a
  // raw `TypeError` out of the very method whose other failure modes name
  // their row.

  test('a BLOB in a production_runs TEXT column is a corrupt row', () async {
    await runs.save(buildRun());
    await db.update('production_runs', <String, Object?>{
      'recipe_id': Uint8List.fromList(const [1, 2, 3]),
    });

    await expectLater(
      runs.listSummaries(),
      throwsA(
        corruptRowNaming(
          'production_runs row run-1',
          'holds a column of the wrong type',
        ),
      ),
    );
  });

  test('an unparseable production_runs.created_at is a corrupt row', () async {
    await runs.save(buildRun());
    await db.update('production_runs', <String, Object?>{
      'created_at': 'yesterday',
    });

    await expectLater(
      runs.listSummaries(),
      throwsA(
        corruptRowNaming(
          'production_runs row run-1',
          'has an unparseable column',
        ),
      ),
    );
  });

  // `findById` reads `result_json` and `created_at` itself rather than
  // through `_summaryFromRow`, so both of its clauses need their own reach.
  test('a BLOB in production_runs.result_json is a corrupt row', () async {
    await runs.save(buildRun());
    await db.update('production_runs', <String, Object?>{
      'result_json': Uint8List.fromList(const [1, 2, 3]),
    });

    await expectLater(
      runs.findById('run-1'),
      throwsA(
        corruptRowNaming(
          'production_runs row run-1',
          'holds a column of the wrong type',
        ),
      ),
    );
  });

  test(
    'an unparseable created_at is a corrupt row on the findById path too',
    () async {
      await runs.save(buildRun());
      await db.update('production_runs', <String, Object?>{
        'created_at': 'yesterday',
      });

      await expectLater(
        runs.findById('run-1'),
        throwsA(
          corruptRowNaming(
            'production_runs row run-1',
            'has an unparseable column',
          ),
        ),
      );
    },
  );

  test('a BLOB in a run_acknowledgements column is a corrupt row', () async {
    await runs.save(buildRun());
    await db.insert('run_acknowledgements', <String, Object?>{
      'run_id': 'run-1',
      'warning_kind': 'archived_dependency',
      'recipe_id': Uint8List.fromList(const [7]),
      'component_id': null,
    });

    await expectLater(
      runs.findById('run-1'),
      throwsA(
        corruptRowNaming(
          'run_acknowledgements row for run run-1',
          'holds a column of the wrong type',
        ),
      ),
    );
  });

  test('a BLOB in a run_overrides key column is a corrupt row', () async {
    await runs.save(buildRun());
    await runs.recordOverride(
      'run-1',
      ('r', 'flour'),
      Quantity.parse('5', Unit.gram),
    );
    await db.update('run_overrides', <String, Object?>{
      'component_id': Uint8List.fromList(const [8]),
    });

    await expectLater(
      runs.findById('run-1'),
      throwsA(
        corruptRowNaming(
          'run_overrides row for run run-1',
          'holds a column of the wrong type',
        ),
      ),
    );
  });

  // --- parses that read a stored column -----------------------------------
  //
  // `DateTime.parse`, `Decimal.parse`, and `jsonDecode` all throw
  // `FormatException`, which is not an `Error` and so is not caught by the
  // `on TypeError` guards above. Each block that owns one of these parses
  // needs its own clause, and each clause needs a test that reaches it.

  test('an unparseable recipes.preparation_notes is a corrupt row', () async {
    await recipes.saveRevision(buildRecipe());
    await db.rawUpdate("UPDATE recipes SET preparation_notes = 'not json'");

    await expectLater(
      recipes.findLatest('r'),
      throwsA(
        corruptRowNaming(
          'recipes row r revision 1',
          'has an unparseable column',
        ),
      ),
    );
  });

  // The second corrupt input to the same column, and it takes a different
  // clause: text that parses as JSON but is not a list fails at the
  // `as List<dynamic>` cast, which is a `TypeError`, not at the parse.
  test(
    'a preparation_notes that is valid JSON but not a list is a corrupt row',
    () async {
      await recipes.saveRevision(buildRecipe());
      await db.rawUpdate(
        'UPDATE recipes SET preparation_notes = \'{"a":1}\'',
      );

      await expectLater(
        recipes.findLatest('r'),
        throwsA(
          corruptRowNaming(
            'recipes row r revision 1',
            'holds a column of the wrong type',
          ),
        ),
      );
    },
  );

  test('an unparseable recipes.modified_at is a corrupt row', () async {
    await recipes.saveRevision(buildRecipe());
    await db.rawUpdate("UPDATE recipes SET modified_at = 'yesterday'");

    await expectLater(
      recipes.findLatest('r'),
      throwsA(
        corruptRowNaming(
          'recipes row r revision 1',
          'has an unparseable column',
        ),
      ),
    );
  });

  test(
    'an unparseable recipe_components.rounding_increment is a corrupt row',
    () async {
      await recipes.saveRevision(buildRecipe());
      await db.rawUpdate(
        "UPDATE recipe_components SET rounding_increment = 'a lot'",
      );

      // `recipe_components row …` alone is the prefix both of this block's
      // clauses emit, so it would pass just as well if the `TypeError`
      // clause had fired. `has an unparseable column` is the half that pins
      // the clause.
      await expectLater(
        recipes.findLatest('r'),
        throwsA(
          corruptRowNaming(
            'recipe_components row r revision 1 component flour',
            'has an unparseable column',
          ),
        ),
      );
    },
  );

  test('an unparseable rounding increment in a run payload is corrupt', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRun())) as Map<String, Object?>;
    final recipe = encoded['recipe']! as Map<String, Object?>;
    final components = recipe['components']! as List<Object?>;
    (components.first! as Map<String, Object?>)['roundingIncrement'] = 'a lot';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _payloadRowLabel),
      throwsA(corruptPayloadDetail('run payload holds an unparseable value')),
    );
  });

  test('an unparseable modifiedAt in a run payload is corrupt', () {
    final encoded =
        jsonDecode(encodeRunPayload(buildRun())) as Map<String, Object?>;
    (encoded['recipe']! as Map<String, Object?>)['modifiedAt'] = 'yesterday';

    expect(
      () => decodeRunPayload(jsonEncode(encoded), rowLabel: _payloadRowLabel),
      throwsA(corruptPayloadDetail('run payload holds an unparseable value')),
    );
  });
}
