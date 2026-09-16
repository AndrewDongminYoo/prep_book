part of 'production_history_cubit.dart';

/// Whether history is loading, available, or unavailable.
enum ProductionHistoryStatus { loading, loaded, failure }

/// The current production history view state.
@immutable
final class ProductionHistoryState {
  /// Creates a state that starts in the loading phase.
  const ProductionHistoryState({
    this.status = ProductionHistoryStatus.loading,
    this.runs = const [],
  });

  /// The current read status.
  final ProductionHistoryStatus status;

  /// Stored runs in repository order.
  final List<ProductionHistoryEntry> runs;

  /// This state with the named values replaced.
  ProductionHistoryState copyWith({
    ProductionHistoryStatus? status,
    List<ProductionHistoryEntry>? runs,
  }) => ProductionHistoryState(
    status: status ?? this.status,
    runs: runs ?? this.runs,
  );
}
