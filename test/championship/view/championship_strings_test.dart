import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/championship/championship.dart';
import 'package:prep_book/championship/view/championship_strings.dart';
import 'package:prep_book/l10n/l10n.dart';

Future<ChampionshipStrings> _stringsFor(
  WidgetTester tester,
  Locale locale,
) async {
  late ChampionshipStrings strings;
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) {
          strings = ChampionshipStrings.of(context);
          return const SizedBox();
        },
      ),
    ),
  );
  return strings;
}

List<String> _allCopy(ChampionshipStrings strings) => [
  strings.title,
  strings.boundary,
  strings.source,
  strings.review,
  strings.target,
  strings.result,
  strings.reset,
  strings.back,
  strings.sourceHeading,
  strings.sourceIntro,
  strings.textMode,
  strings.imageMode,
  strings.sampleTitle,
  strings.sampleDescription,
  strings.useSample,
  strings.recipeText,
  strings.recipeTextHint,
  strings.selectImage,
  strings.importText,
  strings.importImage,
  strings.liveConsent,
  strings.privacy,
  strings.loading,
  strings.retry,
  for (final failure in ChampionshipSourceFailure.values)
    strings.sourceFailure(failure),
  for (final failure in RecipeImportFailureCode.values)
    strings.importFailure(failure),
  strings.reviewHeading,
  strings.reviewIntro,
  strings.confirmAll,
  strings.aiProposal,
  strings.evidence,
  strings.currentValue,
  strings.issues,
  strings.confirm,
  strings.confirmed,
  strings.edited,
  strings.needsConfirmation,
  strings.notApplicable,
  strings.recipeDetails,
  strings.recipeName,
  strings.baseYieldAmount,
  strings.baseYieldUnit,
  strings.maxBatchAmount,
  strings.maxBatchUnit,
  strings.removeMaximumBatch,
  strings.confirmNoMaximumBatch,
  strings.preparationNote(0),
  strings.component(0),
  strings.componentName,
  strings.amount,
  strings.unit,
  strings.behavior,
  strings.note,
  strings.continueToTarget,
  for (final confidence in ExtractionConfidence.values)
    strings.confidence(confidence),
  for (final behavior in DraftScalingBehavior.values)
    strings.behaviorName(behavior),
  strings.targetHeading,
  strings.verifiedRecipe,
  strings.targetAmount,
  strings.targetUnit,
  strings.calculate,
  strings.invalidTarget,
  strings.batchLimit,
  strings.resultHeading,
  strings.exactCalculation,
  strings.exactBoundary,
  strings.batches(2),
  strings.fullBatches(2, '12 piece'),
  strings.remainderBatch('1 piece'),
  strings.batch(0),
  strings.manualAsNeeded,
  strings.warnings,
  strings.noWarnings,
];

void main() {
  for (final locale in const [Locale('en'), Locale('ko')]) {
    testWidgets('provides complete ${locale.languageCode} workflow copy', (
      tester,
    ) async {
      final strings = await _stringsFor(tester, locale);

      expect(_allCopy(strings), everyElement(isNotEmpty));
      expect(
        strings.privacy,
        contains(
          locale.languageCode == 'ko' ? '저장하지 않습니다' : 'does not persist',
        ),
      );
    });
  }
}
