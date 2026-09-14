import 'package:flutter/widgets.dart';
import 'package:prep_book/championship/cubit/championship_demo_state.dart';
import 'package:prep_book/championship/input/recipe_import_client.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';

final class ChampionshipStrings {
  const ChampionshipStrings._({required this.isKorean});

  factory ChampionshipStrings.of(BuildContext context) {
    return ChampionshipStrings._(
      isKorean: Localizations.localeOf(context).languageCode == 'ko',
    );
  }

  final bool isKorean;

  String get title =>
      isKorean ? 'PrepBook AI 레시피 가져오기' : 'PrepBook AI Recipe Import';

  String get boundary => isKorean
      ? 'AI는 원본을 해석합니다. PrepBook은 생산 계획을 계산합니다.'
      : 'AI interprets the source. PrepBook calculates the production plan.';

  String get source => isKorean ? '원본' : 'Source';
  String get review => isKorean ? '검토' : 'Review';
  String get target => isKorean ? '목표' : 'Target';
  String get result => isKorean ? '결과' : 'Result';
  String get reset => isKorean ? '초기화' : 'Reset';
  String get back => isKorean ? '뒤로' : 'Back';

  String get sourceHeading =>
      isKorean ? '레시피 원본을 선택하세요' : 'Choose a recipe source';

  String get sourceIntro => isKorean
      ? '검토할 수 있는 초안만 만듭니다. 수량 계산은 사용자가 확인한 뒤에만 '
            '실행됩니다.'
      : 'Create a reviewable draft first. Quantities are calculated only '
            'after your confirmation.';

  String get textMode => isKorean ? '텍스트' : 'Text';
  String get imageMode => isKorean ? '이미지' : 'Image';
  String get sampleTitle =>
      isKorean ? '합성 크루아상 샘플' : 'Synthetic croissant sample';

  String get sampleDescription => isKorean
      ? '네트워크와 동의 절차 없이 전체 흐름을 실행합니다.'
      : 'Complete the full workflow without network access or consent.';

  String get useSample => isKorean ? '샘플로 시작' : 'Use sample';
  String get recipeText => isKorean ? '레시피 텍스트' : 'Recipe text';

  String get recipeTextHint => isKorean
      ? '레시피 이름, 기준 생산량, 재료와 수량을 붙여 넣으세요.'
      : 'Paste the recipe name, base yield, ingredients, and quantities.';

  String get selectImage => isKorean ? '이미지 선택' : 'Select image';
  String imageMetadata({
    required String mimeType,
    required int byteCount,
    required int width,
    required int height,
  }) => '$mimeType · $byteCount B · $width×$height px';
  String imageReduced(int originalByteCount) => isKorean
      ? '원본 $originalByteCount B에서 축소되었습니다.'
      : 'Reduced from $originalByteCount B.';
  String get importText =>
      isKorean ? '텍스트 검토 초안 만들기' : 'Create text review draft';
  String get importImage =>
      isKorean ? '이미지 검토 초안 만들기' : 'Create image review draft';
  String get liveConsent => isKorean
      ? '아래 개인정보 경계를 확인하고 동의합니다.'
      : 'I understand and accept the privacy boundary below.';

  String get privacy => isKorean
      ? 'PrepBook은 입력한 원본을 저장하지 않습니다. 라이브 입력은 설정된 AI 제공자에게 '
            '전송되며, 제공자의 보존 및 악용 모니터링 정책이 적용됩니다. 기밀 또는 개인정보가 '
            '포함된 내용에는 샘플을 사용하세요.'
      : 'PrepBook does not persist your source. Live input is sent to the '
            'configured AI provider under its retention and abuse-monitoring '
            'controls. Use the sample for confidential or personal content.';

  String get loading =>
      isKorean ? '검토 초안을 만드는 중입니다…' : 'Creating the review draft…';
  String get retry => isKorean ? '다시 시도' : 'Retry';

  String sourceFailure(ChampionshipSourceFailure failure) => switch (failure) {
    ChampionshipSourceFailure.liveConsentRequired =>
      isKorean
          ? '라이브 입력을 전송하려면 개인정보 경계에 동의해야 합니다.'
          : 'Accept the privacy boundary before sending live input.',
    ChampionshipSourceFailure.invalidSource =>
      isKorean
          ? '지원되는 텍스트 또는 이미지 원본을 확인하세요.'
          : 'Check the supported text or image source.',
    ChampionshipSourceFailure.imageSelection =>
      isKorean
          ? 'JPEG, PNG 또는 WebP 이미지 한 개를 32 MiB 이하로 선택하세요.'
          : 'Select one JPEG, PNG, or WebP image no larger than 32 MiB.',
    ChampionshipSourceFailure.sampleUnavailable =>
      isKorean ? '샘플을 불러오지 못했습니다.' : 'The sample could not be loaded.',
  };

  String importFailure(RecipeImportFailureCode failure) => switch (failure) {
    RecipeImportFailureCode.serviceBusy =>
      isKorean
          ? '추출 서비스가 사용 중입니다. 다시 시도하세요.'
          : 'The extraction service is busy. Try again.',
    RecipeImportFailureCode.serviceTimeout =>
      isKorean
          ? '추출 요청 시간이 초과되었습니다. 다시 시도하세요.'
          : 'The extraction request timed out. Try again.',
    RecipeImportFailureCode.serviceUnconfigured =>
      isKorean
          ? '라이브 추출을 사용할 수 없습니다. 오프라인 샘플을 사용하세요.'
          : 'Live extraction is unavailable. Use the offline sample.',
    RecipeImportFailureCode.invalidRequest ||
    RecipeImportFailureCode.unsupportedSource ||
    RecipeImportFailureCode.sourceTooLarge =>
      isKorean
          ? '지원되는 텍스트 또는 이미지 원본을 확인하세요.'
          : 'Check the supported text or image source.',
    RecipeImportFailureCode.methodNotAllowed ||
    RecipeImportFailureCode.invalidContentType ||
    RecipeImportFailureCode.invalidModelOutput ||
    RecipeImportFailureCode.serviceFailure =>
      isKorean
          ? '검토 초안을 만들지 못했습니다. 다시 시도하거나 오프라인 샘플을 사용하세요.'
          : 'The review draft could not be created. Try again or use the '
                'offline sample.',
  };

  String get reviewHeading => isKorean ? 'AI 초안을 검토하세요' : 'Review the AI draft';

  String get reviewIntro => isKorean
      ? '각 값의 원문 근거와 확신도를 확인하고 직접 승인하세요. 누락되거나 모호한 '
            '값은 수정해야 합니다.'
      : 'Inspect the source evidence and confidence for every value, then '
            'confirm it. Missing or ambiguous values must be corrected.';

  String get confirmAll =>
      isKorean ? '문제없는 값 모두 확인' : 'Confirm all unambiguous';
  String get aiProposal => isKorean ? 'AI 제안' : 'AI proposal';
  String get evidence => isKorean ? '원문 근거' : 'Evidence';
  String get currentValue => isKorean ? '현재 값' : 'Current value';
  String get issues => isKorean ? '확인할 문제' : 'Issues';
  String get confirm => isKorean ? '이 값 확인' : 'Confirm value';
  String get confirmed => isKorean ? '사용자 확인 완료' : 'Operator confirmed';
  String get edited => isKorean ? '사용자 수정됨' : 'Edited by operator';
  String get needsConfirmation => isKorean ? '확인 필요' : 'Needs confirmation';
  String get notApplicable => isKorean ? '수동 입력 항목' : 'Manual / not applicable';
  String get recipeDetails => isKorean ? '레시피 정보' : 'Recipe details';
  String get recipeName => isKorean ? '레시피 이름' : 'Recipe name';
  String get baseYieldAmount => isKorean ? '기준 생산량' : 'Base yield amount';
  String get baseYieldUnit => isKorean ? '기준 단위' : 'Base yield unit';
  String get maxBatchAmount => isKorean ? '최대 배치 생산량' : 'Maximum batch amount';
  String get maxBatchUnit => isKorean ? '최대 배치 단위' : 'Maximum batch unit';
  String get removeMaximumBatch =>
      isKorean ? '제안된 최대 배치 제거' : 'Remove proposed maximum';
  String get confirmNoMaximumBatch =>
      isKorean ? '최대 배치 제한 없음 확인' : 'Confirm no maximum batch';
  String preparationNote(int index) =>
      isKorean ? '준비 메모 ${index + 1}' : 'Preparation note ${index + 1}';
  String component(int index) =>
      isKorean ? '재료 ${index + 1}' : 'Component ${index + 1}';
  String get componentName => isKorean ? '재료 이름' : 'Component name';
  String get amount => isKorean ? '수량' : 'Amount';
  String get unit => isKorean ? '단위' : 'Unit';
  String get behavior => isKorean ? '계산 방식' : 'Scaling behavior';
  String get note => isKorean ? '메모' : 'Note';
  String get continueToTarget =>
      isKorean ? '검토 완료하고 목표 설정' : 'Finish review and set target';

  String confidence(ExtractionConfidence confidence) => switch (confidence) {
    ExtractionConfidence.high => isKorean ? '높은 확신도' : 'High confidence',
    ExtractionConfidence.medium => isKorean ? '중간 확신도' : 'Medium confidence',
    ExtractionConfidence.low => isKorean ? '낮은 확신도' : 'Low confidence',
  };

  String behaviorName(DraftScalingBehavior behavior) => switch (behavior) {
    DraftScalingBehavior.proportional => isKorean ? '비례' : 'Proportional',
    DraftScalingBehavior.perBatch => isKorean ? '배치마다' : 'Per batch',
    DraftScalingBehavior.fixedOnce => isKorean ? '한 번만' : 'Fixed once',
    DraftScalingBehavior.manual => isKorean ? '수동' : 'Manual',
  };

  String get targetHeading =>
      isKorean ? '생산 목표를 입력하세요' : 'Set the production target';
  String get verifiedRecipe => isKorean ? '확인된 레시피' : 'Verified recipe';
  String get targetAmount => isKorean ? '목표 수량' : 'Target amount';
  String get targetUnit => isKorean ? '목표 단위' : 'Target unit';
  String get calculate =>
      isKorean ? '정확한 생산 계획 계산' : 'Calculate exact production plan';
  String get invalidTarget => isKorean
      ? '0보다 큰 올바른 목표 수량과 호환 단위를 입력하세요.'
      : 'Enter a valid target above zero with a compatible unit.';
  String get batchLimit => isKorean
      ? '계획이 최대 1,000배치를 초과합니다.'
      : 'The plan exceeds the 1,000-batch limit.';

  String get resultHeading => isKorean ? '생산 계획' : 'Production plan';
  String get exactCalculation =>
      isKorean ? 'PrepBook 정확 계산' : 'Exact PrepBook calculation';
  String get exactBoundary => isKorean
      ? '아래 수량은 AI가 아닌 기존 ProductionCalculator가 계산했습니다.'
      : 'The existing ProductionCalculator, not AI, calculated every '
            'quantity below.';
  String batches(int count) => isKorean ? '$count개 배치' : '$count batches';
  String fullBatches(int count, Object yield) => isKorean
      ? '전체 배치 $count개 · 각 $yield'
      : '$count full batches · $yield each';
  String remainderBatch(Object yield) =>
      isKorean ? '나머지 배치 · $yield' : 'Remainder batch · $yield';
  String batch(int index) =>
      isKorean ? '배치 ${index + 1}' : 'Batch ${index + 1}';
  String get manualAsNeeded => isKorean ? '수동 / 필요량' : 'Manual / as needed';
  String get warnings => isKorean ? '계산 경고' : 'Domain warnings';
  String get noWarnings =>
      isKorean ? '계산 경고가 없습니다.' : 'No calculation warnings.';
  String get productionSheet =>
      isKorean ? '생산 작업표 열기' : 'Open production sheet';
  String get productionSheetFailure => isKorean
      ? '생산 작업표를 열지 못했습니다.'
      : 'The production sheet could not be opened.';
}
