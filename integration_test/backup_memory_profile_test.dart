import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:prep_book/application/application.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:prep_book/presentation/library_backup/view/library_backup_platform.dart';
import 'package:sqflite/sqflite.dart';

import 'support/backup_memory_fixture.dart';
import 'support/backup_memory_report.dart';
import 'support/process_rss_sampler.dart';

const _profileMiBText = String.fromEnvironment(
  'BACKUP_PROFILE_MIB',
  defaultValue: '8',
);

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('validates a copied WAL-mode database without sidecars', (
    _,
  ) async {
    final databasesPath = await databaseFactory.getDatabasesPath();
    final sourcePath = '$databasesPath/backup_memory_validator_source.db';
    final candidatePath = '$databasesPath/backup_memory_validator_candidate';
    await databaseFactory.deleteDatabase(sourcePath);
    await databaseFactory.deleteDatabase(candidatePath);
    addTearDown(() async {
      await databaseFactory.deleteDatabase(sourcePath);
      await databaseFactory.deleteDatabase(candidatePath);
    });

    await generateBackupMemoryFixture(
      factory: databaseFactory,
      path: sourcePath,
      targetBytes: 1024 * 1024,
      maxBytes: 2 * 1024 * 1024,
      payloadBytes: 16 * 1024,
    );
    await File(sourcePath).copy(candidatePath);

    await BackupDatabaseValidator(factory: databaseFactory).validate(
      candidatePath: candidatePath,
      manifestSchemaVersion: currentSchemaVersion,
    );
  });

  testWidgets(
    'profiles near-limit backup create, native handoffs, restore, and rollback',
    (_) async {
      final profileMiB = int.parse(_profileMiBText);
      final targetBytes = profileMiB * 1024 * 1024;
      final databasesPath = await databaseFactory.getDatabasesPath();
      final databasePath = '$databasesPath/backup_memory_profile.db';
      final validationPath = '$databasePath.validation';
      final validationArchivePath = '$validationPath.prepbook';
      await databaseFactory.deleteDatabase(databasePath);
      await databaseFactory.deleteDatabase(validationPath);

      Database? connection;
      ProcessRssSampler? sampler;
      addTearDown(() async {
        await sampler?.close();
        if (connection?.isOpen ?? false) await connection!.close();
        await databaseFactory.deleteDatabase(databasePath);
        await databaseFactory.deleteDatabase(validationPath);
        await const IoBackupFiles().deleteIfExists(validationArchivePath);
      });

      final fixture = await generateBackupMemoryFixture(
        factory: databaseFactory,
        path: databasePath,
        targetBytes: targetBytes,
      );
      expect(fixture.databaseBytes, greaterThanOrEqualTo(targetBytes));
      connection = await openPrepBookDatabase(
        path: databasePath,
        singleInstance: false,
      );
      const files = IoBackupFiles();
      final validator = BackupDatabaseValidator(factory: databaseFactory);
      const codec = BackupArchiveCodec();
      final measurements = <ProcessRssMeasurement>[];
      sampler = await ProcessRssSampler.start();
      Future<T> measure<T>(
        String phase,
        FutureOr<T> Function() operation,
      ) async {
        final result = await measureBackupMemoryPhase(
          sampler!,
          phase,
          operation,
          // Print immediately so a later process termination keeps prior phases.
          writeLine: print,
        );
        measurements.add(result.measurement);
        return result.value;
      }

      var failNextRestoredActivation = false;
      late DatabaseSession session;
      session = DatabaseSession(
        connection: connection,
        databasePath: databasePath,
        factory: databaseFactory,
        files: files,
        validateCandidate: validator.validate,
        activate: (activated, {required restored}) async {
          final count = Sqflite.firstIntValue(
            await activated.rawQuery('SELECT COUNT(*) FROM ingredients'),
          );
          expect(count, fixture.ingredientCount);
          if (restored && failNextRestoredActivation) {
            failNextRestoredActivation = false;
            throw StateError('forced profiling rollback');
          }
        },
        mountRecoveryFailure: () => fail('rollback recovery must succeed'),
      );
      final gateway = DatabaseLibraryBackupGateway(
        createSnapshot: (destinationPath) => DatabaseSnapshotter(
          connection: session.connection,
          databasePath: databasePath,
          files: files,
          validateCandidate: validator.validate,
        ).create(destinationPath: destinationPath),
        encodeArchive: codec.encodeFile,
        decodeArchive: codec.decodeFile,
        restoreDatabase: session.restore,
        files: files,
        now: () => DateTime.now().toUtc(),
      );
      const platform = FilePickerLibraryBackupPlatform();

      final backup = await measure('create', gateway.create);
      final archiveBytes = backup.archive.length;
      expect(
        archiveBytes,
        greaterThanOrEqualTo((fixture.databaseBytes * 0.9).floor()),
        reason: 'the profiled archive must remain near-limit after ZIP',
      );

      final saved = await measure('nativeSave', () async {
        try {
          return await platform.saveBackup(backup);
        } finally {
          await backup.archive.discard();
        }
      });
      expect(saved, isTrue, reason: 'the native save must complete');
      await Future<void>.delayed(const Duration(seconds: 1));

      final picked = await measure('nativePick', platform.pickBackup);
      if (picked == null) fail('the native pick must complete');
      addTearDown(picked.discard);
      expect(picked.length, archiveBytes);

      final decoded = await measure('decode', () async {
        await files.writeStream(
          validationArchivePath,
          picked.openRead(),
          flush: false,
        );
        return await codec.decodeFile(
          archivePath: validationArchivePath,
          databasePath: validationPath,
        );
      });

      await measure<void>('validate', () async {
        try {
          await validator.validate(
            candidatePath: validationPath,
            manifestSchemaVersion: decoded.databaseSchemaVersion,
          );
        } finally {
          await files.deleteDatabaseSidecars(validationPath);
          await files.deleteIfExists(validationPath);
          await files.deleteIfExists(validationArchivePath);
        }
      });
      await Future<void>.delayed(const Duration(seconds: 1));

      await measure<void>('restore', () => gateway.restore(picked));
      connection = session.connection;

      failNextRestoredActivation = true;
      await measure<void>('rollback', () async {
        try {
          await gateway.restore(picked);
          fail('the profiling activation must fail');
        } on LibraryBackupException catch (error) {
          expect(error.kind, LibraryBackupFailureKind.restoreFailed);
        }
      });
      connection = session.connection;
      expect(
        Sqflite.firstIntValue(
          await connection.rawQuery('SELECT COUNT(*) FROM ingredients'),
        ),
        fixture.ingredientCount,
      );

      final report = <String, Object>{
        'schemaVersion': currentSchemaVersion,
        'platform': Platform.operatingSystem,
        'platformVersion': Platform.operatingSystemVersion,
        'buildMode': _buildMode,
        'requestedMiB': profileMiB,
        'fixtureBytes': fixture.databaseBytes,
        'ingredientCount': fixture.ingredientCount,
        'archiveBytes': archiveBytes,
        'rssSamplingIntervalMicroseconds': 10000,
        'measurements': [
          for (final measurement in measurements) measurement.toJson(),
        ],
      };
      binding.reportData = report;
      // The sentinel keeps the report recoverable from `flutter test` output.
      // ignore: avoid_print
      print('BACKUP_MEMORY_REPORT=${jsonEncode(report)}');
    },
    timeout: const Timeout(Duration(minutes: 30)),
  );
}

String get _buildMode => switch ((kReleaseMode, kProfileMode)) {
  (true, _) => 'release',
  (_, true) => 'profile',
  _ => 'debug',
};
