import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prep_book/backup/backup.dart';
import 'package:prep_book/backup/backup_files.dart';
import 'package:prep_book/persistence/persistence.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../integration_test/support/backup_memory_fixture.dart';
import '../../integration_test/support/process_rss_sampler.dart';

/// The database size this regression profiles.
///
/// A streaming create or restore grows a host test process by a roughly
/// fixed amount, about 35 MiB whether the database is 64 or 240 MiB, which
/// is allocation churn rather than anything proportional to the library.
/// At this size one whole-buffer copy of the database clearly exceeds that,
/// and the suite stays quick. Device evidence stays in `integration_test/`.
const int _fixtureBytes = 96 * 1024 * 1024;

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'create and restore stream through files rather than whole-archive buffers',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'prep-book-backup-memory-',
      );
      final databasePath = '${directory.path}/library.db';
      Database? connection;
      ProcessRssSampler? sampler;
      addTearDown(() async {
        await sampler?.close();
        if (connection?.isOpen ?? false) await connection!.close();
        await directory.delete(recursive: true);
      });
      final fixture = await generateBackupMemoryFixture(
        factory: databaseFactoryFfi,
        path: databasePath,
        targetBytes: _fixtureBytes,
      );
      connection = await openPrepBookDatabase(
        path: databasePath,
        factory: databaseFactoryFfi,
        singleInstance: false,
      );
      const files = IoBackupFiles();
      const codec = BackupArchiveCodec();
      final validator = BackupDatabaseValidator(factory: databaseFactoryFfi);
      final session = DatabaseSession(
        connection: connection,
        databasePath: databasePath,
        factory: databaseFactoryFfi,
        files: files,
        validateCandidate: validator.validate,
        activate: (_, {required restored}) {},
        mountRecoveryFailure: () => fail('recovery must not be needed'),
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
        now: DateTime.now,
      );
      sampler = await ProcessRssSampler.start();

      final created = await sampler.measure('create', gateway.create);
      final backup = created.value;
      addTearDown(backup.archive.discard);
      expect(
        backup.archive.length,
        greaterThanOrEqualTo((fixture.databaseBytes * 0.9).floor()),
        reason: 'an archive that compresses away profiles nothing',
      );
      final restored = await sampler.measure(
        'restore',
        () => gateway.restore(backup.archive),
      );
      connection = session.connection;

      // Every whole-buffer copy the pipeline used to make cost at least one
      // database size of RSS: create held the snapshot and the ZIP
      // encoder's input and output, and restore held the archive and its
      // inflated entry. Reintroducing any one of them fails this bound.
      for (final measurement in [created.measurement, restored.measurement]) {
        expect(
          measurement.peakBytes - measurement.baselineBytes,
          lessThan(fixture.databaseBytes),
          reason: '${measurement.phase}: ${measurement.toJson()}',
        );
      }
      expect(
        Sqflite.firstIntValue(
          await connection.rawQuery('SELECT COUNT(*) FROM ingredients'),
        ),
        fixture.ingredientCount,
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
