import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/view/championship_demo_page.dart';
import 'package:prep_book/championship/view/championship_strings.dart';
import 'package:prep_book/l10n/l10n.dart';

class ChampionshipApp extends StatelessWidget {
  const ChampionshipApp({required this.cubit, this.locale, super.key});

  final ChampionshipDemoCubit cubit;
  final Locale? locale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => ChampionshipStrings.of(context).title,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
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
        child: const ChampionshipDemoPage(),
      ),
    );
  }
}
