import 'package:prep_book/domain/production_run.dart';
import 'package:prep_book/domain/recipe/component.dart';
import 'package:prep_book/domain/recipe/recipe.dart';
import 'package:prep_book/domain/scaling/scaled_component.dart';
import 'package:prep_book/domain/units/quantity.dart';
import 'package:prep_book/domain/units/rounding.dart';
import 'package:prep_book/domain/warnings.dart';
import 'package:prep_book/export/production_sheet/localizations.dart';
import 'package:prep_book/export/production_sheet/model.dart';

/// Maps one frozen production run to a presentation-independent document.
class ProductionSheetBuilder {
  const ProductionSheetBuilder();

  ProductionSheet build({
    required ProductionRun run,
    required ProductionSheetOrganization organization,
    required ProductionSheetLocalizations localizations,
  }) {
    final sections = <ProductionSheetSection>[];
    _appendSection(
      sections: sections,
      run: run,
      recipe: run.recipe,
      fallbackRecipeId: run.recipe.id,
      result: run.result,
      target: run.targetYield,
      path: 'root',
      depth: 0,
      organization: organization,
      localizations: localizations,
    );
    final warnings = _buildWarnings(run, localizations);
    return ProductionSheet(
      organization: organization,
      labels: localizations.labels,
      runId: run.id,
      recipeName: run.recipe.name,
      recipeRevision: run.recipeRevision,
      targetYield: localizations.formatQuantity(run.targetYield),
      createdAt: localizations.formatCreatedAt(run.createdAt.toUtc()),
      rootBatchCount: run.result.batchPlan.batchCount,
      isDraft: !run.isFinalizable,
      outstandingWarnings: warnings.outstanding,
      acknowledgedWarnings: warnings.acknowledged,
      sections: sections,
    );
  }

  void _appendSection({
    required List<ProductionSheetSection> sections,
    required ProductionRun run,
    required Recipe? recipe,
    required String fallbackRecipeId,
    required ProductionResult result,
    required Quantity target,
    required String path,
    required int depth,
    required ProductionSheetOrganization organization,
    required ProductionSheetLocalizations localizations,
  }) {
    final recipeId = recipe?.id ?? fallbackRecipeId;
    sections.add(
      ProductionSheetSection(
        path: path,
        depth: depth,
        recipeName: recipe?.name ?? fallbackRecipeId,
        targetYield: localizations.formatQuantity(target),
        batchCount: result.batchPlan.batchCount,
        preparationNotes: recipe?.preparationNotes ?? const [],
        tables: switch (organization) {
          ProductionSheetOrganization.batch => _buildBatchTables(
            run: run,
            recipeId: recipeId,
            result: result,
            localizations: localizations,
          ),
          ProductionSheetOrganization.total => [
            ProductionSheetTable(
              heading: localizations.labels.totals,
              batchYield: null,
              rows: [
                for (final component in result.components)
                  _buildRow(
                    run: run,
                    recipeId: recipeId,
                    component: component,
                    quantity: component.total,
                    localizations: localizations,
                  ),
              ],
            ),
          ],
        },
      ),
    );

    for (var index = 0; index < result.components.length; index++) {
      final component = result.components[index];
      final nestedResult = component.subRecipe;
      if (nestedResult == null) continue;
      if (component.source.target case SubRecipeRef(:final recipeId)) {
        _appendSection(
          sections: sections,
          run: run,
          recipe: run.dependencySnapshot[recipeId],
          fallbackRecipeId: recipeId,
          result: nestedResult,
          target: component.total!.displayed,
          path: '$path/$index',
          depth: depth + 1,
          organization: organization,
          localizations: localizations,
        );
      }
    }
  }

  List<ProductionSheetTable> _buildBatchTables({
    required ProductionRun run,
    required String recipeId,
    required ProductionResult result,
    required ProductionSheetLocalizations localizations,
  }) {
    final yields = <Quantity>[
      for (var index = 0; index < result.batchPlan.fullBatchCount; index++)
        result.batchPlan.fullBatchYield,
      ?result.batchPlan.remainderYield,
    ];
    final candidates = <_BatchTable>[
      for (var batchIndex = 0; batchIndex < yields.length; batchIndex++)
        _BatchTable(
          yield: yields[batchIndex],
          rows: [
            for (final component in result.components)
              _SourceRow(
                sourceId: component.source.id,
                quantity: component.perBatch[batchIndex],
                row: _buildRow(
                  run: run,
                  recipeId: recipeId,
                  component: component,
                  quantity: component.perBatch[batchIndex],
                  localizations: localizations,
                ),
              ),
          ],
        ),
    ];
    final tables = <ProductionSheetTable>[];
    var first = 0;
    while (first < candidates.length) {
      var last = first;
      while (last + 1 < candidates.length &&
          candidates[first].hasSameStoredValues(candidates[last + 1])) {
        last++;
      }
      final candidate = candidates[first];
      tables.add(
        ProductionSheetTable(
          heading: first == last
              ? localizations.batch(first + 1)
              : localizations.batchRange(first + 1, last + 1),
          batchYield: localizations.formatQuantity(candidate.yield),
          rows: [for (final sourceRow in candidate.rows) sourceRow.row],
        ),
      );
      first = last + 1;
    }
    return tables;
  }

  ProductionSheetRow _buildRow({
    required ProductionRun run,
    required String recipeId,
    required ScaledComponent component,
    required ScaledQuantity? quantity,
    required ProductionSheetLocalizations localizations,
  }) {
    final override = run.overrides[(recipeId, component.source.id)];
    return ProductionSheetRow(
      label: _componentName(run, component.source),
      note: component.source.note,
      calculated: quantity == null
          ? localizations.labels.manualAmount
          : localizations.formatQuantity(quantity.displayed),
      exact: quantity?.wasRounded ?? false
          ? localizations.formatQuantity(quantity!.exact)
          : null,
      actualWholeRun: override == null
          ? null
          : localizations.formatQuantity(override),
    );
  }

  String _componentName(ProductionRun run, RecipeComponent component) {
    return switch (component.target) {
      IngredientRef(:final ingredientId) =>
        run.ingredientSnapshot[ingredientId]?.name ?? ingredientId,
      SubRecipeRef(:final recipeId) =>
        run.dependencySnapshot[recipeId]?.name ?? recipeId,
    };
  }

  _WarningGroups _buildWarnings(
    ProductionRun run,
    ProductionSheetLocalizations localizations,
  ) {
    final outstanding = <ProductionSheetWarning>[];
    final acknowledged = <ProductionSheetWarning>[];
    for (final warning in run.result.warnings) {
      final recipeId = _warningRecipeId(warning);
      final recipe = recipeId == run.recipe.id
          ? run.recipe
          : run.dependencySnapshot[recipeId];
      final componentId = _warningComponentId(warning);
      final component = componentId == null || recipe == null
          ? null
          : _findComponent(recipe, componentId);
      final resolved = ProductionSheetWarning(
        message: localizations.warningMessage(
          warning: warning,
          recipeName: recipe?.name ?? recipeId,
          componentName: component == null
              ? componentId
              : _componentName(run, component),
        ),
      );
      if (run.acknowledgedWarnings.contains(warning)) {
        acknowledged.add(resolved);
      } else {
        outstanding.add(resolved);
      }
    }
    return _WarningGroups(outstanding: outstanding, acknowledged: acknowledged);
  }

  String _warningRecipeId(ProductionWarning warning) => switch (warning) {
    ManualComponentWarning(:final recipeId) => recipeId,
    RoundingAdjustedWarning(:final recipeId) => recipeId,
    ArchivedDependencyWarning(:final recipeId) => recipeId,
  };

  String? _warningComponentId(ProductionWarning warning) => switch (warning) {
    ManualComponentWarning(:final componentId) => componentId,
    RoundingAdjustedWarning(:final componentId) => componentId,
    ArchivedDependencyWarning() => null,
  };

  RecipeComponent? _findComponent(Recipe recipe, String componentId) {
    for (final component in recipe.components) {
      if (component.id == componentId) return component;
    }
    return null;
  }
}

final class _BatchTable {
  _BatchTable({required this.yield, required this.rows});

  final Quantity yield;
  final List<_SourceRow> rows;

  bool hasSameStoredValues(_BatchTable other) {
    if (yield != other.yield || rows.length != other.rows.length) return false;
    for (var index = 0; index < rows.length; index++) {
      if (!rows[index].hasSameStoredValues(other.rows[index])) return false;
    }
    return true;
  }
}

final class _SourceRow {
  _SourceRow({
    required this.sourceId,
    required this.quantity,
    required this.row,
  });

  final String sourceId;
  final ScaledQuantity? quantity;
  final ProductionSheetRow row;

  bool hasSameStoredValues(_SourceRow other) =>
      sourceId == other.sourceId &&
      quantity?.exact == other.quantity?.exact &&
      quantity?.displayed == other.quantity?.displayed;
}

final class _WarningGroups {
  _WarningGroups({required this.outstanding, required this.acknowledged});

  final List<ProductionSheetWarning> outstanding;
  final List<ProductionSheetWarning> acknowledged;
}
