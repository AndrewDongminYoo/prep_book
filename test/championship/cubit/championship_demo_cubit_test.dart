import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/cubit/championship_demo_state.dart';
import 'package:prep_book/championship/input/recipe_image_picker.dart';
import 'package:prep_book/championship/input/recipe_image_reducer.dart';
import 'package:prep_book/championship/input/recipe_import_client.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/championship/sample/championship_sample_loader.dart';
import 'package:prep_book/domain/domain.dart';

import '../championship_test_harness.dart';

const _fixturePath = 'assets/championship/sample_croissant_draft.json';

final class _FileAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = Uint8List.fromList(await File(key).readAsBytes());
    return ByteData.sublistView(bytes);
  }
}

final class _FailingAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) => Future.error(StateError(key));
}

final class _FakeImportClient implements RecipeImportClient {
  new(this.extractCall);

  final Future<ExtractedRecipeDraft> Function(
    RecipeImportRequest request,
    String locale,
  )
  extractCall;
  final requests = <RecipeImportRequest>[];
  final locales = <String>[];

  @override
  Future<ExtractedRecipeDraft> extract(
    RecipeImportRequest request, {
    required String locale,
  }) {
    requests.add(request);
    locales.add(locale);
    return extractCall(request, locale);
  }
}

final class _FakeImagePicker implements RecipeImagePicker {
  new(this.pickCall);

  final Future<SelectedRecipeImage?> Function() pickCall;

  @override
  Future<SelectedRecipeImage?> pick() => pickCall();
}

ExtractedRecipeDraft _draft(RecipeImportSourceKind sourceKind) {
  final json = jsonDecode(File(_fixturePath).readAsStringSync());
  return ExtractedRecipeDraft.fromJson({
    ...(json as Map<String, Object?>),
    'sourceKind': sourceKind.name,
  });
}

ChampionshipDemoCubit _cubit({
  _FakeImportClient? client,
  _FakeImagePicker? picker,
  FakeRecipeImageCodec? codec,
  ChampionshipSampleLoader? sampleLoader,
  ChampionshipRunId? createRunId = _fixedRunId,
}) => ChampionshipDemoCubit(
  importClient: client ?? _FakeImportClient((_, _) async => _draft(RecipeImportSourceKind.text)),
  imagePicker: picker ?? _FakeImagePicker(() async => null),
  imageReducer: RecipeImageReducer(codec: codec ?? FakeRecipeImageCodec()),
  sampleLoader: sampleLoader ?? ChampionshipSampleLoader(bundle: _FileAssetBundle()),
  now: () => DateTime.utc(2026, 9, 14, 1, 2, 3),
  createRunId: createRunId,
);

String _fixedRunId() => 'championship-run-1';

void _completeSampleReview(ChampionshipDemoCubit cubit) {
  cubit
    ..confirmAllUnambiguous()
    ..updateReview(
      (draft) => draft.editComponentUnit(2, 'g').confirmComponentUnit(2),
    )
    ..updateReview((draft) => draft.confirmComponentBehavior(3));
}

void main() {
  test(
    'loads the checked-in sample without calling the import client',
    () async {
      final client = _FakeImportClient((_, _) => throw StateError('network'));
      final cubit = _cubit(client: client);
      addTearDown(cubit.close);

      await cubit.loadSample();

      expect(client.requests, isEmpty);
      expect(cubit.state.phase, ChampionshipPhase.review);
      expect(cubit.state.review?.sourceKind, RecipeImportSourceKind.sample);
      expect(cubit.state.isLoading, isFalse);
    },
  );

  test('imports text and preserves it through a retryable failure', () async {
    var attempt = 0;
    final client = _FakeImportClient((request, locale) async {
      attempt += 1;
      if (attempt == 1) {
        throw const RecipeImportException(
          RecipeImportFailureCode.serviceBusy,
          'Busy.',
        );
      }
      return _draft(RecipeImportSourceKind.text);
    });
    final cubit = _cubit(client: client);
    addTearDown(cubit.close);
    cubit
      ..setSourceText('Dough\nFlour 100 g')
      ..setLiveConsent(value: true);

    await cubit.submitText(locale: 'en');

    expect(cubit.state.phase, ChampionshipPhase.source);
    expect(cubit.state.sourceText, 'Dough\nFlour 100 g');
    expect(cubit.state.importFailure, RecipeImportFailureCode.serviceBusy);

    await cubit.retryImport();

    expect(client.requests, hasLength(2));
    expect(client.locales, ['en', 'en']);
    expect(cubit.state.phase, ChampionshipPhase.review);
  });

  test('handles image cancellation and imports one selected image', () async {
    var selection = 0;
    final picker = _FakeImagePicker(() async {
      selection += 1;
      if (selection == 1) return null;
      return SelectedRecipeImage(
        name: 'recipe.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      );
    });
    final client = _FakeImportClient(
      (_, _) async => _draft(RecipeImportSourceKind.image),
    );
    final cubit = _cubit(client: client, picker: picker);
    addTearDown(cubit.close);

    await cubit.pickImage();
    expect(cubit.state.preparedImage, isNull);

    await cubit.pickImage();
    expect(cubit.state.preparedImage?.image.name, 'recipe.png');
    expect(cubit.state.preparedImage?.wasReduced, isFalse);
    cubit.setLiveConsent(value: true);
    await cubit.submitImage(locale: 'ko');

    expect(client.requests.single, isA<ImageRecipeImportRequest>());
    expect(cubit.state.phase, ChampionshipPhase.review);
  });

  test('reduces a large picked image before it is shown or sent', () async {
    const mib = 1024 * 1024;
    final picker = _FakeImagePicker(
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
    final client = _FakeImportClient(
      (_, _) async => _draft(RecipeImportSourceKind.image),
    );
    final cubit = _cubit(client: client, picker: picker, codec: codec);
    addTearDown(cubit.close);

    await cubit.pickImage();
    final prepared = cubit.state.preparedImage!;
    cubit.setLiveConsent(value: true);
    await cubit.submitImage(locale: 'en');

    expect(prepared.wasReduced, isTrue);
    expect(prepared.width, 1536);
    expect(prepared.height, 2048);
    expect(prepared.originalByteCount, 4 * mib);
    expect(prepared.image.bytes.length, mib);
    expect(prepared.image.mimeType, 'image/jpeg');
    expect(prepared.image.name, 'IMG_0001.jpg');
    final dataUrl = client.requests.single.toJson('en')['imageDataUrl']! as String;
    expect(dataUrl, startsWith('data:image/jpeg;base64,'));
    expect(
      dataUrl.length - 'data:image/jpeg;base64,'.length,
      4 * (mib / 3).ceil(),
      reason: 'the reduced bytes are what is sent',
    );
  });

  test(
    'reports a reduction that cannot fit as an image selection failure',
    () async {
      final picker = _FakeImagePicker(
        () async => SelectedRecipeImage(
          name: 'huge.png',
          mimeType: 'image/png',
          bytes: Uint8List(9 * 1024 * 1024)..[0] = 137,
        ),
      );
      final codec = FakeRecipeImageCodec(
        width: 6000,
        height: 6000,
        encodedBytesFor: (_) => recipeImportMaxImageBytes + 1,
      );
      final cubit = _cubit(picker: picker, codec: codec);
      addTearDown(cubit.close);

      await cubit.pickImage();

      expect(cubit.state.preparedImage, isNull);
      expect(
        cubit.state.sourceFailure,
        ChampionshipSourceFailure.imageSelection,
      );
      expect(codec.encodeCalls, hasLength(3));
    },
  );

  test('ignores a reduction that completes after Reset', () async {
    final gate = Completer<void>();
    final picker = _FakeImagePicker(
      () async => SelectedRecipeImage(
        name: 'recipe.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10]),
      ),
    );
    final cubit = _cubit(
      picker: picker,
      codec: FakeRecipeImageCodec(decodeGate: gate.future),
    );
    addTearDown(cubit.close);

    final pending = cubit.pickImage();
    await Future<void>.delayed(Duration.zero);
    cubit.reset();
    gate.complete();
    await pending;

    expect(cubit.state.preparedImage, isNull);
    expect(cubit.state.sourceFailure, isNull);
    expect(cubit.state.sourceMode, ChampionshipSourceMode.text);
  });

  test('ignores a response that completes after Reset', () async {
    final completion = Completer<ExtractedRecipeDraft>();
    final cubit = _cubit(
      client: _FakeImportClient((_, _) => completion.future),
    );
    addTearDown(cubit.close);
    cubit
      ..setSourceText('Old source')
      ..setLiveConsent(value: true);

    final pending = cubit.submitText(locale: 'en');
    cubit.reset();
    completion.complete(_draft(RecipeImportSourceKind.text));
    await pending;

    expect(cubit.state.phase, ChampionshipPhase.source);
    expect(cubit.state.sourceText, isEmpty);
    expect(cubit.state.review, isNull);
  });

  test('ignores an older response after a newer submission', () async {
    final oldCompletion = Completer<ExtractedRecipeDraft>();
    final newCompletion = Completer<ExtractedRecipeDraft>();
    var call = 0;
    final cubit = _cubit(
      client: _FakeImportClient((_, _) {
        call += 1;
        return call == 1 ? oldCompletion.future : newCompletion.future;
      }),
    );
    addTearDown(cubit.close);
    cubit
      ..setLiveConsent(value: true)
      ..setSourceText('Old source');
    final oldRequest = cubit.submitText(locale: 'en');
    cubit.setSourceText('New source');
    final newRequest = cubit.submitText(locale: 'en');

    newCompletion.complete(_draft(RecipeImportSourceKind.text));
    await newRequest;
    final acceptedReview = cubit.state.review;
    oldCompletion.complete(_draft(RecipeImportSourceKind.text));
    await oldRequest;

    expect(cubit.state.review, same(acceptedReview));
    expect(cubit.state.sourceText, 'New source');
  });

  test(
    'editing clears confirmation and unresolved review stays blocked',
    () async {
      final cubit = _cubit();
      addTearDown(cubit.close);
      await cubit.loadSample();
      cubit.confirmAllUnambiguous();
      expect(cubit.state.review?.recipe.name.isConfirmed, isTrue);

      cubit.updateReview((draft) => draft.editRecipeName('New dough'));
      expect(cubit.state.review?.recipe.name.isConfirmed, isFalse);

      cubit.continueToTarget();
      expect(cubit.state.phase, ChampionshipPhase.review);
      expect(cubit.state.reviewIssues, isNotEmpty);
    },
  );

  test(
    'corrected review reaches Target and Back preserves review identity',
    () async {
      final cubit = _cubit();
      addTearDown(cubit.close);
      await cubit.loadSample();
      _completeSampleReview(cubit);
      final completedReview = cubit.state.review;

      cubit.continueToTarget();

      expect(cubit.state.phase, ChampionshipPhase.target);
      expect(cubit.state.targetAmount, isEmpty);
      expect(cubit.state.targetUnit, 'piece');
      cubit.back();
      expect(cubit.state.phase, ChampionshipPhase.review);
      expect(cubit.state.review, same(completedReview));
    },
  );

  test(
    'calculates the exact run once and Result Back preserves target',
    () async {
      var runIds = 0;
      final cubit = ChampionshipDemoCubit(
        importClient: _FakeImportClient(
          (_, _) async => _draft(RecipeImportSourceKind.text),
        ),
        imagePicker: _FakeImagePicker(() async => null),
        imageReducer: RecipeImageReducer(codec: FakeRecipeImageCodec()),
        sampleLoader: ChampionshipSampleLoader(bundle: _FileAssetBundle()),
        now: () => DateTime.utc(2026, 9, 14, 1, 2, 3),
        createRunId: () => 'run-${++runIds}',
      );
      addTearDown(cubit.close);
      await cubit.loadSample();
      _completeSampleReview(cubit);
      cubit
        ..continueToTarget()
        ..setTargetAmount('180')
        ..calculate();
      final run = cubit.state.run!;

      cubit.calculate();

      expect(runIds, 1);
      expect(cubit.state.run, same(run));
      expect(run.result.batchPlan.batchCount, 15);
      expect(
        run.result.components[0].total!.exact,
        Quantity.parse('7500', Unit.gram),
      );
      expect(
        run.result.components[1].total!.exact,
        Quantity.parse('3750', Unit.gram),
      );
      expect(
        run.result.components[2].total!.exact,
        Quantity.parse('3600', Unit.gram),
      );
      expect(run.result.components[3].total, isNull);

      cubit.back();
      expect(cubit.state.phase, ChampionshipPhase.target);
      expect(cubit.state.targetAmount, '180');
      expect(cubit.state.run, same(run));
    },
  );

  test(
    'the target unit starts as the picker symbol of the base yield',
    () async {
      final cubit = _cubit();
      addTearDown(cubit.close);
      await cubit.loadSample();
      _completeSampleReview(cubit);
      cubit.updateReview(
        (draft) => draft
            .editBaseYieldUnit('pieces')
            .confirmBaseYieldUnit()
            .editMaxBatchYieldUnit('pieces')
            .confirmMaxBatchYieldUnit(),
      );

      cubit.continueToTarget();

      expect(cubit.state.phase, ChampionshipPhase.target);
      expect(cubit.state.verified?.recipe.baseYield.unit, 'pieces');
      expect(cubit.state.targetUnit, 'piece');
    },
  );

  test('a failed replacement clears the previously prepared image', () async {
    var call = 0;
    final picker = _FakeImagePicker(() async {
      call += 1;
      if (call == 1) {
        return SelectedRecipeImage(
          name: 'first.png',
          mimeType: 'image/png',
          bytes: Uint8List.fromList([137, 80, 78, 71]),
        );
      }
      throw const RecipeImagePickerException(
        RecipeImagePickerFailure.unsupportedMimeType,
      );
    });
    final cubit = _cubit(picker: picker);
    addTearDown(cubit.close);

    await cubit.pickImage();
    expect(cubit.state.preparedImage?.image.name, 'first.png');

    await cubit.pickImage();

    expect(cubit.state.preparedImage, isNull);
    expect(cubit.state.sourceFailure, ChampionshipSourceFailure.imageSelection);
  });

  test('a retry after consent was withdrawn sends nothing', () async {
    var calls = 0;
    final client = _FakeImportClient((_, _) async {
      calls += 1;
      throw const RecipeImportException(
        RecipeImportFailureCode.serviceBusy,
        'busy',
      );
    });
    final cubit = _cubit(client: client)
      ..setSourceText('Flour 100 g')
      ..setLiveConsent(value: true);
    addTearDown(cubit.close);
    await cubit.submitText(locale: 'en');
    expect(calls, 1);
    expect(cubit.state.importFailure, RecipeImportFailureCode.serviceBusy);

    cubit.setLiveConsent(value: false);
    await cubit.retryImport();

    expect(calls, 1);
    expect(
      cubit.state.sourceFailure,
      ChampionshipSourceFailure.liveConsentRequired,
    );
  });

  test('invalid target stays in Target with the verified draft', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);
    await cubit.loadSample();
    _completeSampleReview(cubit);
    cubit
      ..continueToTarget()
      ..setTargetAmount('0')
      ..calculate();

    expect(cubit.state.phase, ChampionshipPhase.target);
    expect(cubit.state.verified, isNotNull);
    expect(cubit.state.targetAmount, '0');
    expect(cubit.state.targetFailure, ChampionshipTargetFailure.invalidTarget);
    expect(cubit.state.run, isNull);
  });

  test('reports sample and image selection failures safely', () async {
    final sampleCubit = _cubit(
      sampleLoader: ChampionshipSampleLoader(bundle: _FailingAssetBundle()),
    );
    final imageCubit = _cubit(
      picker: _FakeImagePicker(
        () => throw const RecipeImagePickerException(
          RecipeImagePickerFailure.unsupportedMimeType,
        ),
      ),
    );
    addTearDown(sampleCubit.close);
    addTearDown(imageCubit.close);

    await sampleCubit.loadSample();
    await imageCubit.pickImage();

    expect(
      sampleCubit.state.sourceFailure,
      ChampionshipSourceFailure.sampleUnavailable,
    );
    expect(
      imageCubit.state.sourceFailure,
      ChampionshipSourceFailure.imageSelection,
    );
  });

  test('ignores stale sample and picker failures after Reset', () async {
    final sampleCompletion = Completer<ByteData>();
    final pickerCompletion = Completer<SelectedRecipeImage?>();
    final sampleBundle = _CompletingAssetBundle(sampleCompletion.future);
    final sampleCubit = _cubit(
      sampleLoader: ChampionshipSampleLoader(bundle: sampleBundle),
    );
    final pickerCubit = _cubit(
      picker: _FakeImagePicker(() => pickerCompletion.future),
    );
    addTearDown(sampleCubit.close);
    addTearDown(pickerCubit.close);

    final sampleRequest = sampleCubit.loadSample();
    final pickerRequest = pickerCubit.pickImage();
    sampleCubit.reset();
    pickerCubit.reset();
    sampleCompletion.completeError(StateError('sample'));
    pickerCompletion.completeError(
      const RecipeImagePickerException(
        RecipeImagePickerFailure.unsupportedMimeType,
      ),
    );
    await sampleRequest;
    await pickerRequest;

    expect(sampleCubit.state.sourceFailure, isNull);
    expect(pickerCubit.state.sourceFailure, isNull);
  });

  test('validates consent and live sources before import', () async {
    final client = _FakeImportClient(
      (_, _) async => _draft(RecipeImportSourceKind.text),
    );
    final cubit = _cubit(client: client);
    addTearDown(cubit.close);

    await cubit.submitText(locale: 'en');
    expect(
      cubit.state.sourceFailure,
      ChampionshipSourceFailure.liveConsentRequired,
    );

    cubit.setLiveConsent(value: true);
    await cubit.submitText(locale: 'en');
    expect(cubit.state.sourceFailure, ChampionshipSourceFailure.invalidSource);

    cubit.setSourceText(
      List.filled(recipeImportMaxTextScalars + 1, 'x').join(),
    );
    await cubit.submitText(locale: 'en');
    expect(cubit.state.sourceFailure, ChampionshipSourceFailure.invalidSource);

    await cubit.submitImage(locale: 'en');
    expect(cubit.state.sourceFailure, ChampionshipSourceFailure.invalidSource);
    expect(client.requests, isEmpty);
  });

  test('maps unexpected and stale import errors safely', () async {
    final first = Completer<ExtractedRecipeDraft>();
    var call = 0;
    final cubit = _cubit(
      client: _FakeImportClient((_, _) {
        call += 1;
        if (call == 1) return first.future;
        throw StateError('provider');
      }),
    );
    addTearDown(cubit.close);
    cubit
      ..setLiveConsent(value: true)
      ..setSourceText('First');
    final stale = cubit.submitText(locale: 'en');
    cubit.setSourceText('Second');

    await cubit.submitText(locale: 'en');
    expect(cubit.state.importFailure, RecipeImportFailureCode.serviceFailure);
    expect(cubit.state.importFailureMessage, 'The extraction request failed.');

    first.completeError(StateError('late'));
    await stale;
    expect(cubit.state.importFailure, RecipeImportFailureCode.serviceFailure);
  });

  test('no-op commands stay inert before their required phase', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);
    final initial = cubit.state;

    await cubit.retryImport();
    cubit
      ..updateReview((draft) => draft)
      ..continueToTarget()
      ..calculate()
      ..back();

    expect(cubit.state, same(initial));
  });

  test('restores an existing run and reports the batch limit', () async {
    final cubit = _cubit();
    addTearDown(cubit.close);
    await cubit.loadSample();
    _completeSampleReview(cubit);
    cubit
      ..continueToTarget()
      ..setTargetUnit('piece')
      ..setTargetAmount('180')
      ..calculate()
      ..back()
      ..calculate();
    expect(cubit.state.phase, ChampionshipPhase.result);

    cubit
      ..back()
      ..setTargetAmount('12012')
      ..calculate();
    expect(cubit.state.targetFailure, ChampionshipTargetFailure.batchLimit);
  });

  test('the default run id is generated for a successful run', () async {
    final cubit = _cubit(createRunId: null);
    addTearDown(cubit.close);
    await cubit.loadSample();
    _completeSampleReview(cubit);
    cubit
      ..continueToTarget()
      ..setTargetAmount('180')
      ..calculate();

    expect(cubit.state.run?.id, startsWith('championship-'));
  });

  test('safe exception strings expose only their enum code', () {
    expect(
      const RecipeImagePickerException(
        RecipeImagePickerFailure.missingBytes,
      ).toString(),
      'RecipeImagePickerException(missingBytes)',
    );
    expect(
      const RecipeImportException(
        RecipeImportFailureCode.serviceBusy,
        'secret provider text',
      ).toString(),
      'RecipeImportException(service_busy)',
    );
  });
}

final class _CompletingAssetBundle extends CachingAssetBundle {
  new(this.result);

  final Future<ByteData> result;

  @override
  Future<ByteData> load(String key) => result;
}
