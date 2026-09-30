import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  runApp(App217(config: config));
}
