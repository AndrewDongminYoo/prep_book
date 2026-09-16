# Backup Memory Profiling Plan

<!-- cspell:words pbxproj -->

## Goal

Build and run the smallest repeatable harness that can measure Issue #31's remaining backup-memory risk before changing production behavior.

## Success criteria

1. Generate a bounded valid fixture → verify with a focused host test and the production database validator.
2. Measure the real backup and restore phases → verify with machine-readable iOS Simulator and Android Emulator reports.
3. Make only evidence-backed production changes → verify each change with a failing regression and both affected phase measurements.
4. Preserve the backup safety contract → verify the focused backup suite and the repository quality gates.

## Owned paths

- `docs/specs/2026-09-16-backup-memory-profiling.md`
- `docs/plans/2026-09-16-backup-memory-profiling.md`
- `docs/notes/2026-09-16-backup-memory-profile.md`
- `integration_test/backup_memory_profile_test.dart`
- `integration_test/support/backup_memory_fixture.dart`
- `integration_test/support/process_rss_sampler.dart`
- `ios/Runner.xcodeproj/project.pbxproj`
- `test/backup/backup_memory_fixture_test.dart`
- `test/backup/process_rss_sampler_test.dart`
- `test/config/ios_flutter_target_test.dart`
- `test/presentation/library_backup/android_backup_save_test.dart`
- `lib/backup/database_validator.dart`
- `lib/presentation/library_backup/view/android_backup_save.dart`
- `lib/presentation/library_backup/view/library_backup_platform.dart`
- `android/app/src/main/kotlin/kr/donminzzi/prep/book/MainActivity.kt`
- `pubspec.yaml`
- `pubspec.lock`
- Production backup files only if the measurements identify one bounded defect.

## Steps

1. Add `integration_test` from the Flutter SDK and regenerate the lockfile with `flutter pub get`.
2. Add a focused host test for a small fixture and a shared generator signature that throws `UnimplementedError`.
3. Run the focused test and record the intended failure from the unimplemented generator.
4. Implement one valid ingredient row, bounded random BLOB filler insertion, final filler-table removal, WAL checkpointing, exact file-size reporting, maximum enforcement, cleanup on failure, production validation, and a ZIP-size floor that rejects a trivially compressed fixture.
5. Run the focused fixture test and the existing validator and size-limit tests.
6. Add the helper-isolate RSS sampler and test its phase aggregation with a small allocation.
7. Add the development-only integration test that exercises create, production native save, production native pick, decode, validate, successful restore, and forced rollback recovery.
   Remove project-level iOS `FLUTTER_TARGET` overrides that replace Flutter's generated integration-test listener, and guard the configuration with a focused regression test.
8. Run a small fixture on Android Emulator first, because Android supplies direct `dumpsys meminfo` corroboration, and save the JSON report plus external samples outside the repository.
9. After the Android heavy job ends, run the same fixture and build mode on iOS Simulator through the dedicated iOS worker, and save the JSON report plus external samples outside the repository.
10. Compare the two reports.
    The iOS Simulator completed both sizes, while Android reproduced an out-of-memory failure in `StandardMessageCodec.readBytes` at native save.
    Replace only the Android save byte-channel handoff with an app-private temporary file and native stream, then repeat both affected Android runs.
11. Write `docs/notes/2026-09-16-backup-memory-profile.md` with exact commands, device runtimes, fixture sizes, phase measurements, artifacts, and the explicit physical-device evidence gap.
12. Run `dart format` on the explicit changed Dart paths, `flutter analyze`, Bloc lint, the focused backup suite, and the full randomized coverage gate.
13. Review the complete diff against the frozen contract, repair confirmed findings, prepare semantic commits, push, open the PR, and complete hosted CI and review rounds.

## Runtime constraints

Run only one mobile build or profiling job at a time.
Do not install or launch on a physical device.
Do not commit trace binaries, generated fixture databases, archives, build products, or Android profiler skill files.
Keep profiling artifacts under a temporary run directory and record only their paths, hashes, and summarized measurements.

## Merge boundary

The default `pr-loop` boundary applies.
Prepare the PR for a merge commit if its commits remain coherent, then request operator merge after exact-head CI and hosted reviews pass.
