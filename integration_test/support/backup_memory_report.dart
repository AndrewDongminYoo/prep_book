import 'dart:async';
import 'dart:convert';

import 'process_rss_sampler.dart';

/// Records each phase before the next operation can terminate the process.
Future<ProcessRssResult<T>> measureBackupMemoryPhase<T>(
  ProcessRssSampler sampler,
  String phase,
  FutureOr<T> Function() operation, {
  required void Function(String) writeLine,
}) async {
  void report(Map<String, Object> event) => writeLine('BACKUP_MEMORY_PHASE=${jsonEncode(event)}');

  report({'phase': phase, 'status': 'started'});
  final ProcessRssResult<T> result;
  try {
    result = await sampler.measure(phase, operation);
  } on Object {
    report({'phase': phase, 'status': 'failed'});
    rethrow;
  }
  report({
    'phase': phase,
    'status': 'completed',
    'measurement': result.measurement.toJson(),
  });
  return result;
}
