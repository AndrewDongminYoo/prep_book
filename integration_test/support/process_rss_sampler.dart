import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

/// One process-RSS measurement for a named profiling phase.
final class ProcessRssMeasurement {
  /// Creates an immutable phase result.
  const ProcessRssMeasurement({
    required this.phase,
    required this.baselineBytes,
    required this.peakBytes,
    required this.endingBytes,
    required this.sampleCount,
    required this.elapsed,
  });

  /// The stable phase identifier.
  final String phase;

  /// The process RSS immediately before the operation.
  final int baselineBytes;

  /// The highest sampled process RSS during the operation.
  final int peakBytes;

  /// The last process RSS sample after the operation.
  final int endingBytes;

  /// The number of worker-isolate samples in this phase.
  final int sampleCount;

  /// The operation duration.
  final Duration elapsed;

  /// Converts the measurement to the integration report shape.
  Map<String, Object> toJson() => {
    'phase': phase,
    'baselineBytes': baselineBytes,
    'peakBytes': peakBytes,
    'endingBytes': endingBytes,
    'sampleCount': sampleCount,
    'elapsedMicroseconds': elapsed.inMicroseconds,
  };
}

/// The measured value and its process-RSS samples.
final class ProcessRssResult<T> {
  /// Creates a completed measurement result.
  const ProcessRssResult({required this.value, required this.measurement});

  /// The operation result.
  final T value;

  /// The process-RSS measurement.
  final ProcessRssMeasurement measurement;
}

/// Samples process RSS from a helper isolate during synchronous work.
final class ProcessRssSampler {
  ProcessRssSampler._({
    required this._interval,
    required this._samples,
    required this._samplePort,
    required this._sampleSubscription,
    required this._commandPort,
    required this._exitPort,
    required this._exited,
  });

  final Duration _interval;
  final List<int> _samples;
  final ReceivePort _samplePort;
  final StreamSubscription<Object?> _sampleSubscription;
  final SendPort _commandPort;
  final ReceivePort _exitPort;
  final Future<void> _exited;
  var _closed = false;
  var _measuring = false;

  /// Starts the sampler.
  static Future<ProcessRssSampler> start({
    Duration interval = const Duration(milliseconds: 10),
  }) async {
    if (interval <= Duration.zero) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
    final samplePort = ReceivePort();
    final exitPort = ReceivePort();
    final ready = Completer<SendPort>();
    final samples = <int>[];
    // The returned sampler owns and cancels this subscription in close().
    // ignore: cancel_subscriptions
    final sampleSubscription = samplePort.listen((message) {
      switch (message) {
        case final SendPort commands:
          if (!ready.isCompleted) ready.complete(commands);
        case final int rss:
          samples.add(rss);
      }
    });
    final exited = exitPort.first.then((_) {});
    await Isolate.spawn<List<Object>>(_sampleProcessRss, [
      samplePort.sendPort,
      interval.inMicroseconds,
    ], onExit: exitPort.sendPort);
    final commandPort = await ready.future;
    while (samples.isEmpty) {
      await Future<void>.delayed(interval);
    }
    return ProcessRssSampler._(
      interval: interval,
      samples: samples,
      samplePort: samplePort,
      sampleSubscription: sampleSubscription,
      commandPort: commandPort,
      exitPort: exitPort,
      exited: exited,
    );
  }

  /// Measures [operation] as one named phase.
  Future<ProcessRssResult<T>> measure<T>(
    String phase,
    FutureOr<T> Function() operation,
  ) async {
    if (_closed) throw StateError('The RSS sampler is closed.');
    if (_measuring) throw StateError('An RSS phase is already running.');
    if (phase.isEmpty) throw ArgumentError.value(phase, 'phase', 'is empty');

    _measuring = true;
    final baselineBytes = ProcessInfo.currentRss;
    final firstSample = _samples.length;
    final stopwatch = Stopwatch()..start();
    try {
      final value = await Future<T>.sync(operation);
      stopwatch.stop();
      await Future<void>.delayed(_interval);
      final samples = _samples.sublist(firstSample);
      final endingBytes = samples.isEmpty ? baselineBytes : samples.last;
      final peakBytes = [baselineBytes, ...samples].reduce(max);
      return ProcessRssResult(
        value: value,
        measurement: ProcessRssMeasurement(
          phase: phase,
          baselineBytes: baselineBytes,
          peakBytes: peakBytes,
          endingBytes: endingBytes,
          sampleCount: samples.length,
          elapsed: stopwatch.elapsed,
        ),
      );
    } finally {
      _measuring = false;
    }
  }

  /// Stops the worker isolate and releases its ports.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _commandPort.send(null);
    await _exited;
    await _sampleSubscription.cancel();
    _samplePort.close();
    _exitPort.close();
  }
}

void _sampleProcessRss(List<Object> arguments) {
  final output = arguments[0] as SendPort;
  final interval = Duration(microseconds: arguments[1] as int);
  final commands = ReceivePort();
  output.send(commands.sendPort);
  output.send(ProcessInfo.currentRss);
  final timer = Timer.periodic(interval, (_) {
    output.send(ProcessInfo.currentRss);
  });
  commands.listen((message) {
    if (message != null) return;
    timer.cancel();
    commands.close();
    Isolate.exit();
  });
}
