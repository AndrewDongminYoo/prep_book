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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF81552D)),
        scaffoldBackgroundColor: const Color(0xFFFFF8F1),
        cardTheme: const CardThemeData(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
        ),
        useMaterial3: true,
      ),
      home: BlocProvider.value(
        value: cubit,
        child: ChampionshipDemoPage(openProductionSheet: openProductionSheet),
      ),
    );
  }
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
