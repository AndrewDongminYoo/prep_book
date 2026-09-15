import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/cubit/championship_demo_state.dart';
import 'package:prep_book/championship/view/championship_strings.dart';
import 'package:prep_book/championship/view/championship_word_wrap_text.dart';

class ChampionshipSourcePanel extends StatefulWidget {
  const ChampionshipSourcePanel({super.key});

  @override
  State<ChampionshipSourcePanel> createState() =>
      _ChampionshipSourcePanelState();
}

class _ChampionshipSourcePanelState extends State<ChampionshipSourcePanel> {
  late final TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController(
      text: context.read<ChampionshipDemoCubit>().state.sourceText,
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ChampionshipDemoCubit>();
    final state = context.watch<ChampionshipDemoCubit>().state;
    final strings = ChampionshipStrings.of(context);
    if (_textController.text != state.sourceText) {
      _textController.value = TextEditingValue(
        text: state.sourceText,
        selection: TextSelection.collapsed(offset: state.sourceText.length),
      );
    }
    final locale = Localizations.localeOf(context).languageCode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              strings.sourceHeading,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(strings.sourceIntro),
            const SizedBox(height: 24),
            SegmentedButton<ChampionshipSourceMode>(
              key: const ValueKey('source-mode-selector'),
              segments: [
                ButtonSegment(
                  value: ChampionshipSourceMode.text,
                  label: Text(
                    strings.textMode,
                    key: const ValueKey('source-mode-text'),
                  ),
                  icon: const Icon(Icons.notes),
                ),
                ButtonSegment(
                  value: ChampionshipSourceMode.image,
                  label: Text(
                    strings.imageMode,
                    key: const ValueKey('source-mode-image'),
                  ),
                  icon: const Icon(Icons.image_outlined),
                ),
              ],
              selected: {state.sourceMode},
              onSelectionChanged: state.isLoading
                  ? null
                  : (selection) => cubit.setSourceMode(selection.single),
            ),
            const SizedBox(height: 20),
            if (state.sourceMode == ChampionshipSourceMode.text) ...[
              TextField(
                key: const ValueKey('source-text-input'),
                controller: _textController,
                enabled: !state.isLoading,
                minLines: 6,
                maxLines: 12,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  labelText: strings.recipeText,
                  hintText: strings.recipeTextHint,
                  alignLabelWithHint: true,
                  border: const OutlineInputBorder(),
                ),
                onChanged: cubit.setSourceText,
              ),
            ] else ...[
              OutlinedButton.icon(
                key: const ValueKey('source-pick-image'),
                onPressed: state.isLoading ? null : cubit.pickImage,
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(strings.selectImage),
              ),
              if (state.preparedImage case final prepared?) ...[
                const SizedBox(height: 12),
                Text(
                  prepared.image.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  strings.imageMetadata(
                    mimeType: prepared.image.mimeType,
                    byteCount: prepared.image.bytes.length,
                    width: prepared.width,
                    height: prepared.height,
                  ),
                ),
                if (prepared.wasReduced)
                  Text(strings.imageReduced(prepared.originalByteCount)),
              ],
            ],
            const SizedBox(height: 20),
            CheckboxListTile(
              key: const ValueKey('source-consent'),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: state.hasLiveConsent,
              onChanged: state.isLoading
                  ? null
                  : (value) => cubit.setLiveConsent(value: value ?? false),
              title: ChampionshipWordWrapText(
                key: const ValueKey('source-live-consent-label'),
                text: strings.liveConsent,
              ),
            ),
            _PrivacyBoundary(text: strings.privacy),
            const SizedBox(height: 16),
            if (state.sourceMode == ChampionshipSourceMode.text)
              FilledButton.icon(
                key: const ValueKey('source-submit-text'),
                onPressed:
                    !state.isLoading &&
                        state.hasLiveConsent &&
                        state.sourceText.trim().isNotEmpty
                    ? () => cubit.submitText(locale: locale)
                    : null,
                icon: const Icon(Icons.auto_awesome),
                label: Text(strings.importText),
              )
            else
              FilledButton.icon(
                key: const ValueKey('source-submit-image'),
                onPressed:
                    !state.isLoading &&
                        state.hasLiveConsent &&
                        state.preparedImage != null
                    ? () => cubit.submitImage(locale: locale)
                    : null,
                icon: const Icon(Icons.auto_awesome),
                label: Text(strings.importImage),
              ),
            if (state.isLoading) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(strings.loading),
            ],
            if (state.sourceFailure case final failure?) ...[
              const SizedBox(height: 16),
              _FailureMessage(text: strings.sourceFailure(failure)),
            ],
            if (state.importFailure != null) ...[
              const SizedBox(height: 16),
              _FailureMessage(
                text: strings.importFailure(state.importFailure!),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('source-retry'),
                onPressed: state.isLoading ? null : cubit.retryImport,
                icon: const Icon(Icons.refresh),
                label: Text(strings.retry),
              ),
            ],
            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              strings.sampleTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(strings.sampleDescription),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              key: const ValueKey('source-sample'),
              onPressed: state.isLoading ? null : cubit.loadSample,
              icon: const Icon(Icons.science_outlined),
              label: Text(strings.useSample),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrivacyBoundary extends StatelessWidget {
  const _PrivacyBoundary({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.secondaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.privacy_tip_outlined,
              color: colors.onSecondaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
  }
}

class _FailureMessage extends StatelessWidget {
  const _FailureMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Text(text, style: TextStyle(color: colors.error));
  }
}
