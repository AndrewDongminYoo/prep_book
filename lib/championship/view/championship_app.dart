import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/championship/cubit/championship_demo_cubit.dart';
import 'package:prep_book/championship/view/championship_demo_page.dart';
import 'package:prep_book/championship/view/championship_strings.dart';
import 'package:prep_book/l10n/l10n.dart';

class ChampionshipApp extends StatelessWidget {
  const ChampionshipApp({this.locale, super.key});

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
        useMaterial3: true,
      ),
      home: BlocProvider(
        create: (_) => ChampionshipDemoCubit(),
        child: const ChampionshipDemoPage(),
      ),
    );
  }
}
