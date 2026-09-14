import 'package:bloc/bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_state.dart';
import 'package:prep_book/championship/import/championship_run_builder.dart';
import 'package:prep_book/championship/import/recipe_draft_verifier.dart';
import 'package:prep_book/championship/input/recipe_image_picker.dart';
import 'package:prep_book/championship/input/recipe_image_reducer.dart';
import 'package:prep_book/championship/input/recipe_import_client.dart';
import 'package:prep_book/championship/input/recipe_import_request.dart';
import 'package:prep_book/championship/model/extracted_recipe_draft.dart';
import 'package:prep_book/championship/model/review_recipe_draft.dart';
import 'package:prep_book/championship/sample/championship_sample_loader.dart';
import 'package:prep_book/domain/domain.dart';

typedef ChampionshipNow = DateTime Function();
typedef ChampionshipRunId = String Function();

final class ChampionshipDemoCubit extends Cubit<ChampionshipDemoState> {
  ChampionshipDemoCubit({
    required RecipeImportClient importClient,
    required RecipeImagePicker imagePicker,
    required RecipeImageReducer imageReducer,
    required ChampionshipSampleLoader sampleLoader,
    RecipeDraftVerifier verifier = const RecipeDraftVerifier(),
    ChampionshipRunBuilder runBuilder = const ChampionshipRunBuilder(),
    ChampionshipNow? now,
    ChampionshipRunId? createRunId,
  }) : _dependencies = (
         importClient: importClient,
         imagePicker: imagePicker,
         imageReducer: imageReducer,
         sampleLoader: sampleLoader,
         verifier: verifier,
         runBuilder: runBuilder,
         now: now ?? DateTime.now,
         createRunId: createRunId ?? _defaultRunId,
       ),
       super(ChampionshipDemoState.initial());

  final ({
    RecipeImportClient importClient,
    RecipeImagePicker imagePicker,
    RecipeImageReducer imageReducer,
    ChampionshipSampleLoader sampleLoader,
    RecipeDraftVerifier verifier,
    ChampionshipRunBuilder runBuilder,
    ChampionshipNow now,
    ChampionshipRunId createRunId,
  })
  _dependencies;

  int _requestGeneration = 0;
  ({RecipeImportRequest request, String locale})? _lastImport;

  void setSourceMode(ChampionshipSourceMode mode) {
    emit(
      state.copyWith(
        sourceMode: mode,
        sourceFailure: null,
        importFailure: null,
        importFailureMessage: null,
      ),
    );
  }

  void setSourceText(String value) {
    emit(
      state.copyWith(
        sourceText: value,
        sourceFailure: null,
        importFailure: null,
        importFailureMessage: null,
      ),
    );
  }

  void setLiveConsent({required bool value}) {
    emit(state.copyWith(hasLiveConsent: value, sourceFailure: null));
  }

  Future<void> loadSample() async {
    final generation = ++_requestGeneration;
    _lastImport = null;
    emit(
      state.copyWith(
        isLoading: true,
        sourceFailure: null,
        importFailure: null,
        importFailureMessage: null,
      ),
    );
    try {
      final extracted = await _dependencies.sampleLoader.load();
      if (generation != _requestGeneration) return;
      _acceptExtracted(extracted);
    } on Object {
      if (generation != _requestGeneration) return;
      emit(
        state.copyWith(
          isLoading: false,
          sourceFailure: ChampionshipSourceFailure.sampleUnavailable,
        ),
      );
    }
  }

  Future<void> pickImage() async {
    final generation = ++_requestGeneration;
    emit(
      state.copyWith(
        sourceMode: ChampionshipSourceMode.image,
        sourceFailure: null,
        importFailure: null,
        importFailureMessage: null,
      ),
    );
    try {
      final selected = await _dependencies.imagePicker.pick();
      if (generation != _requestGeneration || selected == null) return;
      // Reduce before anything is shown, so the metadata on screen describes
      // the bytes that will actually be sent.
      final prepared = await _dependencies.imageReducer.reduce(selected);
      if (generation != _requestGeneration) return;
      emit(state.copyWith(preparedImage: prepared));
    } on RecipeImagePickerException {
      if (generation != _requestGeneration) return;
      emit(_imageSelectionFailed());
    } on RecipeImageReducerException {
      if (generation != _requestGeneration) return;
      emit(_imageSelectionFailed());
    }
  }

  /// A failed selection also drops the image picked before it: the visitor
  /// meant to replace it, and an error shown over a still-submittable old
  /// image would send the wrong source.
  ChampionshipDemoState _imageSelectionFailed() => state.copyWith(
    preparedImage: null,
    sourceFailure: ChampionshipSourceFailure.imageSelection,
  );

  Future<void> submitText({required String locale}) async {
    if (!_requireLiveConsent()) return;
    if (state.sourceText.trim().isEmpty ||
        state.sourceText.runes.length > recipeImportMaxTextScalars) {
      emit(
        state.copyWith(sourceFailure: ChampionshipSourceFailure.invalidSource),
      );
      return;
    }
    await _extract(TextRecipeImportRequest(state.sourceText), locale);
  }

  Future<void> submitImage({required String locale}) async {
    if (!_requireLiveConsent()) return;
    final prepared = state.preparedImage;
    if (prepared == null) {
      emit(
        state.copyWith(sourceFailure: ChampionshipSourceFailure.invalidSource),
      );
      return;
    }
    await _extract(
      ImageRecipeImportRequest(
        bytes: prepared.image.bytes,
        mimeType: prepared.image.mimeType,
      ),
      locale,
    );
  }

  Future<void> retryImport() async {
    final lastImport = _lastImport;
    if (lastImport == null) return;
    await _extract(lastImport.request, lastImport.locale);
  }

  void confirmAllUnambiguous() {
    updateReview((draft) => draft.confirmAllUnambiguous());
  }

  void updateReview(ReviewRecipeDraft Function(ReviewRecipeDraft) update) {
    final review = state.review;
    if (review == null) return;
    emit(
      state.copyWith(
        review: update(review),
        reviewIssues: const [],
        verified: null,
        targetFailure: null,
        run: null,
      ),
    );
  }

  void continueToTarget() {
    final review = state.review;
    if (review == null) return;
    final verification = _dependencies.verifier.verify(review);
    switch (verification) {
      case RecipeDraftRejected(:final issues):
        emit(state.copyWith(reviewIssues: issues));
      case RecipeDraftVerified(:final draft):
        emit(
          state.copyWith(
            phase: ChampionshipPhase.target,
            verified: draft,
            reviewIssues: const [],
            targetAmount: '',
            // The verifier resolved this unit, so the symbol exists; the
            // picker offers symbols, and the state must name what it shows.
            targetUnit: review.units
                .resolve(draft.recipe.baseYield.unit)!
                .symbol,
            targetFailure: null,
            run: null,
          ),
        );
    }
  }

  void setTargetAmount(String value) {
    emit(state.copyWith(targetAmount: value, targetFailure: null, run: null));
  }

  void setTargetUnit(String value) {
    emit(state.copyWith(targetUnit: value, targetFailure: null, run: null));
  }

  void calculate() {
    if (state.phase == ChampionshipPhase.result) return;
    final verified = state.verified;
    if (state.phase != ChampionshipPhase.target || verified == null) return;
    final previousRun = state.run;
    if (previousRun != null) {
      emit(state.copyWith(phase: ChampionshipPhase.result));
      return;
    }
    try {
      final run = _dependencies.runBuilder.build(
        draft: verified,
        targetAmount: state.targetAmount,
        targetUnit: state.targetUnit,
        createdAt: _dependencies.now(),
        runId: _dependencies.createRunId(),
      );
      emit(
        state.copyWith(
          phase: ChampionshipPhase.result,
          targetFailure: null,
          run: run,
        ),
      );
    } on BatchLimitExceededError {
      emit(
        state.copyWith(
          targetFailure: ChampionshipTargetFailure.batchLimit,
          run: null,
        ),
      );
    } on Object {
      emit(
        state.copyWith(
          targetFailure: ChampionshipTargetFailure.invalidTarget,
          run: null,
        ),
      );
    }
  }

  void back() {
    switch (state.phase) {
      case ChampionshipPhase.source:
        return;
      case ChampionshipPhase.review:
        emit(state.copyWith(phase: ChampionshipPhase.source));
      case ChampionshipPhase.target:
        emit(state.copyWith(phase: ChampionshipPhase.review));
      case ChampionshipPhase.result:
        emit(state.copyWith(phase: ChampionshipPhase.target));
    }
  }

  void reset() {
    _requestGeneration += 1;
    _lastImport = null;
    emit(ChampionshipDemoState.initial());
  }

  bool _requireLiveConsent() {
    if (state.hasLiveConsent) return true;
    emit(
      state.copyWith(
        sourceFailure: ChampionshipSourceFailure.liveConsentRequired,
      ),
    );
    return false;
  }

  Future<void> _extract(RecipeImportRequest request, String locale) async {
    final generation = ++_requestGeneration;
    _lastImport = (request: request, locale: locale);
    emit(
      state.copyWith(
        isLoading: true,
        sourceFailure: null,
        importFailure: null,
        importFailureMessage: null,
      ),
    );
    try {
      final extracted = await _dependencies.importClient.extract(
        request,
        locale: locale,
      );
      if (generation != _requestGeneration) return;
      _acceptExtracted(extracted);
    } on RecipeImportException catch (error) {
      if (generation != _requestGeneration) return;
      emit(
        state.copyWith(
          isLoading: false,
          importFailure: error.code,
          importFailureMessage: error.message,
        ),
      );
    } on Object {
      if (generation != _requestGeneration) return;
      emit(
        state.copyWith(
          isLoading: false,
          importFailure: RecipeImportFailureCode.serviceFailure,
          importFailureMessage: 'The extraction request failed.',
        ),
      );
    }
  }

  void _acceptExtracted(ExtractedRecipeDraft extracted) {
    emit(
      state.copyWith(
        phase: ChampionshipPhase.review,
        isLoading: false,
        sourceFailure: null,
        importFailure: null,
        importFailureMessage: null,
        extracted: extracted,
        review: ReviewRecipeDraft.fromExtracted(extracted),
        reviewIssues: const [],
        verified: null,
        targetAmount: '',
        targetUnit: '',
        targetFailure: null,
        run: null,
      ),
    );
  }
}

String _defaultRunId() =>
    'championship-${DateTime.now().microsecondsSinceEpoch}';
