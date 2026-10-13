/// How [saveDataFile] handed the file to the user.
enum SaveDataHow { downloaded, shared, saved, unsupported }

class SaveDataOutcome {
  const SaveDataOutcome(this.how, [this.path]);

  final SaveDataHow how;

  /// Where the file was written, for [SaveDataHow.saved].
  final String? path;
}
