import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';

const _sampleAssetPath = 'assets/championship/sample_croissant_draft.json';

final class ChampionshipSampleLoader {
  const ChampionshipSampleLoader({required this.bundle});

  final AssetBundle bundle;

  Future<ExtractedRecipeDraft> load() async {
    final decoded = jsonDecode(await bundle.loadString(_sampleAssetPath));
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('The sample asset must contain an object.');
    }
    return ExtractedRecipeDraft.fromJson(decoded);
  }
}
