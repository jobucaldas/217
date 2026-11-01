import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:a217/src/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('the logo font is reserved for the wordmark', () {
    final theme = buildApp217Theme(brightness: Brightness.light);
    bool isLogoFont(TextStyle? s) =>
        (s?.fontFamily ?? '').toLowerCase().contains('fraunces');

    final text = theme.textTheme;
    for (final style in [
      text.displayLarge,
      text.displayMedium,
      text.displaySmall,
      text.headlineLarge,
      text.headlineMedium,
      text.headlineSmall,
      text.titleLarge,
      text.titleMedium,
      text.bodyLarge,
      text.labelLarge,
      theme.appBarTheme.titleTextStyle,
    ]) {
      expect(isLogoFont(style), isFalse, reason: '${style?.fontFamily}');
    }

    final logo = theme.extension<App217Typography>()!;
    expect(isLogoFont(logo.wordmark), isTrue);
    expect(isLogoFont(logo.wordmarkLarge), isTrue);
  });
}
