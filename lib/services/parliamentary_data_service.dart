import 'package:sqflite/sqflite.dart';

import '../models/debate.dart';
import '../models/member.dart';
import '../models/speech.dart';
import 'api_services.dart';
import 'database_service.dart';

/// How long cached member profiles are considered fresh.
const Duration _membersCacheTtl = Duration(days: 30);

/// The high-level service that coordinates API calls with local SQLite caches.
///
/// All read operations follow the local-first strategy:
///  1. Check whether a local cache exists.
///  2. If not (or stale for members), fetch from the network, persist, then
///     return the data.
///  3. Network radio is not used again for the same data until the cache
///     expires.
class ParliamentaryDataService {
  final DatabaseService _db;
  final MembersApiService _membersApi;
  final HansardApiService _hansardApi;

  ParliamentaryDataService({
    DatabaseService? databaseService,
    MembersApiService? membersApiService,
    HansardApiService? hansardApiService,
  })  : _db = databaseService ?? DatabaseService(),
        _membersApi = membersApiService ?? MembersApiService(),
        _hansardApi = hansardApiService ?? HansardApiService();

  // ─── Members ──────────────────────────────────────────────────────────────

  /// Returns all cached members, refreshing from the API if the cache is older
  /// than [_membersCacheTtl] (30 days).
  Future<List<Member>> getMembers() async {
    final db = await _db.openMembersDb();
    try {
      if (await _isMembersCacheFresh(db)) {
        return _loadMembersFromDb(db);
      }
      return _fetchAndCacheMembers(db);
    } finally {
      await db.close();
    }
  }

  /// Returns a single member by [memberId] from the local cache, or `null` if
  /// not found.
  Future<Member?> getMemberById(int memberId) async {
    final db = await _db.openMembersDb();
    try {
      final rows = await db.query(
        'members',
        where: 'id = ?',
        whereArgs: [memberId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return Member.fromDb(rows.first);
    } finally {
      await db.close();
    }
  }

  // ─── Sittings ─────────────────────────────────────────────────────────────

  /// Returns all speeches for [date] (YYYY-MM-DD).
  ///
  /// If `sitting_$date.db` does not yet exist the sitting is fetched from the
  /// Hansard API, persisted to SQLite, then returned. Subsequent calls use
  /// only the local database.
  Future<List<Speech>> getSpeeches(String date) async {
    final alreadyCached = await _db.sittingDbExists(date);
    if (alreadyCached) {
      return _loadSpeechesFromDb(date);
    }
    return _fetchAndCacheSitting(date);
  }

  /// Returns `true` when a local cache already exists for [date].
  Future<bool> isSittingCached(String date) => _db.sittingDbExists(date);

  // ─── Private helpers ──────────────────────────────────────────────────────

  Future<bool> _isMembersCacheFresh(Database db) async {
    final rows = await db.query(
      'meta',
      where: 'key = ?',
      whereArgs: ['last_fetched'],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final ts = int.tryParse(rows.first['value'] as String? ?? '0') ?? 0;
    final lastFetched =
        DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
    return DateTime.now().toUtc().difference(lastFetched) < _membersCacheTtl;
  }

  Future<List<Member>> _loadMembersFromDb(Database db) async {
    final rows = await db.query('members', orderBy: 'name ASC');
    return rows.map(Member.fromDb).toList();
  }

  Future<List<Member>> _fetchAndCacheMembers(Database db) async {
    final members = await _membersApi.fetchAllMembers();
    if (members.isEmpty) {
      // Return whatever we have cached rather than an empty list on failure.
      return _loadMembersFromDb(db);
    }

    await db.transaction((txn) async {
      await txn.delete('members');

      for (final m in members) {
        await txn.insert(
          'members',
          m.toDb(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await txn.insert(
        'meta',
        {
          'key': 'last_fetched',
          'value': DateTime.now().toUtc().millisecondsSinceEpoch.toString(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    return members;
  }

  Future<List<Speech>> _fetchAndCacheSitting(String date) async {
    final debates = await _hansardApi.fetchSittingDebates(date);
    final speeches = <Speech>[];

    for (final debate in debates) {
      final debateSpeeches = await _hansardApi.fetchDebateSpeeches(
        debate.id,
        debate.title,
      );
      speeches.addAll(debateSpeeches);
    }

    // Persist to local SQLite immediately so the network is no longer needed.
    await _persistSitting(date, debates, speeches);
    return speeches;
  }

  Future<void> _persistSitting(
    String date,
    List<Debate> debates,
    List<Speech> speeches,
  ) async {
    final db = await _db.openSittingDb(date);
    try {
      await db.transaction((txn) async {
        for (final d in debates) {
          await txn.insert(
            'debates',
            d.toDb(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }

        for (final s in speeches) {
          await txn.insert(
            'speeches',
            s.toDb(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
    } finally {
      await db.close();
    }
  }

  Future<List<Speech>> _loadSpeechesFromDb(String date) async {
    final db = await _db.openSittingDb(date);
    try {
      final rows = await db.query(
        'speeches',
        orderBy: 'order_idx ASC',
      );
      return rows.map(Speech.fromDb).toList();
    } finally {
      await db.close();
    }
  }

  void dispose() {
    _membersApi.dispose();
    _hansardApi.dispose();
  }
}
