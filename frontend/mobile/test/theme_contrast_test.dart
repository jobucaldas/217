import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/theme/app_theme.dart';
import 'package:a217/src/theme/contrast.dart';

void main() {
  for (final palette in AppPalette.values) {
    for (final brightness in Brightness.values) {
      test(
        'palette ${palette.name} $brightness meets WCAG AA for body and status',
        () {
          final scheme =
              buildApp217ColorScheme(brightness, palette: palette);
          final scaffold =
              scaffoldBackgroundFor(brightness, palette: palette);

          expect(
            meetsBodyContrast(scheme.onSurface, scaffold),
            isTrue,
            reason: 'onSurface on scaffold (${palette.name}/$brightness)',
          );
          expect(
            meetsBodyContrast(scheme.onSurface, scheme.surface),
            isTrue,
            reason: 'onSurface on surface (${palette.name}/$brightness)',
          );
          expect(
            meetsBodyContrast(scheme.onSurfaceVariant, scaffold),
            isTrue,
            reason: 'onSurfaceVariant (${palette.name}/$brightness)',
          );
          expect(
            meetsLargeContrast(
              App217Colors.statusTaken(brightness, palette),
              scaffold,
            ),
            isTrue,
            reason: 'taken status (${palette.name}/$brightness)',
          );
          expect(
            meetsLargeContrast(
              App217Colors.statusMissed(brightness, palette),
              scaffold,
            ),
            isTrue,
            reason: 'missed status (${palette.name}/$brightness)',
          );
          expect(
            scaffold,
            brightness == Brightness.dark
                ? const Color(0xFF121212)
                : const Color(0xFFF5F5F4),
            reason: 'pinned scaffold (${palette.name}/$brightness)',
          );
          expect(
            meetsBodyContrast(
              scheme.onPrimaryContainer,
              scheme.primaryContainer,
            ),
            isTrue,
            reason: 'nudge chip (${palette.name}/$brightness)',
          );
          expect(
            meetsLargeContrast(scheme.primary, scaffold),
            isTrue,
            reason: 'primary accent on scaffold (${palette.name}/$brightness)',
          );
          expect(
            meetsBodyContrast(
              scheme.onSecondaryContainer,
              scheme.secondaryContainer,
            ),
            isTrue,
            reason: 'reminder note chip (${palette.name}/$brightness)',
          );
          expect(
            meetsLargeContrast(
              App217Colors.onFilledCell(brightness, palette),
              App217Colors.cellTaken(brightness, palette),
            ),
            isTrue,
            reason: 'day number on taken cell (${palette.name}/$brightness)',
          );
          // Cycle marks sit on the scaffold gap and on empty day cells.
          for (final (name, color) in [
            ('PMS ring', App217Colors.pms(brightness, palette)),
            ('period drop', App217Colors.period(brightness, palette)),
          ]) {
            expect(
              meetsLargeContrast(color, scaffold),
              isTrue,
              reason: '$name on scaffold (${palette.name}/$brightness)',
            );
            expect(
              meetsLargeContrast(color, scheme.surface),
              isTrue,
              reason: '$name on day cell (${palette.name}/$brightness)',
            );
          }
          expect(
            meetsLargeContrast(
              App217Colors.onFilledCell(brightness, palette),
              App217Colors.cellMissed(brightness, palette),
            ),
            isTrue,
            reason: 'cell icons on missed cell (${palette.name}/$brightness)',
          );
          expect(
            meetsBodyContrast(scheme.onErrorContainer, scheme.errorContainer),
            isTrue,
            reason: 'calendar sync error banner (${palette.name}/$brightness)',
          );
        },
      );
    }
  }
}
