import 'dart:typed_data';

import 'package:bloc/bloc.dart';
import 'package:meta/meta.dart';
import 'package:prep_book/domain/production_run.dart';
import 'package:prep_book/export/export.dart';
import 'package:prep_book/presentation/production_sheet/view/production_sheet_platform.dart';

part 'production_sheet_state.dart';

/// Generates one production sheet and owns its reusable PDF bytes.
final class ProductionSheetCubit extends Cubit<ProductionSheetState> {
  ProductionSheetCubit({
    required ProductionRun run,
    required ProductionSheetBuilder builder,
    required ProductionSheetPdfRenderer renderer,
    required ProductionSheetLocalizations localizations,
    required ProductionSheetPlatform platform,
  }) : _dependencies = (
         run: run,
         builder: builder,
         renderer: renderer,
         localizations: localizations,
         platform: platform,
       ),
       super(const ProductionSheetState());

  final ({
    ProductionRun run,
    ProductionSheetBuilder builder,
    ProductionSheetPdfRenderer renderer,
    ProductionSheetLocalizations localizations,
    ProductionSheetPlatform platform,
  })
  _dependencies;

  Uint8List? _fontBytes;
  var _generationRevision = 0;

  Future<void> generate() => _generate(state.organization);

  Future<void> organizationChanged(
    ProductionSheetOrganization organization,
  ) async {
    if (isClosed ||
        organization == state.organization ||
        state.actionStatus != ProductionSheetActionStatus.idle) {
      return;
    }
    await _generate(organization);
  }

  Future<void> _generate(ProductionSheetOrganization organization) async {
    if (isClosed) return;
    final revision = ++_generationRevision;
    emit(ProductionSheetState(organization: organization));
    try {
      final Uint8List fontBytes;
      if (_fontBytes case final cached?) {
        fontBytes = cached;
      } else {
        final loaded = await _dependencies.platform.loadFontBytes();
        if (isClosed || revision != _generationRevision) return;
        _fontBytes = loaded;
        fontBytes = loaded;
      }
      final sheet = _dependencies.builder.build(
        run: _dependencies.run,
        organization: organization,
        localizations: _dependencies.localizations,
      );
      final bytes = await _dependencies.renderer.render(
        sheet,
        fontBytes: fontBytes,
      );
      if (isClosed || revision != _generationRevision) return;
      emit(
        ProductionSheetState(
          organization: organization,
          status: ProductionSheetStatus.ready,
          bytes: bytes,
          filename: buildProductionSheetFilename(_dependencies.run),
        ),
      );
    } on Object catch (error, stackTrace) {
      if (isClosed || revision != _generationRevision) return;
      addError(error, stackTrace);
      emit(
        ProductionSheetState(
          organization: organization,
          status: ProductionSheetStatus.failure,
          generationError: error,
        ),
      );
    }
  }

  Future<void> share() async {
    if (!state.canUsePdfActions) return;
    final bytes = state.bytes!;
    final filename = state.filename!;
    emit(_actionState(ProductionSheetActionStatus.sharing));
    try {
      await _dependencies.platform.share(bytes: bytes, filename: filename);
      if (isClosed) return;
      emit(_actionState(ProductionSheetActionStatus.idle));
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      if (isClosed) return;
      emit(
        _actionState(
          ProductionSheetActionStatus.idle,
          error: error,
          failedAction: ProductionSheetActionStatus.sharing,
        ),
      );
    }
  }

  Future<void> print() async {
    if (!state.canUsePdfActions) return;
    final bytes = state.bytes!;
    final filename = state.filename!;
    emit(_actionState(ProductionSheetActionStatus.printing));
    try {
      await _dependencies.platform.print(bytes: bytes, name: filename);
      if (isClosed) return;
      emit(_actionState(ProductionSheetActionStatus.idle));
    } on Object catch (error, stackTrace) {
      addError(error, stackTrace);
      if (isClosed) return;
      emit(
        _actionState(
          ProductionSheetActionStatus.idle,
          error: error,
          failedAction: ProductionSheetActionStatus.printing,
        ),
      );
    }
  }

  ProductionSheetState _actionState(
    ProductionSheetActionStatus actionStatus, {
    Object? error,
    ProductionSheetActionStatus? failedAction,
  }) {
    return ProductionSheetState(
      organization: state.organization,
      status: state.status,
      bytes: state.bytes,
      filename: state.filename,
      generationError: state.generationError,
      actionStatus: actionStatus,
      actionError: error,
      failedAction: failedAction,
    );
  }
}
