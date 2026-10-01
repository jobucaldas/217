import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Relative luminance (sRGB) per WCAG 2.x.
double relativeLuminance(Color color) {
  double lin(int channel) {
    final v = channel / 255.0;
    return v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  }

  // ignore: deprecated_member_use — stable channel accessors across Flutter versions
  final r = lin(color.red);
  // ignore: deprecated_member_use
  final g = lin(color.green);
  // ignore: deprecated_member_use
  final b = lin(color.blue);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// Contrast ratio of [foreground] on [background] (1–21).
double contrastRatio(Color foreground, Color background) {
  final l1 = relativeLuminance(foreground);
  final l2 = relativeLuminance(background);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

/// WCAG AA for normal text.
const double kMinBodyContrast = 4.5;

/// WCAG AA for large / bold UI text.
const double kMinLargeContrast = 3.0;

bool meetsBodyContrast(Color foreground, Color background) =>
    contrastRatio(foreground, background) >= kMinBodyContrast;

bool meetsLargeContrast(Color foreground, Color background) =>
    contrastRatio(foreground, background) >= kMinLargeContrast;
