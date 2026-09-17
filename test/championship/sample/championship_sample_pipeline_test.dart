import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';
import 'package:prep_book/domain/domain.dart';

const _fixturePath = 'assets/championship/sample_croissant_draft.json';

final class _FileAssetBundle extends CachingAssetBundle {
  final requestedKeys = <String>[];

  @override
  Future<ByteData> load(String key) async {
    requestedKeys.add(key);
    final bytes = Uint8List.fromList(await File(key).readAsBytes());
    return ByteData.sublistView(bytes);
  }
}

void main() {
  test(
    'loads the one fixture and completes the deterministic sample path',
    () async {
      final bundle = _FileAssetBundle();
      final extracted = await ChampionshipSampleLoader(bundle: bundle).load();

      final review = ReviewRecipeDraft.fromExtracted(
        extracted,
      ).confirmAllUnambiguous().editComponentUnit(2, 'g').confirmComponentUnit(2).confirmComponentBehavior(3);
      final verification = const RecipeDraftVerifier().verify(review);
      final verified = (verification as RecipeDraftVerified).draft;
      final run = const ChampionshipRunBuilder().build(
        draft: verified,
        targetAmount: '180',
        targetUnit: 'piece',
        createdAt: DateTime.utc(2026, 9, 13),
        runId: 'sample-run',
      );

      expect(bundle.requestedKeys, [_fixturePath]);
      expect(
        extracted.toJson(),
        jsonDecode(File(_fixturePath).readAsStringSync()),
      );
      expect(run.result.batchPlan.batchCount, 15);
      expect(
        run.result.components[0].total!.exact,
        Quantity.parse('7500', Unit.gram),
      );
      expect(run.result.components[3].total, isNull);
    },
  );
}
