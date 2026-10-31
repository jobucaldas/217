import '../models.dart';
import 'local_store_memory.dart';
import 'local_store_stub.dart'
    if (dart.library.io) 'local_store_io.dart' as platform;

/// A day edit not yet confirmed by the server. [entry] null clears the day.
class PendingWrite {
  const PendingWrite({this.id, required this.date, this.entry});

  final int? id;
  final String date;
  final Entry? entry;
}

/// What the app keeps on the device so it opens and works offline: the
/// last server answers per account, the calendar months it has seen, and the
/// day edits waiting to be sent (oldest first).
abstract class LocalStore {
  /// SQLite (encrypted, key in the Keystore) on Android; memory elsewhere.
  factory LocalStore() => platform.createLocalStore() ?? MemoryLocalStore();

  /// A raw server answer (session, cycle, …) saved under [key].
  Future<String?> readDoc(String userId, String key);
  Future<void> writeDoc(String userId, String key, String body);

  /// Null when the month was never loaded on this device.
  Future<List<Entry>?> monthEntries(String userId, int year, int month);
  Future<void> replaceMonth(
      String userId, int year, int month, List<Entry> entries);

  /// Local copy of one day; [entry] null clears it.
  Future<void> putEntry(String userId, String date, Entry? entry);

  /// Next load of the month comes from the server only.
  Future<void> forgetMonth(String userId, int year, int month);

  Future<List<PendingWrite>> pendingWrites(String userId);

  /// Queues [write], replacing any older write of the same day.
  Future<PendingWrite> enqueue(String userId, PendingWrite write);
  Future<void> removePending(int id);

  /// Drops everything kept for [userId] (sign-out, account deletion).
  Future<void> clearAccount(String userId);
  Future<void> clearAll();
}

/// Global (not per-account) doc keys use this user ID.
const localGlobalUser = '';

String monthPrefix(int year, int month) =>
    '$year-${month.toString().padLeft(2, '0')}-';
