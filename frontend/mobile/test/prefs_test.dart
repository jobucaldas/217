import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/prefs.dart';
import 'package:a217/src/theme/app_theme.dart';

void main() {
  test('palette ids round-trip', () {
    expect(AppPaletteX.fromId('mint'), AppPalette.mint);
    expect(AppPaletteX.fromId('plum'), AppPalette.plum);
    expect(AppPaletteX.fromId('azure'), AppPalette.azure);
    expect(AppPaletteX.fromId('blue'), AppPalette.azure);
    expect(AppPaletteX.fromId('forest'), AppPalette.azure);
    expect(AppPaletteX.fromId(null), AppPalette.azure);
    expect(AppPalette.azure.id, 'azure');
    expect(AppPalette.mint.id, 'mint');
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
