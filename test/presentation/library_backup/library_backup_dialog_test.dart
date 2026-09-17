import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/l10n/l10n.dart';
import 'package:prep_book/presentation/library_backup/library_backup.dart';

void main() {
  testWidgets('backup saves, closes, and reports success', (tester) async {
    final gateway = _Gateway();
    final platform = _Platform();
    final pending = Completer<LibraryBackupFile>();
    gateway.pendingCreate = pending.future;
    final launcher = _launcher(gateway, platform);
    await _pumpLauncher(tester, launcher, LibraryBackupAction.create);

    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();

    expect(find.text('Preparing backup…'), findsOneWidget);
    pending.complete(
      LibraryBackupFile(
        bytes: Uint8List.fromList([1]),
        suggestedName: 'backup.prepbook',
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LibraryBackupDialog), findsNothing);
    expect(find.text('Library backup saved.'), findsOneWidget);
    expect(platform.saved, hasLength(1));
  });

  testWidgets('restore confirmation names both data sets and can cancel', (
    tester,
  ) async {
    final gateway = _Gateway();
    final platform = _Platform()..pickedBytes = Uint8List.fromList([2, 3]);
    final launcher = _launcher(gateway, platform);
    await _pumpLauncher(tester, launcher, LibraryBackupAction.restore);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Replace this library?'), findsOneWidget);
    expect(
      find.text(
        'This replaces all recipes and production history with the selected '
        'backup.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryBackupDialog), findsNothing);
    expect(gateway.restoreCalls, 0);
  });

  testWidgets('shows picker progress while native selection is pending', (
    tester,
  ) async {
    final pending = Completer<Uint8List?>();
    final platform = _Platform()..pendingPick = pending.future;
    final launcher = _launcher(_Gateway(), platform);
    await _pumpLauncher(tester, launcher, LibraryBackupAction.restore);

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(find.text('Choose a backup file…'), findsOneWidget);
    pending.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('restore blocks back navigation until activation settles', (
    tester,
  ) async {
    final gateway = _Gateway();
    final platform = _Platform()..pickedBytes = Uint8List.fromList([4, 5]);
    final pending = Completer<void>();
    gateway.pendingRestore = pending.future;
    final launcher = _launcher(gateway, platform);
    await _pumpLauncher(tester, launcher, LibraryBackupAction.restore);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Restore'));
    await tester.pump();
    expect(find.text('Restoring library…'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(LibraryBackupDialog), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(find.byType(LibraryBackupDialog), findsNothing);
    expect(gateway.restoreCalls, 1);
  });

  testWidgets('backup creation blocks back navigation until it settles', (
    tester,
  ) async {
    final gateway = _Gateway();
    final pending = Completer<LibraryBackupFile>();
    gateway.pendingCreate = pending.future;
    await _pumpLauncher(
      tester,
      _launcher(gateway, _Platform()),
      LibraryBackupAction.create,
    );
    await tester.tap(find.text('Open'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Preparing backup…'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pump();

    expect(find.byType(LibraryBackupDialog), findsOneWidget);
    pending.complete(
      LibraryBackupFile(
        bytes: Uint8List.fromList([6]),
        suggestedName: 'backup.prepbook',
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('renders a localizable failure without diagnostic details', (
    tester,
  ) async {
    final gateway = _Gateway()
      ..createError = LibraryBackupException(
        LibraryBackupFailureKind.incompatibleSchema,
        cause: StateError('/private/library.db'),
        stackTrace: StackTrace.current,
      );
    final launcher = _launcher(gateway, _Platform());
    await _pumpLauncher(tester, launcher, LibraryBackupAction.create);

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(
      find.text('Update PrepBook before restoring this newer backup.'),
      findsOneWidget,
    );
    expect(find.textContaining('/private/'), findsNothing);
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryBackupDialog), findsNothing);
  });

  const failureMessages = <LibraryBackupFailureKind, String>{
    LibraryBackupFailureKind.cancelled: 'The file selection was cancelled.',
    LibraryBackupFailureKind.unsupportedFormat: 'Choose a PrepBook backup file.',
    LibraryBackupFailureKind.invalidArchive: 'This backup file is damaged or incomplete. Choose another backup.',
    LibraryBackupFailureKind.backupTooLarge: 'This backup is too large to open on this device.',
    LibraryBackupFailureKind.invalidDatabase: 'This backup contains invalid library data. Choose another backup.',
    LibraryBackupFailureKind.incompatibleSchema: 'Update PrepBook before restoring this newer backup.',
    LibraryBackupFailureKind.saveFailed: 'The backup could not be saved. Choose another location and try again.',
    LibraryBackupFailureKind.restoreFailed:
        'The backup could not be restored. '
        'Your current library is unchanged.',
    LibraryBackupFailureKind.recoveryFailed:
        'The library could not be reopened. '
        'Try again from the startup screen.',
  };
  for (final entry in failureMessages.entries) {
    testWidgets('renders ${entry.key.name} failure copy', (tester) async {
      final gateway = _Gateway()..createError = LibraryBackupException(entry.key);
      final launcher = _launcher(gateway, _Platform());
      await _pumpLauncher(tester, launcher, LibraryBackupAction.create);

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text(entry.value), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
    });
  }

  for (final size in const [Size(320, 568), Size(1000, 700)]) {
    testWidgets('fits confirmation at $size with large text', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _Gateway();
      final platform = _Platform()..pickedBytes = Uint8List.fromList([1]);
      await _pumpLauncher(
        tester,
        _launcher(gateway, platform),
        LibraryBackupAction.restore,
        textScaler: const TextScaler.linear(2),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.widgetWithText(FilledButton, 'Restore'), findsOneWidget);
    });
  }
}

LibraryBackupLauncher _launcher(_Gateway gateway, _Platform platform) => LibraryBackupLauncher(
  createBackup: CreateLibraryBackup(gateway),
  restoreBackup: RestoreLibraryBackup(gateway),
  platform: platform,
);

Future<void> _pumpLauncher(
  WidgetTester tester,
  LibraryBackupLauncher launcher,
  LibraryBackupAction action, {
  TextScaler textScaler = TextScaler.noScaling,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(launcher.open(context, action)),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  ),
);

final class _Gateway implements LibraryBackupGateway {
  int createCalls = 0;
  int restoreCalls = 0;
  Future<LibraryBackupFile>? pendingCreate;
  Future<void>? pendingRestore;
  LibraryBackupException? createError;

  @override
  Future<LibraryBackupFile> create() async {
    createCalls++;
    final error = createError;
    if (error != null) throw error;
    return await (pendingCreate ??
        LibraryBackupFile(
          bytes: Uint8List.fromList([1]),
          suggestedName: 'backup.prepbook',
        ));
  }

  @override
  Future<void> restore(Uint8List archiveBytes) async {
    restoreCalls++;
    await (pendingRestore ?? Future<void>.value());
  }
}

final class _Platform implements LibraryBackupPlatform {
  Uint8List? pickedBytes;
  Future<Uint8List?>? pendingPick;
  final saved = <LibraryBackupFile>[];

  @override
  Future<Uint8List?> pickBackup() async {
    final pending = pendingPick;
    if (pending != null) return await pending;
    return pickedBytes;
  }

  @override
  Future<bool> saveBackup(LibraryBackupFile backup) async {
    saved.add(backup);
    return true;
  }
}
