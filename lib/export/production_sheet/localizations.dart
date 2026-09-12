import 'package:prep_book/domain/units/quantity.dart';
import 'package:prep_book/domain/warnings.dart';
import 'package:prep_book/export/production_sheet/model.dart';

/// Formats domain values without coupling the export core to Flutter.
abstract interface class ProductionSheetLocalizations {
  ProductionSheetLabels get labels;

  String formatQuantity(Quantity quantity);

  String formatCreatedAt(DateTime createdAtUtc);

  String batch(int number);

  String batchRange(int first, int last);

  String warningMessage({
    required ProductionWarning warning,
    required String recipeName,
    String? componentName,
  });
}
