import 'dart:io';

import 'save_data_outcome.dart';
import 'share_sheet.dart';

export 'save_data_outcome.dart';

/// Android: the share sheet (save to Files, Drive, email…). Desktop: the
/// Downloads folder. Otherwise unsupported, so callers can copy instead.
Future<SaveDataOutcome> saveDataFile(String name, String content) async {
  if (Platform.isAndroid) {
    final shared = await shareJsonFile(name, content);
    return shared
        ? const SaveDataOutcome(SaveDataHow.shared)
        : const SaveDataOutcome(SaveDataHow.unsupported);
  }
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (home == null) return const SaveDataOutcome(SaveDataHow.unsupported);
  final sep = Platform.pathSeparator;
  final downloads = Directory('$home${sep}Downloads');
  if (!await downloads.exists()) {
    return const SaveDataOutcome(SaveDataHow.unsupported);
  }
  final file = File('${downloads.path}$sep$name');
  await file.writeAsString(content);
  return SaveDataOutcome(SaveDataHow.saved, file.path);
}
