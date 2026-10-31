import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../models.dart';
import 'local_store.dart';

LocalStore? createLocalStore() =>
    Platform.isAndroid ? SqliteLocalStore() : null;

/// SQLite through SQLCipher: the file is encrypted with a random key that
/// only lives in the Keystore-backed secure storage.
class SqliteLocalStore implements LocalStore {
  SqliteLocalStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;
  Future<Database>? _db;

  static const _keyName = 'local_db_key';
  static const _fileName = '217-local.db';

  Future<Database> get _open => _db ??= _openDb();

  Future<Database> _openDb() async {
    final path = p.join(await getDatabasesPath(), _fileName);
    var key = await _storage.read(key: _keyName);
    if (key == null) {
      final random = Random.secure();
      key = base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
      await _storage.write(key: _keyName, value: key);
      // A file left without its key (storage wiped) can never be read.
      await deleteDatabase(path);
    }
    Future<Database> open() => openDatabase(
          path,
          password: key,
          version: 1,
          onCreate: (db, _) async {
            final batch = db.batch()
              ..execute('CREATE TABLE docs (user_id TEXT NOT NULL, '
                  'key TEXT NOT NULL, body TEXT NOT NULL, '
                  'PRIMARY KEY (user_id, key))')
              ..execute('CREATE TABLE months (user_id TEXT NOT NULL, '
                  'month TEXT NOT NULL, PRIMARY KEY (user_id, month))')
              ..execute('CREATE TABLE entries (user_id TEXT NOT NULL, '
                  'date TEXT NOT NULL, taken INTEGER, notes TEXT NOT NULL, '
                  'heart INTEGER NOT NULL, period INTEGER NOT NULL, '
                  'PRIMARY KEY (user_id, date))')
              ..execute('CREATE TABLE outbox (id INTEGER PRIMARY KEY '
                  'AUTOINCREMENT, user_id TEXT NOT NULL, date TEXT NOT NULL, '
                  'cleared INTEGER NOT NULL, taken INTEGER, notes TEXT, '
                  'heart INTEGER, period INTEGER)');
            await batch.commit(noResult: true);
          },
        );
    try {
      return await open();
    } on DatabaseException {
      // Unreadable (file damaged): set it aside rather than delete it, since
      // it may hold unsent edits, and start a fresh one.
      final file = File(path);
      if (await file.exists()) {
        await file.rename('$path.unreadable-${DateTime.now().millisecondsSinceEpoch}');
      }
      return open();
    }
  }

  static int? _bool(bool? v) => v == null ? null : (v ? 1 : 0);

  static Map<String, Object?> _row(String userId, Entry e) => {
        'user_id': userId,
        'date': e.date,
        'taken': _bool(e.taken),
        'notes': e.notes,
        'heart': _bool(e.heart),
        'period': _bool(e.period),
      };

  static Entry _entry(Map<String, Object?> r) => Entry(
        date: r['date'] as String,
        taken: r['taken'] == null ? null : r['taken'] == 1,
        notes: (r['notes'] as String?) ?? '',
        heart: r['heart'] == 1,
        period: r['period'] == 1,
      );

  @override
  Future<String?> readDoc(String userId, String key) async {
    final rows = await (await _open).query('docs',
        columns: ['body'],
        where: 'user_id = ? AND key = ?',
        whereArgs: [userId, key]);
    return rows.isEmpty ? null : rows.first['body'] as String;
  }

  @override
  Future<void> writeDoc(String userId, String key, String body) async {
    await (await _open).insert(
        'docs', {'user_id': userId, 'key': key, 'body': body},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<Entry>?> monthEntries(String userId, int year, int month) async {
    final db = await _open;
    final prefix = monthPrefix(year, month);
    final known = await db.query('months',
        where: 'user_id = ? AND month = ?', whereArgs: [userId, prefix]);
    if (known.isEmpty) return null;
    final rows = await db.query('entries',
        where: 'user_id = ? AND date LIKE ?',
        whereArgs: [userId, '$prefix%'],
        orderBy: 'date');
    return rows.map(_entry).toList();
  }

  @override
  Future<void> replaceMonth(
      String userId, int year, int month, List<Entry> entries) async {
    final prefix = monthPrefix(year, month);
    await (await _open).transaction((tx) async {
      await tx.delete('entries',
          where: 'user_id = ? AND date LIKE ?',
          whereArgs: [userId, '$prefix%']);
      for (final e in entries) {
        await tx.insert('entries', _row(userId, e));
      }
      await tx.insert('months', {'user_id': userId, 'month': prefix},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  @override
  Future<void> putEntry(String userId, String date, Entry? entry) async {
    final db = await _open;
    if (entry == null) {
      await db.delete('entries',
          where: 'user_id = ? AND date = ?', whereArgs: [userId, date]);
    } else {
      await db.insert('entries', _row(userId, entry),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  @override
  Future<void> forgetMonth(String userId, int year, int month) async {
    await (await _open).delete('months',
        where: 'user_id = ? AND month = ?',
        whereArgs: [userId, monthPrefix(year, month)]);
  }

  @override
  Future<List<PendingWrite>> pendingWrites(String userId) async {
    final rows = await (await _open).query('outbox',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'id');
    return [
      for (final r in rows)
        PendingWrite(
          id: r['id'] as int,
          date: r['date'] as String,
          entry: r['cleared'] == 1 ? null : _entry(r),
        ),
    ];
  }

  @override
  Future<PendingWrite> enqueue(String userId, PendingWrite write) async {
    final db = await _open;
    final id = await db.transaction((tx) async {
      await tx.delete('outbox',
          where: 'user_id = ? AND date = ?', whereArgs: [userId, write.date]);
      final e = write.entry;
      return tx.insert('outbox', {
        'user_id': userId,
        'date': write.date,
        'cleared': e == null ? 1 : 0,
        if (e != null) ...{
          'taken': _bool(e.taken),
          'notes': e.notes,
          'heart': _bool(e.heart),
          'period': _bool(e.period),
        },
      });
    });
    return PendingWrite(id: id, date: write.date, entry: write.entry);
  }

  @override
  Future<void> removePending(int id) async {
    await (await _open).delete('outbox', where: 'id = ?', whereArgs: [id]);
  }

  @override
  Future<void> clearCalendar(String userId) async {
    await (await _open).transaction((tx) async {
      for (final table in ['months', 'entries']) {
        await tx.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      }
      await tx.delete('docs',
          where: 'user_id = ? AND key = ?', whereArgs: [userId, 'cycle']);
    });
  }

  @override
  Future<void> clearAccount(String userId) async {
    await (await _open).transaction((tx) async {
      for (final table in ['docs', 'months', 'entries', 'outbox']) {
        await tx.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      }
    });
  }

  @override
  Future<void> clearAll() async {
    await (await _open).transaction((tx) async {
      for (final table in ['docs', 'months', 'entries', 'outbox']) {
        await tx.delete(table);
      }
    });
  }
}
