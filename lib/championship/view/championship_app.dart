import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/view/championship_demo_page.dart';
import 'package:prep_book/championship/view/championship_result_panel.dart';
import 'package:prep_book/championship/view/championship_strings.dart';
import 'package:prep_book/l10n/l10n.dart';

class ChampionshipApp extends StatelessWidget {
  const ChampionshipApp({
    required this.cubit,
    required this.openProductionSheet,
    this.locale,
    this.onResolvedLocale,
    super.key,
  });

  final ChampionshipDemoCubit cubit;
  final OpenChampionshipProductionSheet openProductionSheet;
  final Locale? locale;
  final ValueChanged<Locale>? onResolvedLocale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => ChampionshipStrings.of(context).title,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => _ResolvedLocaleReporter(
        onResolvedLocale: onResolvedLocale,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: _championshipTheme(),
      home: BlocProvider.value(
        value: cubit,
        child: ChampionshipDemoPage(openProductionSheet: openProductionSheet),
      ),
    );
  }
}

ThemeData _championshipTheme() {
  final colors = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2D4C7C),
    surface: Colors.white,
  );
  final base = ThemeData(colorScheme: colors, useMaterial3: true);
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(6),
    borderSide: BorderSide(color: colors.outlineVariant),
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFFFDFEFE),
    textTheme: base.textTheme.copyWith(
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.5),
    ),
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
      color: colors.surface,
      elevation: 2,
      shadowColor: colors.shadow.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: colors.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.all(16),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.primary, width: 1.5),
      ),
      errorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.error),
      ),
      focusedErrorBorder: inputBorder.copyWith(
        borderSide: BorderSide(color: colors.error, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            foregroundColor: colors.primary,
          ).copyWith(
            side: WidgetStateProperty.resolveWith(
              (states) => BorderSide(
                color: states.contains(WidgetState.disabled)
                    ? colors.outlineVariant.withValues(alpha: 0.6)
                    : colors.outlineVariant,
              ),
            ),
          ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: colors.outlineVariant)),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFFF0F3F7)
              : colors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? colors.onSurface
              : colors.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class _ResolvedLocaleReporter extends StatefulWidget {
  const _ResolvedLocaleReporter({
    required this.onResolvedLocale,
    required this.child,
  });

  final ValueChanged<Locale>? onResolvedLocale;
  final Widget child;

  @override
  State<_ResolvedLocaleReporter> createState() =>
      _ResolvedLocaleReporterState();
}

class _ResolvedLocaleReporterState extends State<_ResolvedLocaleReporter> {
  Locale? _lastLocale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    if (locale == _lastLocale) return;
    _lastLocale = locale;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _lastLocale == locale) {
        widget.onResolvedLocale?.call(locale);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
