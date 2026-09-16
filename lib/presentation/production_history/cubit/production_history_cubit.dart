import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/application/application.dart';

part 'production_history_state.dart';

/// Drives the read-only production history screen.
final class ProductionHistoryCubit extends Cubit<ProductionHistoryState> {
  /// Creates the cubit over the history list use case.
  ProductionHistoryCubit(this._listHistory)
    : super(const ProductionHistoryState());

  final ListProductionHistory _listHistory;

  /// Reads the stored-run summaries in repository order.
  Future<void> load() async {
    emit(state.copyWith(status: ProductionHistoryStatus.loading));
    try {
      final runs = await _listHistory();
      if (isClosed) return;
      emit(state.copyWith(status: ProductionHistoryStatus.loaded, runs: runs));
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      if (isClosed) return;
      emit(
        state.copyWith(status: ProductionHistoryStatus.failure, runs: const []),
      );
    }
  }

  /// Repeats a failed read.
  Future<void> retry() => load();
}
