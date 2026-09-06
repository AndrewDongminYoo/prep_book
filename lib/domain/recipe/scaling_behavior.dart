/// How a component's quantity responds to a production run.
enum ScalingBehavior {
  /// Multiplied by the run's scale ratio.
  proportional,

  /// The configured amount, once per batch.
  perBatch,

  /// The configured amount, once for the whole run.
  fixedOnce,

  /// No numeric result until the operator supplies one.
  manual,
}
