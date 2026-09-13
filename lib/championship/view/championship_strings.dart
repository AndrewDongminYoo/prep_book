import 'package:flutter/widgets.dart';

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

  String get sourcePlaceholder => isKorean
      ? '레시피 원본 입력 기능은 다음 단계에서 이 영역에 연결됩니다.'
      : 'Recipe source input will be connected here in the next task.';
}
