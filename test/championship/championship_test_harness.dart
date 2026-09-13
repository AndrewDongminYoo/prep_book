import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/input/recipe_image_picker.dart';
import 'package:prep_book/championship/input/recipe_import_client.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/championship/sample/championship_sample_loader.dart';

const championshipFixturePath =
    'assets/championship/sample_croissant_draft.json';

final class FileChampionshipAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    final bytes = Uint8List.fromList(File(key).readAsBytesSync());
    return SynchronousFuture(ByteData.sublistView(bytes));
  }
}

final class RecordingRecipeImportClient implements RecipeImportClient {
  RecordingRecipeImportClient(this.extractCall);

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

final class StubRecipeImagePicker implements RecipeImagePicker {
  StubRecipeImagePicker(this.pickCall);

  final Future<SelectedRecipeImage?> Function() pickCall;

  @override
  Future<SelectedRecipeImage?> pick() => pickCall();
}

ExtractedRecipeDraft championshipDraft(RecipeImportSourceKind sourceKind) {
  final value = jsonDecode(File(championshipFixturePath).readAsStringSync());
  return ExtractedRecipeDraft.fromJson({
    ...(value as Map<String, Object?>),
    'sourceKind': sourceKind.name,
  });
}

ChampionshipDemoCubit buildChampionshipTestCubit({
  RecordingRecipeImportClient? client,
  StubRecipeImagePicker? picker,
}) => ChampionshipDemoCubit(
  importClient:
      client ??
      RecordingRecipeImportClient(
        (_, _) async => championshipDraft(RecipeImportSourceKind.text),
      ),
  imagePicker: picker ?? StubRecipeImagePicker(() async => null),
  sampleLoader: ChampionshipSampleLoader(bundle: FileChampionshipAssetBundle()),
  now: () => DateTime.utc(2026, 9, 14, 1, 2, 3),
  createRunId: () => 'championship-test-run',
);
