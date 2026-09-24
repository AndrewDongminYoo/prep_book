import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/backup_memory_report.dart';
import '../../integration_test/support/process_rss_sampler.dart';

void main() {
  late ProcessRssSampler sampler;
  late List<String> lines;

  setUp(() async {
    sampler = await ProcessRssSampler.start();
    lines = [];
  });

  tearDown(() => sampler.close());

  test('reports phase entry before an operation can terminate the process', () async {
    final operation = Completer<int>();
    final pending = measureBackupMemoryPhase(
      sampler,
      'nativeSave',
      () => operation.future,
      writeLine: lines.add,
    );
    addTearDown(() {
      if (!operation.isCompleted) operation.complete(42);
      return pending;
    });

    expect(_events(lines), [
      {'phase': 'nativeSave', 'status': 'started'},
    ]);
    operation.complete(42);
    expect((await pending).value, 42);
  });

  test('preserves a completed measurement when a later phase fails', () async {
    final created = await measureBackupMemoryPhase(
      sampler,
      'create',
      () => 42,
      writeLine: lines.add,
    );
    final failure = StateError('native save failed');
    final failureStack = StackTrace.current;

    await expectLater(
      measureBackupMemoryPhase<void>(
        sampler,
        'nativeSave',
        () => Error.throwWithStackTrace(failure, failureStack),
        writeLine: lines.add,
      ),
      throwsA(same(failure)),
    );

    final events = _events(lines);
    expect(events, hasLength(4));
    expect(events[0], {'phase': 'create', 'status': 'started'});
    expect(events[1]['status'], 'completed');
    expect(events[1]['measurement'], created.measurement.toJson());
    expect(events[2], {'phase': 'nativeSave', 'status': 'started'});
    expect(events[3], {'phase': 'nativeSave', 'status': 'failed'});
    final measurement = events[1]['measurement']! as Map<String, dynamic>;
    expect(measurement['phase'], 'create');
    expect(measurement['sampleCount'], greaterThan(0));
    expect(measurement['peakBytes'], greaterThan(0));
    expect(created.value, 42);
  });
}

List<Map<String, dynamic>> _events(List<String> lines) => [
  for (final line in lines)
    if (line.startsWith('BACKUP_MEMORY_PHASE='))
      jsonDecode(line.substring('BACKUP_MEMORY_PHASE='.length)) as Map<String, dynamic>,
];
