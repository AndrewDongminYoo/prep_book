import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';
import 'package:prep_book/domain/domain.dart';

import '../championship_test_harness.dart';

Future<void> _pumpApp(
  WidgetTester tester,
  ChampionshipDemoCubit cubit, {
  Size size = const Size(900, 1000),
  Locale locale = const Locale('en'),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(cubit.close);
  await tester.pumpWidget(
    ChampionshipApp(
      cubit: cubit,
      openProductionSheet: ignoreChampionshipProductionSheet,
      locale: locale,
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _tabTo(WidgetTester tester, Key key) async {
  final target = tester.element(find.byKey(key));
  for (var attempt = 0; attempt < 100; attempt += 1) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus?.context;
    var reached = identical(focused, target);
    if (focused case final Element element) {
      element.visitAncestorElements((ancestor) {
        reached = reached || identical(ancestor, target);
        return !reached;
      });
    }
    if (reached) return;
  }
  fail('Tab did not reach $key.');
}

List<Key> _enabledButtonKeys() => [
  for (final element
      in find
          .byWidgetPredicate((widget) => widget is ButtonStyleButton)
          .evaluate())
    if (element.widget case final ButtonStyleButton button
        when button.onPressed != null && button.key != null)
      button.key!,
];

void main() {
  testWidgets('sample needs no consent or network and shows review evidence', (
    tester,
  ) async {
    final client = RecordingRecipeImportClient(
      (_, _) => throw StateError('network must not be called'),
    );
    final cubit = buildChampionshipTestCubit(client: client);
    await _pumpApp(tester, cubit);

    expect(
      find.text(
        'PrepBook does not persist your source. Live input is sent to the '
        'configured AI provider under its retention and abuse-monitoring '
        'controls. Use the sample for confidential or personal content.',
      ),
      findsOneWidget,
    );

    await _tapVisible(tester, find.byKey(const ValueKey('source-sample')));

    expect(client.requests, isEmpty);
    expect(cubit.state.sourceFailure, isNull);
    expect(cubit.state.phase, ChampionshipPhase.review);
    expect(find.text('AI proposal'), findsWidgets);
    expect(find.text('Evidence'), findsWidgets);
    expect(find.text('High confidence'), findsWidgets);
    expect(find.text('Low confidence'), findsOneWidget);
    expect(find.text('The source does not state a unit.'), findsOneWidget);
    expect(find.text('Needs confirmation'), findsWidgets);
    cubit.continueToTarget();
    await tester.pumpAndSettle();
    expect(find.text('• recipe.name must be confirmed.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('local review issues follow the locale and never repeat the '
      'model', (tester) async {
    final cubit = buildChampionshipTestCubit();
    await cubit.loadSample();
    await _pumpApp(tester, cubit, locale: const Locale('ko'));

    // The water unit is absent and the model already said so; the local
    // check must not add a second line, in either language.
    expect(find.text('The source does not state a unit.'), findsOneWidget);
    expect(find.text('The unit is unsupported.'), findsNothing);
    expect(find.text('지원되지 않는 단위입니다.'), findsNothing);
    expect(find.text('단위를 선택하세요.'), findsNothing);

    tester
        .widget<TextFormField>(
          find.byKey(const ValueKey('recipe.baseYield.amount.input')),
        )
        .onChanged
        ?.call('');
    await tester.pumpAndSettle();

    expect(find.text('수량을 입력하세요.'), findsOneWidget);
    expect(find.text('A quantity is required.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('live text requires consent and loading prevents duplicates', (
    tester,
  ) async {
    final completion = Completer<ExtractedRecipeDraft>();
    final client = RecordingRecipeImportClient((_, _) => completion.future);
    final cubit = buildChampionshipTestCubit(client: client);
    await _pumpApp(tester, cubit, size: const Size(390, 844));
    final submitFinder = find.byKey(const ValueKey('source-submit-text'));

    await tester.enterText(
      find.byKey(const ValueKey('source-text-input')),
      'Dough\nFlour 100 g',
    );
    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNull);

    await _tapVisible(tester, find.byKey(const ValueKey('source-consent')));
    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNotNull);
    await tester.ensureVisible(submitFinder);
    await tester.tap(submitFinder);
    await tester.pump();

    expect(client.requests, hasLength(1));
    expect(
      tester
          .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator))
          .value,
      isNull,
      reason: 'the extraction has no known duration, so the bar animates',
    );
    expect(tester.widget<FilledButton>(submitFinder).onPressed, isNull);
    completion.complete(championshipDraft(RecipeImportSourceKind.text));
    await tester.pumpAndSettle();
    expect(cubit.state.phase, ChampionshipPhase.review);
  });

  testWidgets('image mode shows metadata without rendering source bytes', (
    tester,
  ) async {
    final picker = StubRecipeImagePicker(
      () async => SelectedRecipeImage(
        name: 'recipe.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
    );
    final cubit = buildChampionshipTestCubit(picker: picker);
    await _pumpApp(tester, cubit);

    await _tapVisible(tester, find.byKey(const ValueKey('source-mode-image')));
    await _tapVisible(tester, find.byKey(const ValueKey('source-pick-image')));

    expect(find.text('recipe.png'), findsOneWidget);
    expect(find.text('image/png · 8 B · 1200×800 px'), findsOneWidget);
    expect(find.textContaining('Reduced from'), findsNothing);
    expect(find.byType(Image), findsNothing);

    await _tapVisible(tester, find.byKey(const ValueKey('source-consent')));
    await _tapVisible(
      tester,
      find.byKey(const ValueKey('source-submit-image')),
    );
    expect(cubit.state.phase, ChampionshipPhase.review);
  });

  testWidgets('image mode shows the reduced size and marks the reduction', (
    tester,
  ) async {
    const mib = 1024 * 1024;
    final picker = StubRecipeImagePicker(
      () async => SelectedRecipeImage(
        name: 'IMG_0001.jpg',
        mimeType: 'image/jpeg',
        bytes: Uint8List(4 * mib)..[0] = 255,
      ),
    );
    final codec = FakeRecipeImageCodec(
      width: 3024,
      height: 4032,
      encodedBytesFor: (_) => mib,
    );
    final cubit = buildChampionshipTestCubit(picker: picker, codec: codec);
    await _pumpApp(tester, cubit);

    await _tapVisible(tester, find.byKey(const ValueKey('source-mode-image')));
    await _tapVisible(tester, find.byKey(const ValueKey('source-pick-image')));

    expect(find.text('IMG_0001.jpg'), findsOneWidget);
    expect(find.text('image/jpeg · 1048576 B · 1536×2048 px'), findsOneWidget);
    expect(find.text('Reduced from 4194304 B.'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('retryable failure preserves text and offers Retry and Sample', (
    tester,
  ) async {
    final client = RecordingRecipeImportClient(
      (_, _) async => throw const RecipeImportException(
        RecipeImportFailureCode.serviceBusy,
        'The extraction service is busy.',
      ),
    );
    final cubit = buildChampionshipTestCubit(client: client);
    await _pumpApp(tester, cubit);

    await tester.enterText(
      find.byKey(const ValueKey('source-text-input')),
      'Dough\nFlour 100 g',
    );
    await _tapVisible(tester, find.byKey(const ValueKey('source-consent')));
    await _tapVisible(tester, find.byKey(const ValueKey('source-submit-text')));

    expect(find.text('Dough\nFlour 100 g'), findsOneWidget);
    expect(
      find.text('The extraction service is busy. Try again.'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('source-retry')), findsOneWidget);
    expect(find.byKey(const ValueKey('source-sample')), findsOneWidget);
  });

  testWidgets('source reflects external edits and shows validation failures', (
    tester,
  ) async {
    final cubit = buildChampionshipTestCubit(
      picker: StubRecipeImagePicker(
        () => throw const RecipeImagePickerException(
          RecipeImagePickerFailure.unsupportedMimeType,
        ),
      ),
    );
    await _pumpApp(tester, cubit);

    cubit.setSourceText('Externally restored source');
    await tester.pumpAndSettle();
    expect(cubit.state.sourceText, 'Externally restored source');
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('source-text-input')))
          .controller
          ?.text,
      'Externally restored source',
    );

    await _tapVisible(tester, find.byKey(const ValueKey('source-mode-image')));
    await _tapVisible(tester, find.byKey(const ValueKey('source-pick-image')));
    expect(
      find.text('Select one JPEG, PNG, or WebP image no larger than 32 MiB.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'keyboard traversal reaches every editable field and phase action',
    (tester) async {
      final cubit = buildChampionshipTestCubit()
        ..setSourceText('Keyboard source')
        ..setLiveConsent(value: true);
      await _pumpApp(tester, cubit, size: const Size(390, 844));

      for (final key in const [
        ValueKey('source-mode-selector'),
        ValueKey('source-text-input'),
        ValueKey('source-submit-text'),
        ValueKey('source-consent'),
        ValueKey('source-sample'),
      ]) {
        await _tabTo(tester, key);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(cubit.state.phase, ChampionshipPhase.review);

      final reviewActions = _enabledButtonKeys();
      for (final key in const [
        ValueKey('review-confirm-all'),
        ValueKey('recipe.name.input'),
        ValueKey('recipe.baseYield.amount.input'),
        ValueKey('recipe.baseYield.unit.input'),
        ValueKey('recipe.maxBatchYield.amount.input'),
        ValueKey('recipe.maxBatchYield.unit.input'),
        ValueKey('recipe.maxBatchYield.remove'),
        ValueKey('recipe.preparationNotes[0].input'),
        ValueKey('components[0].name.input'),
        ValueKey('components[0].amount.input'),
        ValueKey('components[0].unit.input'),
        ValueKey('components[0].behavior.input'),
        ValueKey('components[1].name.input'),
        ValueKey('components[1].amount.input'),
        ValueKey('components[1].unit.input'),
        ValueKey('components[1].behavior.input'),
        ValueKey('components[2].name.input'),
        ValueKey('components[2].amount.input'),
        ValueKey('components[2].unit.input'),
        ValueKey('components[2].behavior.input'),
        ValueKey('components[3].name.input'),
        ValueKey('components[3].behavior.input'),
        ValueKey('components[3].note.input'),
        ValueKey('review-continue'),
        ValueKey('review-back'),
      ]) {
        await _tabTo(tester, key);
      }
      for (final key in reviewActions) {
        await _tabTo(tester, key);
      }

      cubit
        ..confirmAllUnambiguous()
        ..updateReview(
          (draft) => draft.editComponentUnit(2, 'g').confirmComponentUnit(2),
        )
        ..updateReview((draft) => draft.confirmComponentBehavior(3))
        ..continueToTarget()
        ..setTargetAmount('25');
      await tester.pumpAndSettle();

      final targetActions = _enabledButtonKeys();
      for (final key in const [
        ValueKey('target-amount-input'),
        ValueKey('target-unit-input'),
        ValueKey('target-calculate'),
        ValueKey('target-back'),
      ]) {
        await _tabTo(tester, key);
      }
      for (final key in targetActions) {
        await _tabTo(tester, key);
      }

      cubit.calculate();
      await tester.pumpAndSettle();
      final resultActions = _enabledButtonKeys();
      for (final key in const [
        ValueKey('result-back'),
        ValueKey('result-reset'),
      ]) {
        await _tabTo(tester, key);
      }
      for (final key in resultActions) {
        await _tabTo(tester, key);
      }
    },
  );

  testWidgets('every editable review value uses its stable path action', (
    tester,
  ) async {
    final cubit = buildChampionshipTestCubit();
    await cubit.loadSample();
    await _pumpApp(tester, cubit, size: const Size(1200, 1000));

    for (final entry in <String, String>{
      'recipe.name': 'Updated croissant',
      'recipe.baseYield.amount': '24',
      'recipe.maxBatchYield.amount': '12',
      'recipe.preparationNotes[0]': 'Rest between folds.',
      'components[0].name': 'Flour',
      'components[0].amount': '1000',
      'components[1].name': 'Butter',
      'components[1].amount': '500',
      'components[2].name': 'Water',
      'components[2].amount': '480',
      'components[3].name': 'Dusting flour',
      'components[3].note': 'As needed.',
    }.entries) {
      await _editAndConfirmText(tester, entry.key, entry.value);
    }
    for (final entry in <String, String>{
      'recipe.baseYield.unit': 'piece',
      'recipe.maxBatchYield.unit': 'piece',
      'components[0].unit': 'g',
      'components[1].unit': 'g',
      'components[2].unit': 'g',
    }.entries) {
      await _editAndConfirmUnit(tester, entry.key, entry.value);
    }
    for (final entry in <String, DraftScalingBehavior>{
      'components[0].behavior': DraftScalingBehavior.proportional,
      'components[1].behavior': DraftScalingBehavior.proportional,
      'components[2].behavior': DraftScalingBehavior.proportional,
      'components[3].behavior': DraftScalingBehavior.manual,
    }.entries) {
      await _editAndConfirmBehavior(tester, entry.key, entry.value);
    }
    for (final entry in <String, String>{
      'components[0].amount': '1000',
      'components[1].amount': '500',
      'components[2].amount': '480',
    }.entries) {
      await _editAndConfirmText(tester, entry.key, entry.value);
    }
    for (final entry in <String, String>{
      'components[0].unit': 'g',
      'components[1].unit': 'g',
      'components[2].unit': 'g',
    }.entries) {
      await _editAndConfirmUnit(tester, entry.key, entry.value);
    }

    cubit.continueToTarget();
    expect(cubit.state.reviewIssues, isEmpty);
    expect(cubit.state.phase, ChampionshipPhase.target);
    cubit.back();
    await _tapVisible(tester, find.byKey(const ValueKey('review-back')));
    expect(cubit.state.phase, ChampionshipPhase.source);
  });

  testWidgets('a base yield counted in 개 keeps that word through the target', (
    tester,
  ) async {
    final cubit = buildChampionshipTestCubit();
    await cubit.loadSample();
    await _pumpApp(tester, cubit, size: const Size(1200, 1000));

    expect(
      _dropdownValues(tester, 'recipe.baseYield.unit.input'),
      containsAll(['piece', 'ea', '개']),
    );

    await _editAndConfirmUnit(tester, 'recipe.baseYield.unit', '개');
    await _editAndConfirmUnit(tester, 'recipe.maxBatchYield.unit', '개');
    await _editAndConfirmUnit(tester, 'components[2].unit', 'g');
    await _tapVisible(tester, find.byKey(const ValueKey('review-confirm-all')));
    await _editAndConfirmBehavior(
      tester,
      'components[3].behavior',
      DraftScalingBehavior.manual,
    );
    cubit.continueToTarget();
    await tester.pumpAndSettle();

    expect(cubit.state.reviewIssues, isEmpty);
    expect(cubit.state.phase, ChampionshipPhase.target);
    expect(cubit.state.targetUnit, '개');
    expect(_dropdownValues(tester, 'target-unit-input'), ['개']);
  });

  testWidgets('bulk confirmation is also offered where the review ends', (
    tester,
  ) async {
    final cubit = buildChampionshipTestCubit();
    await cubit.loadSample();
    await _pumpApp(tester, cubit, size: const Size(900, 600));

    final top = find.byKey(const ValueKey('review-confirm-all'));
    final bottom = find.byKey(const ValueKey('review-confirm-all-bottom'));
    final continueButton = find.byKey(const ValueKey('review-continue'));
    expect(top, findsOneWidget);
    expect(cubit.state.review!.recipe.name.isConfirmed, isFalse);

    await _tapVisible(tester, bottom);

    expect(cubit.state.review!.recipe.name.isConfirmed, isTrue);
    expect(cubit.state.review!.components[2].unit.isConfirmed, isFalse);
    expect(
      tester.getTopLeft(bottom).dy,
      lessThan(tester.getTopLeft(continueButton).dy),
    );
  });

  testWidgets('review confirms an explicitly absent maximum batch', (
    tester,
  ) async {
    final source = championshipDraft(RecipeImportSourceKind.text).toJson();
    final recipe = Map<String, Object?>.from(
      source['recipe']! as Map<String, Object?>,
    )..['maxBatchYield'] = null;
    final withoutMaximum = ExtractedRecipeDraft.fromJson({
      ...source,
      'recipe': recipe,
    });
    final client = RecordingRecipeImportClient((_, _) async => withoutMaximum);
    final cubit = buildChampionshipTestCubit(client: client)
      ..setSourceText('No maximum batch')
      ..setLiveConsent(value: true);
    await cubit.submitText(locale: 'en');
    await _pumpApp(tester, cubit);

    await _tapVisible(
      tester,
      find.byKey(const ValueKey('recipe.maxBatchYield.absent.confirm')),
    );

    expect(cubit.state.review?.recipe.isMaxBatchYieldAbsentConfirmed, isTrue);
  });

  testWidgets(
    'review can remove a proposed maximum batch and confirm absence',
    (tester) async {
      final cubit = buildChampionshipTestCubit();
      await cubit.loadSample();
      await _pumpApp(tester, cubit);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('recipe.maxBatchYield.remove')),
      );

      expect(cubit.state.review?.recipe.maxBatchYield, isNull);
      expect(
        cubit.state.review?.recipe.isMaxBatchYieldAbsentConfirmed,
        isFalse,
      );
      expect(find.text('Confirm no maximum batch'), findsOneWidget);

      await _tapVisible(
        tester,
        find.byKey(const ValueKey('recipe.maxBatchYield.absent.confirm')),
      );

      expect(cubit.state.review?.recipe.isMaxBatchYieldAbsentConfirmed, isTrue);
    },
  );

  testWidgets('changing a numeric component to manual clears hidden quantity', (
    tester,
  ) async {
    final cubit = buildChampionshipTestCubit();
    await cubit.loadSample();
    await _pumpApp(tester, cubit);

    await _editAndConfirmBehavior(
      tester,
      'components[0].behavior',
      DraftScalingBehavior.manual,
    );

    final component = cubit.state.review!.components[0];
    expect(component.amount.value, isNull);
    expect(component.unit.value, isNull);
    expect(
      find.byKey(const ValueKey('components[0].amount.input')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('components[0].unit.input')),
      findsNothing,
    );
  });

  testWidgets('target renders invalid and batch-limit outcomes', (
    tester,
  ) async {
    final cubit = buildChampionshipTestCubit();
    await cubit.loadSample();
    cubit
      ..confirmAllUnambiguous()
      ..updateReview(
        (draft) => draft.editComponentUnit(2, 'g').confirmComponentUnit(2),
      )
      ..updateReview((draft) => draft.confirmComponentBehavior(3))
      ..continueToTarget()
      ..setTargetUnit('g');
    await _pumpApp(tester, cubit);

    final unitField = tester.widget<DropdownButtonFormField<String>>(
      find.byKey(const ValueKey('target-unit-input')),
    );
    unitField.onChanged?.call('piece');
    await tester.pump();
    cubit
      ..setTargetAmount('0')
      ..calculate();
    await tester.pump();
    expect(
      find.text('Enter a valid target above zero with a compatible unit.'),
      findsOneWidget,
    );

    cubit
      ..setTargetAmount('12012')
      ..calculate();
    await tester.pump();
    expect(
      find.text('The plan exceeds the 1,000-batch limit.'),
      findsOneWidget,
    );
    await _tapVisible(tester, find.byKey(const ValueKey('target-back')));
    expect(cubit.state.phase, ChampionshipPhase.review);
  });

  testWidgets(
    'result shows the no-warning state and preserves Back and Reset',
    (tester) async {
      final cubit = buildChampionshipTestCubit();
      await cubit.loadSample();
      cubit
        ..confirmAllUnambiguous()
        ..updateReview(
          (draft) => draft.editComponentUnit(2, 'g').confirmComponentUnit(2),
        )
        ..updateReview(
          (draft) => draft
              .editComponentBehavior(3, DraftScalingBehavior.proportional)
              .confirmComponentBehavior(3)
              .editComponentAmount(3, '10')
              .confirmComponentAmount(3)
              .editComponentUnit(3, 'g')
              .confirmComponentUnit(3),
        )
        ..continueToTarget()
        ..setTargetAmount('25')
        ..calculate();
      await _pumpApp(tester, cubit);

      expect(find.text('No calculation warnings.'), findsOneWidget);
      expect(find.text('3 batches'), findsOneWidget);
      expect(find.text('2 full batches · 12 piece each'), findsOneWidget);
      expect(find.text('Remainder batch · 1 piece'), findsOneWidget);
      await _tapVisible(tester, find.byKey(const ValueKey('result-back')));
      expect(cubit.state.phase, ChampionshipPhase.target);
      cubit.calculate();
      await tester.pumpAndSettle();
      await _tapVisible(tester, find.byKey(const ValueKey('result-reset')));
      expect(cubit.state.phase, ChampionshipPhase.source);
    },
  );

  testWidgets(
    'production sheet receives the identical run and failures recover',
    (tester) async {
      final cubit = buildChampionshipTestCubit();
      await cubit.loadSample();
      cubit
        ..confirmAllUnambiguous()
        ..updateReview(
          (draft) => draft.editComponentUnit(2, 'g').confirmComponentUnit(2),
        )
        ..updateReview((draft) => draft.confirmComponentBehavior(3))
        ..continueToTarget()
        ..setTargetAmount('180')
        ..calculate();
      final run = cubit.state.run!;
      final openedRuns = <ProductionRun>[];
      var shouldFail = true;

      tester.view
        ..physicalSize = const Size(900, 1000)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      addTearDown(cubit.close);
      await tester.pumpWidget(
        ChampionshipApp(
          cubit: cubit,
          locale: const Locale('en'),
          openProductionSheet: (_, openedRun) async {
            openedRuns.add(openedRun);
            if (shouldFail) {
              shouldFail = false;
              throw StateError('platform failure');
            }
          },
        ),
      );
      await tester.pumpAndSettle();

      final action = find.byKey(const ValueKey('result-production-sheet'));
      await _tapVisible(tester, action);

      expect(openedRuns, [same(run)]);
      expect(cubit.state.phase, ChampionshipPhase.result);
      expect(cubit.state.run, same(run));
      expect(
        find.text('The production sheet could not be opened.'),
        findsOneWidget,
      );

      await _tapVisible(tester, action);
      expect(openedRuns, [same(run), same(run)]);
      expect(cubit.state.phase, ChampionshipPhase.result);
      expect(cubit.state.run, same(run));
    },
  );
}

Future<void> _editAndConfirmText(
  WidgetTester tester,
  String path,
  String value,
) async {
  final input = tester.widget<TextFormField>(
    find.byKey(ValueKey('$path.input')),
  );
  input.onChanged?.call(value);
  await tester.pump();
  tester
      .widget<OutlinedButton>(find.byKey(ValueKey('$path.confirm')))
      .onPressed
      ?.call();
  await tester.pump();
}

List<String?> _dropdownValues(WidgetTester tester, String key) => tester
    .widget<DropdownButton<String>>(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(DropdownButton<String>),
      ),
    )
    .items!
    .map((item) => item.value)
    .toList();

Future<void> _editAndConfirmUnit(
  WidgetTester tester,
  String path,
  String value,
) async {
  tester
      .widget<DropdownButtonFormField<String>>(
        find.byKey(ValueKey('$path.input')),
      )
      .onChanged
      ?.call(value);
  await tester.pump();
  tester
      .widget<OutlinedButton>(find.byKey(ValueKey('$path.confirm')))
      .onPressed
      ?.call();
  await tester.pump();
}

Future<void> _editAndConfirmBehavior(
  WidgetTester tester,
  String path,
  DraftScalingBehavior value,
) async {
  tester
      .widget<DropdownButtonFormField<DraftScalingBehavior>>(
        find.byKey(ValueKey('$path.input')),
      )
      .onChanged
      ?.call(value);
  await tester.pump();
  tester
      .widget<OutlinedButton>(find.byKey(ValueKey('$path.confirm')))
      .onPressed
      ?.call();
  await tester.pump();
}
