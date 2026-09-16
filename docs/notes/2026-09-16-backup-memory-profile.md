# Backup Memory Profile Evidence

## Status

The corrected fixture passed a full near-limit iOS Simulator run.
The Android Emulator reproduced a production native-save out-of-memory failure with the same fixture size.
The Android streaming save correction passed both emulator sizes.
Physical-device safety remains unverified, and Issue #31 remains open.

## Method

The development-only integration harness creates a current-schema SQLite database with retained random free pages, then verifies that its ZIP archive remains at least 90 percent of the database size.
It exercises the production backup gateway, native document save and pick adapters, decoding, candidate validation, and database-session restore and rollback.
The activation callback checks the ingredient row count and injects a rollback failure; it does not rebuild the app's repositories or remount the root UI.
A helper isolate samples app-process `ProcessInfo.currentRss` every 10 milliseconds during each named phase.
The reported peak is the highest sampled RSS and may miss a shorter transient peak.
These debug-build process measurements include runtime overhead and do not establish release-build or physical-device behavior.

The command for each platform uses `flutter test integration_test/backup_memory_profile_test.dart -d <device> --flavor development --dart-define=BACKUP_PROFILE_MIB=<size>`.
The smoke size is 8 MiB and the near-limit target is 240 MiB.

## iOS Simulator

The iPhone 17e Simulator ran iOS 26.5 with device ID `7F7136A9-679F-49C9-B548-474C67645A7E`.
The real Files interface completed the save and pick handoffs in both runs.
The repeated 8 MiB run produced an 8,527,872-byte database and an 8,411,296-byte archive; every phase passed.
The repeated 240 MiB run produced a 252,112,896-byte database and a 250,577,073-byte archive; every phase passed.

| Phase      | 8 MiB peak RSS bytes | 240 MiB peak RSS bytes |
| ---------- | -------------------: | ---------------------: |
| create     |          493,731,840 |          1,371,799,552 |
| nativeSave |          501,055,488 |          1,640,120,320 |
| nativePick |          384,745,472 |            560,873,472 |
| decode     |          368,148,480 |          1,188,954,112 |
| validate   |          367,575,040 |          1,565,835,264 |
| restore    |          384,663,552 |          1,367,343,104 |
| rollback   |          385,728,512 |          1,567,834,112 |

The highest sampled near-limit RSS in this repeated run was 1,640,120,320 bytes during native save.
An earlier successful run peaked at 1,435,992,064 bytes during restore, illustrating run-to-run variation.
These are process RSS samples on a Simulator, not a device-specific safe threshold.
An iOS regression also reproduced a copied WAL-mode candidate validation failure without sidecars; the validator now opens the candidate for SQLite recovery before checking it.

The repeated iOS integration-test report lines are preserved here.

```json
{"schemaVersion":2,"platform":"ios","platformVersion":"Version 26.5 (Build 23F77)","buildMode":"debug","requestedMiB":8,"fixtureBytes":8527872,"ingredientCount":1,"archiveBytes":8411296,"rssSamplingIntervalMicroseconds":10000,"measurements":[{"phase":"create","baselineBytes":448479232,"peakBytes":493731840,"endingBytes":492634112,"sampleCount":21,"elapsedMicroseconds":195264},{"phase":"nativeSave","baselineBytes":492634112,"peakBytes":501055488,"endingBytes":375128064,"sampleCount":1933,"elapsedMicroseconds":19346391},{"phase":"nativePick","baselineBytes":377651200,"peakBytes":384745472,"endingBytes":324173824,"sampleCount":1006,"elapsedMicroseconds":10060023},{"phase":"decode","baselineBytes":325156864,"peakBytes":368148480,"endingBytes":357810176,"sampleCount":7,"elapsedMicroseconds":49992},{"phase":"validate","baselineBytes":357826560,"peakBytes":367575040,"endingBytes":367575040,"sampleCount":2,"elapsedMicroseconds":13351},{"phase":"restore","baselineBytes":358268928,"peakBytes":384663552,"endingBytes":360464384,"sampleCount":8,"elapsedMicroseconds":70906},{"phase":"rollback","baselineBytes":360464384,"peakBytes":385728512,"endingBytes":365395968,"sampleCount":11,"elapsedMicroseconds":97308}]}
{"schemaVersion":2,"platform":"ios","platformVersion":"Version 26.5 (Build 23F77)","buildMode":"debug","requestedMiB":240,"fixtureBytes":252112896,"ingredientCount":1,"archiveBytes":250577073,"rssSamplingIntervalMicroseconds":10000,"measurements":[{"phase":"create","baselineBytes":433389568,"peakBytes":1371799552,"endingBytes":1371799552,"sampleCount":458,"elapsedMicroseconds":4658220},{"phase":"nativeSave","baselineBytes":1373011968,"peakBytes":1640120320,"endingBytes":251936768,"sampleCount":1881,"elapsedMicroseconds":18799352},{"phase":"nativePick","baselineBytes":252772352,"peakBytes":560873472,"endingBytes":560873472,"sampleCount":916,"elapsedMicroseconds":9150385},{"phase":"decode","baselineBytes":561201152,"peakBytes":1188954112,"endingBytes":1072627712,"sampleCount":104,"elapsedMicroseconds":1083546},{"phase":"validate","baselineBytes":1067974656,"peakBytes":1565835264,"endingBytes":1166655488,"sampleCount":18,"elapsedMicroseconds":190336},{"phase":"restore","baselineBytes":1166884864,"peakBytes":1367343104,"endingBytes":1303822336,"sampleCount":142,"elapsedMicroseconds":1527694},{"phase":"rollback","baselineBytes":1303822336,"peakBytes":1567834112,"endingBytes":1049329664,"sampleCount":230,"elapsedMicroseconds":2351157}]}
```

## Android Emulator

The Pixel 10 Android Emulator ran Android 17 / API 37 with device ID `emulator-5554`.
The real DocumentsUI interface completed save and pick in the corrected 8 MiB baseline: an 8,531,968-byte database and an 8,411,333-byte archive.

| Phase      | 8 MiB peak RSS bytes |
| ---------- | -------------------: |
| create     |          424,247,296 |
| nativeSave |          429,686,784 |
| nativePick |          401,735,680 |
| decode     |          416,841,728 |
| validate   |          425,410,560 |
| restore    |          433,045,504 |
| rollback   |          435,240,960 |

With the original `file_picker` byte handoff, the corrected 240 MiB fixture reached native save and the app process terminated.
Android logcat recorded `java.lang.OutOfMemoryError` while `StandardMessageCodec.readBytes` tried to allocate 250,577,040 bytes under a 201,326,592-byte growth limit.
The original full logcat stream was not retained; this failure signature was read from the integration session output and cannot be re-audited from a stored log artifact.
This is an observed Android native-channel limit in the product path, not a completed near-limit profile.
A local adapter now writes an app-private temporary file and passes its path to an Android native document-save channel, which streams to the selected `content://` destination.
The first 8 MiB check rejected the path because Dart's `Directory.systemTemp` used the app's `code_cache` while the native guard expected `cache`.
The guard now accepts only a regular file beneath the canonical app-private `codeCacheDir`.
The corrected 8 MiB run passed every phase with an 8,531,968-byte database and an 8,411,353-byte archive.
Its sampled RSS peaks were 431,226,880 bytes at create, 427,425,792 at native save, 397,262,848 at native pick, 423,133,184 at decode, 435,257,344 at validation, 434,913,280 at restore, and 447,184,896 at rollback.
The corrected 240 MiB run also passed every phase with a 252,116,992-byte database and a 250,576,877-byte archive.

| Phase      | Corrected 240 MiB peak RSS bytes |
| ---------- | -------------------------------: |
| create     |                    1,393,147,904 |
| nativeSave |                    1,611,055,104 |
| nativePick |                      861,863,936 |
| decode     |                    1,309,130,752 |
| validate   |                    1,409,515,520 |
| restore    |                    1,354,792,960 |
| rollback   |                    1,365,622,784 |

The highest sampled near-limit RSS was 1,611,055,104 bytes during native save.
The process survived the real DocumentsUI save and pick, but this debug Emulator result does not establish safety on a low-memory physical Android device.

The original integration-test report lines for the corrected Android runs are preserved here.
They record the baseline, peak, ending sample, sample count, and elapsed microseconds for each phase in order.

```json
{"schemaVersion":2,"platform":"android","platformVersion":"CE2A.260420.019 dev-keys","buildMode":"debug","requestedMiB":8,"fixtureBytes":8531968,"ingredientCount":1,"archiveBytes":8411353,"rssSamplingIntervalMicroseconds":10000,"measurements":[{"phase":"create","baselineBytes":380436480,"peakBytes":431226880,"endingBytes":427425792,"sampleCount":65,"elapsedMicroseconds":695730},{"phase":"nativeSave","baselineBytes":427425792,"peakBytes":427425792,"endingBytes":390938624,"sampleCount":1187,"elapsedMicroseconds":12059642},{"phase":"nativePick","baselineBytes":391757824,"peakBytes":397262848,"endingBytes":396296192,"sampleCount":1618,"elapsedMicroseconds":16514392},{"phase":"decode","baselineBytes":396296192,"peakBytes":423133184,"endingBytes":423133184,"sampleCount":25,"elapsedMicroseconds":231171},{"phase":"validate","baselineBytes":423133184,"peakBytes":435257344,"endingBytes":406732800,"sampleCount":8,"elapsedMicroseconds":78030},{"phase":"restore","baselineBytes":406749184,"peakBytes":434913280,"endingBytes":414859264,"sampleCount":113,"elapsedMicroseconds":1769350},{"phase":"rollback","baselineBytes":414859264,"peakBytes":447184896,"endingBytes":406568960,"sampleCount":158,"elapsedMicroseconds":1942121}]}
{"schemaVersion":2,"platform":"android","platformVersion":"CE2A.260420.019 dev-keys","buildMode":"debug","requestedMiB":240,"fixtureBytes":252116992,"ingredientCount":1,"archiveBytes":250576877,"rssSamplingIntervalMicroseconds":10000,"measurements":[{"phase":"create","baselineBytes":398573568,"peakBytes":1393147904,"endingBytes":1392427008,"sampleCount":898,"elapsedMicroseconds":9394347},{"phase":"nativeSave","baselineBytes":1109966848,"peakBytes":1611055104,"endingBytes":859078656,"sampleCount":2646,"elapsedMicroseconds":26896099},{"phase":"nativePick","baselineBytes":858734592,"peakBytes":861863936,"endingBytes":612171776,"sampleCount":2071,"elapsedMicroseconds":21036244},{"phase":"decode","baselineBytes":612450304,"peakBytes":1309130752,"endingBytes":1155973120,"sampleCount":289,"elapsedMicroseconds":3701801},{"phase":"validate","baselineBytes":1155989504,"peakBytes":1409515520,"endingBytes":1081344000,"sampleCount":16,"elapsedMicroseconds":1291701},{"phase":"restore","baselineBytes":1081114624,"peakBytes":1354792960,"endingBytes":1088421888,"sampleCount":402,"elapsedMicroseconds":4376894},{"phase":"rollback","baselineBytes":1088421888,"peakBytes":1365622784,"endingBytes":1086750720,"sampleCount":703,"elapsedMicroseconds":7315140}]}
```

Earlier Android 240 MiB numbers are superseded: the first fixture compressed to roughly half its database size, and another fixture was vacuumed back to 77,824 bytes.
Focused failing regressions exposed both fixture problems before the current entropy and size checks passed.

## Decision Boundary

Do not change `maxLibraryBackupBytes` on the strength of Simulator or Emulator measurements alone.
The Android streaming correction passed both native runs; supported physical-device safety still requires separate evidence.
Keep the current integrity, schema, archive-size, and atomic-restore checks intact.
