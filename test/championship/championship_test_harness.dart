import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/input/recipe_image_picker.dart';
import 'package:prep_book/championship/input/recipe_image_reducer.dart';
import 'package:prep_book/championship/input/recipe_import_client.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/championship/sample/championship_sample_loader.dart';
import 'package:prep_book/domain/domain.dart';

const championshipFixturePath = 'assets/championship/sample_croissant_draft.json';

Future<void> ignoreChampionshipProductionSheet(
  BuildContext context,
  ProductionRun run,
) async {}

final class FileChampionshipAssetBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    final bytes = Uint8List.fromList(File(key).readAsBytesSync());
    return SynchronousFuture(ByteData.sublistView(bytes));
  }
}

final class RecordingRecipeImportClient implements RecipeImportClient {
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

final class StubRecipeImagePicker implements RecipeImagePicker {
  new(this.pickCall);

  final Future<SelectedRecipeImage?> Function() pickCall;

  @override
  Future<SelectedRecipeImage?> pick() => pickCall();
}

typedef RecipeImageEncodeCall = ({int width, int height, double quality});

/// Scripts the pixel size of every decoded image and the byte count each
/// encode produces; the defaults describe a small image that needs no work.
final class FakeRecipeImageCodec implements RecipeImageCodec {
  new({
    this.width = 1200,
    this.height = 800,
    int Function(RecipeImageEncodeCall call)? encodedBytesFor,
    this.decodeError,
    this.decodeGate,
  }) : encodedBytesFor = encodedBytesFor ?? ((_) => 256 * 1024);

  final int width;
  final int height;
  final int Function(RecipeImageEncodeCall call) encodedBytesFor;
  final Error? decodeError;

  /// Awaited before every decode, so a test can hold a reduction open.
  final Future<void>? decodeGate;
  final decodeCalls = <(Uint8List, String)>[];
  final encodeCalls = <RecipeImageEncodeCall>[];
  int closeCount = 0;

  @override
  Future<DecodedRecipeImage> decode(Uint8List bytes, String mimeType) async {
    decodeCalls.add((bytes, mimeType));
    if (decodeGate case final gate?) await gate;
    if (decodeError case final error?) throw error;
    return _FakeDecodedRecipeImage(this);
  }
}

final class _FakeDecodedRecipeImage implements DecodedRecipeImage {
  new(this.codec);

  final FakeRecipeImageCodec codec;

  @override
  int get width => codec.width;

  @override
  int get height => codec.height;

  @override
  Future<Uint8List> encodeJpeg({
    required int width,
    required int height,
    required double quality,
  }) async {
    final call = (width: width, height: height, quality: quality);
    codec.encodeCalls.add(call);
    return Uint8List(codec.encodedBytesFor(call))..[0] = 0xFF;
  }

  @override
  void close() => codec.closeCount++;
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
  FakeRecipeImageCodec? codec,
}) => ChampionshipDemoCubit(
  importClient:
      client ??
      RecordingRecipeImportClient(
        (_, _) async => championshipDraft(RecipeImportSourceKind.text),
      ),
  imagePicker: picker ?? StubRecipeImagePicker(() async => null),
  imageReducer: RecipeImageReducer(codec: codec ?? FakeRecipeImageCodec()),
  sampleLoader: ChampionshipSampleLoader(bundle: FileChampionshipAssetBundle()),
  now: () => DateTime.utc(2026, 9, 14, 1, 2, 3),
  createRunId: () => 'championship-test-run',
);
