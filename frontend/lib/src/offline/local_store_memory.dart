import '../models.dart';
import 'local_store.dart';

/// Kept only while the app runs (web, desktop, tests).
class MemoryLocalStore implements LocalStore {
  final _docs = <String, String>{};
  final _months = <String, Map<String, Entry>>{};
  final _pending = <(String, PendingWrite)>[];
  int _nextId = 1;

  String _monthKey(String userId, int year, int month) =>
      '$userId|${monthPrefix(year, month)}';

  @override
  Future<String?> readDoc(String userId, String key) async =>
      _docs['$userId|$key'];

  @override
  Future<void> writeDoc(String userId, String key, String body) async =>
      _docs['$userId|$key'] = body;

  @override
  Future<List<Entry>?> monthEntries(String userId, int year, int month) async {
    final days = _months[_monthKey(userId, year, month)];
    if (days == null) return null;
    return (days.values.toList()..sort((a, b) => a.date.compareTo(b.date)));
  }

  @override
  Future<void> replaceMonth(
      String userId, int year, int month, List<Entry> entries) async {
    _months[_monthKey(userId, year, month)] = {
      for (final e in entries) e.date: e,
    };
  }

  @override
  Future<void> putEntry(String userId, String date, Entry? entry) async {
    final day = DateTime.parse(date);
    final days = _months[_monthKey(userId, day.year, day.month)];
    if (days == null) return;
    if (entry == null) {
      days.remove(date);
    } else {
      days[date] = entry;
    }
  }

  @override
  Future<void> forgetMonth(String userId, int year, int month) async =>
      _months.remove(_monthKey(userId, year, month));

  @override
  Future<List<PendingWrite>> pendingWrites(String userId) async => [
        for (final (owner, write) in _pending)
          if (owner == userId) write,
      ];

  @override
  Future<PendingWrite> enqueue(String userId, PendingWrite write) async {
    _pending.removeWhere((p) => p.$1 == userId && p.$2.date == write.date);
    final queued =
        PendingWrite(id: _nextId++, date: write.date, entry: write.entry);
    _pending.add((userId, queued));
    return queued;
  }

  @override
  Future<void> removePending(int id) async =>
      _pending.removeWhere((p) => p.$2.id == id);

  @override
  Future<void> clearAccount(String userId) async {
    _docs.removeWhere((k, _) => k.startsWith('$userId|'));
    _months.removeWhere((k, _) => k.startsWith('$userId|'));
    _pending.removeWhere((p) => p.$1 == userId);
  }

  @override
  Future<void> clearAll() async {
    _docs.clear();
    _months.clear();
    _pending.clear();
  }
}
