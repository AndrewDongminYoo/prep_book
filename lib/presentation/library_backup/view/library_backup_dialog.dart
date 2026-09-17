import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/library_backup/cubit/library_backup_cubit.dart';

/// Modal progress, confirmation, and failure UI for one library operation.
final class LibraryBackupDialog extends StatefulWidget {
  const LibraryBackupDialog({required this.action, super.key});

  final LibraryBackupAction action;

  @override
  State<LibraryBackupDialog> createState() => _LibraryBackupDialogState();
}

class _LibraryBackupDialogState extends State<LibraryBackupDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(context.read<LibraryBackupCubit>().start(widget.action));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<LibraryBackupCubit, LibraryBackupState>(
      listener: (context, state) {
        if (state.status == LibraryBackupStatus.idle || state.status == LibraryBackupStatus.succeeded) {
          Navigator.of(context).pop(state.action);
        }
      },
      builder: (context, state) => PopScope(
        canPop: state.status != LibraryBackupStatus.creating && state.status != LibraryBackupStatus.restoring,
        child: _dialogFor(context, state),
      ),
    );
  }

  Widget _dialogFor(BuildContext context, LibraryBackupState state) {
    final l10n = context.l10n;
    return switch (state.status) {
      LibraryBackupStatus.awaitingConfirmation => AlertDialog(
        title: Text(l10n.libraryBackupConfirmTitle),
        content: Text(l10n.libraryBackupConfirmBody),
        actions: [
          TextButton(
            onPressed: context.read<LibraryBackupCubit>().cancelRestore,
            child: Text(l10n.libraryBackupCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => unawaited(context.read<LibraryBackupCubit>().confirmRestore()),
            child: Text(l10n.libraryBackupConfirm),
          ),
        ],
      ),
      LibraryBackupStatus.failed => AlertDialog(
        title: Text(l10n.libraryBackupFailureTitle),
        content: Text(libraryBackupFailureMessage(l10n, state.failure!)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.libraryBackupCancel),
          ),
        ],
      ),
      LibraryBackupStatus.creating => _ProgressDialog(
        message: l10n.libraryBackupCreating,
      ),
      LibraryBackupStatus.restoring => _ProgressDialog(
        message: l10n.libraryBackupRestoring,
      ),
      LibraryBackupStatus.idle => _ProgressDialog(
        message: widget.action == LibraryBackupAction.restore ? l10n.libraryBackupPicking : l10n.libraryBackupCreating,
      ),
      LibraryBackupStatus.succeeded => const SizedBox.shrink(),
    };
  }
}

final class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => AlertDialog(
    content: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(width: 20),
        Flexible(child: Text(message)),
      ],
    ),
  );
}

/// Returns the localized operator-facing message for [failure].
String libraryBackupFailureMessage(
  AppLocalizations l10n,
  LibraryBackupFailureKind failure,
) => switch (failure) {
  LibraryBackupFailureKind.cancelled => l10n.libraryBackupFailureCancelled,
  LibraryBackupFailureKind.unsupportedFormat => l10n.libraryBackupFailureUnsupportedFormat,
  LibraryBackupFailureKind.invalidArchive => l10n.libraryBackupFailureInvalidArchive,
  LibraryBackupFailureKind.backupTooLarge => l10n.libraryBackupFailureTooLarge,
  LibraryBackupFailureKind.invalidDatabase => l10n.libraryBackupFailureInvalidDatabase,
  LibraryBackupFailureKind.incompatibleSchema => l10n.libraryBackupFailureIncompatibleSchema,
  LibraryBackupFailureKind.saveFailed => l10n.libraryBackupFailureSave,
  LibraryBackupFailureKind.restoreFailed => l10n.libraryBackupFailureRestore,
  LibraryBackupFailureKind.recoveryFailed => l10n.libraryBackupFailureRecovery,
};
