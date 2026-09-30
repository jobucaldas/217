import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'src/app.dart';
import 'src/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([
    initializeDateFormatting('pt_BR'),
    initializeDateFormatting('en_US'),
  ]);
  final config = AppConfig.fromEnvironment();
  runApp(App217(config: config));
}
