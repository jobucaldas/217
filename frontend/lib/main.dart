import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'src/app.dart';
import 'src/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Fonts come from assets/fonts: no request to Google Fonts (LGPD: no
  // third-party transfer of the user's IP address).
  GoogleFonts.config.allowRuntimeFetching = false;
  // The embedded symbol/pattern map installs synchronously (the locale
  // argument is ignored); not awaiting cannot leave formatting
  // uninitialized, but keep the future so an early throw still surfaces.
  unawaited(initializeDateFormatting());
  final config = AppConfig.fromEnvironment();
  runApp(App217(config: config));
}
