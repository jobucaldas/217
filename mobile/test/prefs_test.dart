import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:a217/src/prefs.dart';
import 'package:a217/src/theme/palette.dart';

void main() {
  test('palette ids round-trip', () {
    expect(AppPaletteX.fromId('mint'), AppPalette.mint);
    expect(AppPaletteX.fromId('plum'), AppPalette.plum);
    expect(AppPaletteX.fromId(null), AppPalette.forest);
    expect(AppPalette.mint.id, 'mint');
  });

  test('theme mode ids used by AppearancePrefs', () {
    // Defaults to system when unset — verified via load with empty storage
    // in widget tests; here we lock the encoding contract.
    expect(ThemeMode.system.name, 'system');
    expect(ThemeMode.dark.name, 'dark');
    expect(AppearancePrefs.themeModeKey, 'theme_mode');
    expect(AppearancePrefs.paletteKey, 'app_palette');
  });
}
