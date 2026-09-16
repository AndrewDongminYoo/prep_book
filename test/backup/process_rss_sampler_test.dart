import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/process_rss_sampler.dart';

void main() {
  test('samples a named phase from a helper isolate', () async {
    final sampler = await ProcessRssSampler.start(
      interval: const Duration(milliseconds: 1),
    );
    addTearDown(sampler.close);

    final result = await sampler.measure('allocation', () async {
      final bytes = Uint8List(8 * 1024 * 1024);
      for (var index = 0; index < bytes.length; index += 4096) {
        bytes[index] = 1;
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return bytes.length;
    });

    expect(result.value, 8 * 1024 * 1024);
    expect(result.measurement.phase, 'allocation');
    expect(result.measurement.sampleCount, greaterThan(0));
    expect(
      result.measurement.peakBytes,
      greaterThanOrEqualTo(result.measurement.baselineBytes),
    );
    expect(
      result.measurement.peakBytes,
      greaterThanOrEqualTo(result.measurement.endingBytes),
    );
    expect(result.measurement.elapsed, isNot(Duration.zero));
  });
}
