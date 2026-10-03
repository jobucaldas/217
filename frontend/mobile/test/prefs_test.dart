import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/prefs.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  test('palette ids round-trip', () {
    expect(AppPaletteX.fromId('blue'), AppPalette.blue);
    expect(AppPaletteX.fromId('cyan'), AppPalette.cyan);
    expect(AppPaletteX.fromId('purple'), AppPalette.purple);
    expect(AppPaletteX.fromId(null), AppPalette.blue);
    expect(AppPalette.blue.id, 'blue');
    expect(AppPalette.cyan.id, 'cyan');
    expect(AppPalette.purple.id, 'purple');
  });

  test('legacy palette ids still resolve', () {
    expect(AppPaletteX.fromId('azure'), AppPalette.blue);
    expect(AppPaletteX.fromId('mint'), AppPalette.cyan);
    expect(AppPaletteX.fromId('plum'), AppPalette.purple);
    expect(AppPaletteX.fromId('forest'), AppPalette.blue);
  });

  test('theme mode ids used by AppearancePrefs', () {
    expect(ThemeMode.system.name, 'system');
    expect(ThemeMode.dark.name, 'dark');
    expect(AppearancePrefs.themeModeKey, 'theme_mode');
    expect(AppearancePrefs.paletteKey, 'app_palette');
    expect(AppearancePrefs.fabSideKey, 'today_fab_side');
    expect(AppearancePrefs.fabBottomKey, 'today_fab_bottom');
  });

  test('scaffold neutrals are pinned across accents', () {
    for (final brightness in Brightness.values) {
      final scaffolds = {
        for (final p in AppPalette.values)
          p: scaffoldBackgroundFor(brightness, palette: p),
      };
      expect(
        scaffolds.values.toSet().length,
        1,
        reason: 'scaffold must not shift with accent ($brightness)',
      );
    }
  });

  test('self-host card dismissal is remembered', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final prefs = AppearancePrefs();
    expect(await prefs.selfHostCardDismissed(), isFalse);
    await prefs.dismissSelfHostCard();
    expect(await AppearancePrefs().selfHostCardDismissed(), isTrue);
  });
}
