import 'package:prep_book/championship/import/recipe_draft_verifier.dart';
import 'package:prep_book/championship/input/recipe_image_reducer.dart';
import 'package:prep_book/championship/input/recipe_import_client.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/championship/model/review_recipe_draft.dart';
import 'package:prep_book/domain/domain.dart';

enum ChampionshipPhase { source, review, target, result }

enum ChampionshipSourceMode { text, image }

enum ChampionshipSourceFailure {
  liveConsentRequired,
  invalidSource,
  imageSelection,
  sampleUnavailable,
}

enum ChampionshipTargetFailure { invalidTarget, batchLimit }

final class ChampionshipDemoState {
  ChampionshipDemoState({
    required this.phase,
    required this.sourceMode,
    required this.sourceText,
    required this.preparedImage,
    required this.hasLiveConsent,
    required this.isLoading,
    required this.sourceFailure,
    required this.importFailure,
    required this.importFailureMessage,
    required this.extracted,
    required this.review,
    required List<RecipeDraftVerificationIssue> reviewIssues,
    required this.verified,
    required this.targetAmount,
    required this.targetUnit,
    required this.targetFailure,
    required this.run,
  }) : reviewIssues = List.unmodifiable(reviewIssues);

  factory ChampionshipDemoState.initial() => ChampionshipDemoState(
    phase: ChampionshipPhase.source,
    sourceMode: ChampionshipSourceMode.text,
    sourceText: '',
    preparedImage: null,
    hasLiveConsent: false,
    isLoading: false,
    sourceFailure: null,
    importFailure: null,
    importFailureMessage: null,
    extracted: null,
    review: null,
    reviewIssues: const [],
    verified: null,
    targetAmount: '',
    targetUnit: '',
    targetFailure: null,
    run: null,
  );

  final ChampionshipPhase phase;
  final ChampionshipSourceMode sourceMode;
  final String sourceText;
  final PreparedRecipeImage? preparedImage;
  final bool hasLiveConsent;
  final bool isLoading;
  final ChampionshipSourceFailure? sourceFailure;
  final RecipeImportFailureCode? importFailure;
  final String? importFailureMessage;
  final ExtractedRecipeDraft? extracted;
  final ReviewRecipeDraft? review;
  final List<RecipeDraftVerificationIssue> reviewIssues;
  final VerifiedRecipeDraft? verified;
  final String targetAmount;
  final String targetUnit;
  final ChampionshipTargetFailure? targetFailure;
  final ProductionRun? run;

  ChampionshipDemoState copyWith({
    ChampionshipPhase? phase,
    ChampionshipSourceMode? sourceMode,
    String? sourceText,
    Object? preparedImage = _unset,
    bool? hasLiveConsent,
    bool? isLoading,
    Object? sourceFailure = _unset,
    Object? importFailure = _unset,
    Object? importFailureMessage = _unset,
    Object? extracted = _unset,
    Object? review = _unset,
    List<RecipeDraftVerificationIssue>? reviewIssues,
    Object? verified = _unset,
    String? targetAmount,
    String? targetUnit,
    Object? targetFailure = _unset,
    Object? run = _unset,
  }) => ChampionshipDemoState(
    phase: phase ?? this.phase,
    sourceMode: sourceMode ?? this.sourceMode,
    sourceText: sourceText ?? this.sourceText,
    preparedImage: preparedImage == _unset
        ? this.preparedImage
        : preparedImage as PreparedRecipeImage?,
    hasLiveConsent: hasLiveConsent ?? this.hasLiveConsent,
    isLoading: isLoading ?? this.isLoading,
    sourceFailure: sourceFailure == _unset
        ? this.sourceFailure
        : sourceFailure as ChampionshipSourceFailure?,
    importFailure: importFailure == _unset
        ? this.importFailure
        : importFailure as RecipeImportFailureCode?,
    importFailureMessage: importFailureMessage == _unset
        ? this.importFailureMessage
        : importFailureMessage as String?,
    extracted: extracted == _unset
        ? this.extracted
        : extracted as ExtractedRecipeDraft?,
    review: review == _unset ? this.review : review as ReviewRecipeDraft?,
    reviewIssues: reviewIssues ?? this.reviewIssues,
    verified: verified == _unset
        ? this.verified
        : verified as VerifiedRecipeDraft?,
    targetAmount: targetAmount ?? this.targetAmount,
    targetUnit: targetUnit ?? this.targetUnit,
    targetFailure: targetFailure == _unset
        ? this.targetFailure
        : targetFailure as ChampionshipTargetFailure?,
    run: run == _unset ? this.run : run as ProductionRun?,
  );
}

const Object _unset = Object();
