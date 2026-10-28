import 'package:intl/intl.dart';

import '../api/client.dart';

/// Whether today's pill is already logged, the same notion the partner
/// alert flow uses: an entry for today with `taken == true`. Propagates
/// fetch failures so callers can tolerate them by not scheduling repeats
/// rather than risking a spam of reminders based on stale data.
Future<bool> fetchTodayLogged(ApiClient api, {DateTime? now}) async {
  final n = now ?? DateTime.now();
  final today = DateFormat('yyyy-MM-dd').format(n);
  final entries = await api.listEntries(n.year, n.month);
  return entries.any((e) => e.date == today && e.taken == true);
}
