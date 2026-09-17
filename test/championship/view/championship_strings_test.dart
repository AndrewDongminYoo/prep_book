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
  strings.brandTitle,
  strings.brandSubtitle,
  strings.boundary,
  strings.source,
  strings.review,
  strings.target,
  strings.result,
  strings.reset,
  strings.back,
  for (final phase in ChampionshipPhase.values) strings.phaseName(phase),
  strings.currentStep(label: strings.review, index: 1),
  strings.phaseStep(label: strings.review, index: 1, current: true),
  strings.phaseStep(label: strings.review, index: 1, current: false),
  strings.sourceHeading,
  strings.sourceIntro,
  strings.textMode,
  strings.imageMode,
  strings.sampleDescription,
  strings.useSample,
  strings.recipeText,
  strings.recipeTextHint,
  strings.selectImage,
  strings.imageMetadata(
    mimeType: 'image/jpeg',
    byteCount: 1,
    width: 2,
    height: 3,
  ),
  strings.imageReduced(4),
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
  strings.currentValueFor(strings.recipeName),
  strings.issues,
  strings.confirm,
  strings.confirmField(strings.recipeName),
  strings.confirmedField(strings.recipeName),
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
  strings.removeComponent,
  strings.removeComponentAction(index: 0, name: 'Flour'),
  strings.removeComponentTitle('Flour'),
  strings.removeComponentMessage('Flour'),
  strings.cancel,
  strings.remove,
  strings.componentName,
  strings.amount,
  strings.unit,
  strings.behavior,
  strings.note,
  strings.componentNameFor(0),
  strings.componentAmountFor(0),
  strings.componentUnitFor(0),
  strings.componentBehaviorFor(0),
  strings.componentNoteFor(0),
  strings.continueToTarget,
  for (final confidence in ExtractionConfidence.values)
    strings.confidence(confidence),
  for (final behavior in DraftScalingBehavior.values)
    strings.behaviorName(behavior),
  for (final issue in ReviewIssue.values) strings.reviewIssue(issue),
  for (final issue in RecipeDraftVerificationIssueKind.values)
    strings.verificationIssue(
      RecipeDraftVerificationIssue(
        kind: issue,
        path: issue == RecipeDraftVerificationIssueKind.atLeastOneComponent
            ? null
            : 'components[0].name',
      ),
    ),
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
  strings.batchQuantity(first: 1, last: 15, amount: '500 g', manual: false),
  strings.batchQuantity(
    first: 1,
    last: 15,
    amount: strings.manualAsNeeded,
    manual: true,
  ),
  strings.manualAsNeeded,
  strings.warnings,
  strings.noWarnings,
];

void main() {
  testWidgets('translates every local review issue', (tester) async {
    final english = await _stringsFor(tester, const Locale('en'));
    final korean = await _stringsFor(tester, const Locale('ko'));

    for (final issue in ReviewIssue.values) {
      expect(english.reviewIssue(issue), issue.message, reason: '$issue');
      expect(korean.reviewIssue(issue), isNot(issue.message), reason: '$issue');
    }
  });

  testWidgets('distinguishes manual quantity and unit verification issues', (
    tester,
  ) async {
    final english = await _stringsFor(tester, const Locale('en'));
    final korean = await _stringsFor(tester, const Locale('ko'));
    const quantityIssue = RecipeDraftVerificationIssue(
      kind: RecipeDraftVerificationIssueKind.manualHasQuantity,
      path: 'components[0].behavior',
    );
    const unitIssue = RecipeDraftVerificationIssue(
      kind: RecipeDraftVerificationIssueKind.manualHasUnit,
      path: 'components[0].behavior',
    );

    expect(
      english.verificationIssue(quantityIssue),
      'Component 1 scaling behavior: Clear the quantity for a manual '
      'component.',
    );
    expect(
      english.verificationIssue(unitIssue),
      'Component 1 scaling behavior: Clear the unit for a manual component.',
    );
    expect(korean.verificationIssue(quantityIssue), contains('수량을 비우세요'));
    expect(korean.verificationIssue(unitIssue), contains('단위를 비우세요'));
  });

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
