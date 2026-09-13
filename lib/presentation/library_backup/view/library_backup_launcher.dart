import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/library_backup/cubit/library_backup_cubit.dart';
import 'package:prep_book/presentation/library_backup/view/library_backup_dialog.dart';
import 'package:prep_book/presentation/library_backup/view/library_backup_platform.dart';

/// Opens one modal backup or restore flow.
@immutable
final class LibraryBackupLauncher {
  /// Creates the launcher over its application and native operations.
  const LibraryBackupLauncher({
    required this.createBackup,
    required this.restoreBackup,
    required this.platform,
  });

  final CreateLibraryBackup createBackup;
  final RestoreLibraryBackup restoreBackup;
  final LibraryBackupPlatform platform;

  /// Opens [action] after the modal route owns its cubit.
  Future<void> open(BuildContext context, LibraryBackupAction action) async {
    final route = DialogRoute<LibraryBackupAction>(
      context: context,
      barrierDismissible: false,
      requestFocus: false,
      builder: (_) => BlocProvider(
        create: (_) => LibraryBackupCubit(
          createBackup: createBackup,
          restoreBackup: restoreBackup,
          platform: platform,
        ),
        child: LibraryBackupDialog(action: action),
      ),
    );
    final result = await Navigator.of(context, rootNavigator: true).push(route);
    await route.completed;
    if (!context.mounted || result != LibraryBackupAction.create) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.libraryBackupSaved)));
  }
}
