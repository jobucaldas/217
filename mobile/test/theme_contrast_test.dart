import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/theme/app_theme.dart';
import 'package:a217/src/theme/contrast.dart';

void main() {
  for (final brightness in Brightness.values) {
    test('theme $brightness meets WCAG AA for body and status text', () {
      final theme = buildApp217Theme(brightness: brightness);
      final scheme = theme.colorScheme;
      final scaffold = theme.scaffoldBackgroundColor;

      expect(
        meetsBodyContrast(scheme.onSurface, scaffold),
        isTrue,
        reason: 'onSurface on scaffold ($brightness)',
      );
      expect(
        meetsBodyContrast(scheme.onSurface, scheme.surface),
        isTrue,
        reason: 'onSurface on surface ($brightness)',
      );
      expect(
        meetsBodyContrast(scheme.onSurfaceVariant, scaffold),
        isTrue,
        reason: 'onSurfaceVariant on scaffold ($brightness)',
      );
      expect(
        meetsLargeContrast(
          App217Colors.statusTaken(brightness),
          scaffold,
        ),
        isTrue,
        reason: 'taken status on scaffold ($brightness)',
      );
      expect(
        meetsLargeContrast(
          App217Colors.statusMissed(brightness),
          scaffold,
        ),
        isTrue,
        reason: 'missed status on scaffold ($brightness)',
      );
      expect(
        meetsBodyContrast(scheme.onPrimaryContainer, scheme.primaryContainer),
        isTrue,
        reason: 'nudge chip label ($brightness)',
      );
    });
  }
}
