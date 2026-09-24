import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/domain/domain.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:prep_book/presentation/recipe_editor/cubit/recipe_editor_cubit.dart';
import 'package:sqflite/sqflite.dart';

final class _Clock implements Clock {
  @override
  DateTime now() => DateTime.utc(2026, 9, 24);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Database db;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('prep-book-review-');
    db = await openPrepBookDatabase(path: '${directory.path}/candidate.db', singleInstance: false);
  });

  tearDown(() async {
    if (db.isOpen) await db.close();
    await directory.delete(recursive: true);
  });

  testWidgets('native SQLite rejects a mismatched run source before restore', (_) async {
    final recipe = Recipe(
      id: 'bread',
      revision: 1,
      name: 'Bread',
      baseYield: Quantity.parse('1000', Unit.gram),
      modifiedAt: _Clock().now(),
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
    final run = ProductionRun(
      id: 'run',
      createdAt: _Clock().now(),
      recipe: recipe,
      dependencySnapshot: const {},
      targetYield: recipe.baseYield,
      result: const ProductionCalculator().calculate(recipe: recipe, targetYield: recipe.baseYield),
    );
    await SqfliteProductionRunRepository(db).save(run);
    await db.close();
    final validator = BackupDatabaseValidator(factory: databaseFactory);
    final candidatePath = '${directory.path}/candidate.db';
    await validator.validate(candidatePath: candidatePath, manifestSchemaVersion: currentSchemaVersion);

    db = await openPrepBookDatabase(path: candidatePath, singleInstance: false);
    final payload = jsonDecode(encodeRunPayload(run)) as Map<String, Object?>;
    final result = payload['result']! as Map<String, Object?>;
    final components = result['components']! as List<Object?>;
    final source = (components.first! as Map<String, Object?>)['source']! as Map<String, Object?>;
    (source['target']! as Map<String, Object?>)['id'] = 'salt';
    await db.update('production_runs', {'result_json': jsonEncode(payload)}, where: 'id = ?', whereArgs: [run.id]);
    await db.close();

    await expectLater(
      validator.validate(candidatePath: candidatePath, manifestSchemaVersion: currentSchemaVersion),
      throwsA(
        isA<LibraryBackupException>().having((error) => error.kind, 'kind', LibraryBackupFailureKind.invalidDatabase),
      ),
    );
  });

  testWidgets('two editor saves store one native SQLite revision', (_) async {
    final recipes = SqfliteRecipeRepository(db);
    final ingredients = SqfliteIngredientRepository(db);
    final editor = RecipeEditorCubit(
      ListLibrary(recipes),
      ListIngredients(ingredients),
      SaveRecipeRevision(recipes, _Clock()),
      CreateRecipe(recipes, _Clock()),
      SaveIngredient(ingredients),
    );
    addTearDown(editor.close);
    await editor.load();
    editor
      ..nameChanged('Bread')
      ..baseYieldAmountChanged('1000')
      ..baseYieldUnitChanged(Unit.gram);
    await Future.wait([editor.save(), editor.save()]);
    expect(editor.state.status, RecipeEditorStatus.saved);
    expect(editor.state.saveError, isNull);
    expect(await db.query('recipes'), hasLength(1));
    expect((await recipes.findLatest('bread'))?.revision, 1);
  });
}
