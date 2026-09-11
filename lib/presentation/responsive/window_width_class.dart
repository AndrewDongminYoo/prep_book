import 'package:flutter/widgets.dart';

/// A layout class derived from the width that a presentation surface receives.
enum WindowWidthClass {
  /// A single-pane layout for widths below 600 logical pixels.
  compact,

  /// A multi-pane layout for widths from 600 to 839 logical pixels.
  medium,

  /// A multi-pane layout for widths of at least 840 logical pixels.
  expanded,
}

/// Classifies an available layout [width].
WindowWidthClass windowWidthClassOf(double width) {
  if (width < 600) return WindowWidthClass.compact;
  if (width < 840) return WindowWidthClass.medium;
  return WindowWidthClass.expanded;
}

/// Whether [width] leaves two panes usable at the current [textScaler].
bool usesMultiplePanesAt(double width, TextScaler textScaler) {
  if (!windowWidthClassOf(width).usesMultiplePanes) return false;
  final textScaleFactor = textScaler.scale(16) / 16;
  final minimumWidth = textScaleFactor <= 2 ? 600 : 300 * textScaleFactor;
  return width >= minimumWidth;
}

/// Layout properties that presentation screens share.
extension WindowWidthClassLayout on WindowWidthClass {
  /// Whether the width can show two useful panes at the same time.
  bool get usesMultiplePanes => this != WindowWidthClass.compact;
}
