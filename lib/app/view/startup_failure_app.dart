import 'package:flutter/material.dart';
import 'package:prep_book/l10n/l10n.dart';

/// The root widget `bootstrap` mounts when startup failed.
///
/// Opening the database happens before the app is built, so a failure there
/// has no screen to report itself on: without this, `runApp` is never
/// reached and the launch screen stays up forever, with no message and no
/// way out. The recipe library's own error state cannot help, because it is
/// never mounted.
///
/// Carries its own [MaterialApp] for exactly that reason — it is what is
/// mounted instead of `App`, not something shown inside it — and its own
/// localization delegates, so the message is in the operator's language.
class StartupFailureApp extends StatelessWidget {
  /// Creates the failure screen. [onRetry] runs startup again.
  const StartupFailureApp({required this.onRetry, super.key});

  /// Runs the whole startup sequence again, replacing this widget with the
  /// app when it succeeds. A retry is worth offering because the failures
  /// this screen reports are mostly transient — a device out of storage, a
  /// database file still locked by a previous launch.
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: _StartupFailureView(onRetry: onRetry),
  );
}

/// The message and the retry, split out so this widget's context sits below
/// the [MaterialApp] that provides the localizations it reads.
class _StartupFailureView extends StatelessWidget {
  const _StartupFailureView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.startupFailureMessage, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: onRetry,
                  child: Text(l10n.startupFailureRetry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
