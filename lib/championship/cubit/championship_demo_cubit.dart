import 'package:bloc/bloc.dart';

enum ChampionshipPhase { source, review, target, result }

final class ChampionshipDemoCubit extends Cubit<ChampionshipPhase> {
  ChampionshipDemoCubit() : super(ChampionshipPhase.source);
}
