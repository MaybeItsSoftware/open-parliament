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
    if (await _isMembersCacheFresh(db)) {
      return _loadMembersFromDb(db);
    }
    return _fetchAndCacheMembers(db);
  }

  /// Returns a single member by [memberId] from the local cache, or `null` if
  /// not found.
  Future<Member?> getMemberById(int memberId) async {
    final db = await _db.openMembersDb();
    final rows = await db.query(
      'members',
      where: 'id = ?',
      whereArgs: [memberId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Member.fromDb(rows.first);
  }

  /// Returns resolved member IDs for previously learned speaker alias keys.
  Future<Map<String, int>> getSpeakerAliasMemberIds(
    Iterable<String> aliasKeys,
  ) async {
    final keys = aliasKeys.where((k) => k.trim().isNotEmpty).toSet().toList();
    if (keys.isEmpty) return const <String, int>{};

    final db = await _db.openMembersDb();
    final placeholders = List.filled(keys.length, '?').join(',');
    final rows = await db.query(
      'speaker_aliases',
      columns: ['alias_key', 'member_id'],
      where: 'alias_key IN ($placeholders)',
      whereArgs: keys,
    );

    return {
      for (final row in rows)
        (row['alias_key'] as String): (row['member_id'] as num).toInt(),
    };
  }

  /// Persists resolved speaker alias keys for future transcripts.
  Future<void> saveSpeakerAliasMemberIds(
      Map<String, int> aliasToMemberId) async {
    if (aliasToMemberId.isEmpty) return;

    final db = await _db.openMembersDb();
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      for (final entry in aliasToMemberId.entries) {
        final key = entry.key.trim();
        if (key.isEmpty) continue;
        await txn.insert(
          'speaker_aliases',
          {
            'alias_key': key,
            'member_id': entry.value,
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
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

  /// Fetches a single member from the Members API and stores them in the local
  /// members DB.
  ///
  /// Use this when an [id] is known from the Hansard API but is absent
  /// from the local cache — for example, former MPs who left Parliament after
  /// the last full member sync, or newly elected members.
  ///
  /// Returns `null` if the API returns no data or the response cannot be parsed.
  Future<Member?> fetchAndCacheMemberById(int id) async {
    final detail = await _membersApi.fetchMemberDetail(id);
    if (detail == null) return null;
    try {
      final member = Member.fromApiJson({'value': detail});
      final db = await _db.openMembersDb();
      await db.insert(
        'members',
        member.toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return member;
    } catch (_) {
      return null;
    }
  }

  /// Returns all debates for [date] from the local cache.
  ///
  /// Returns an empty list if the sitting has not been cached yet.
  Future<List<Debate>> getDebatesForDate(String date) async {
    if (!await _db.sittingDbExists(date)) return const [];
    final db = await _db.openSittingDb(date);
    final rows = await db.query('debates', orderBy: 'order_idx ASC');
    return rows.map(Debate.fromDb).toList();
  }

  /// Returns `true` when a local cache already exists for [date].
  Future<bool> isSittingCached(String date) => _db.sittingDbExists(date);

  /// Returns `true` if [date] has Hansard sitting content in at least one house.
  Future<bool> hasSittingData(String date) async {
    final alreadyCached = await _db.sittingDbExists(date);
    if (alreadyCached) {
      final cachedSpeeches = await _loadSpeechesFromDb(date);
      return cachedSpeeches.isNotEmpty;
    }

    final debates = await _hansardApi.fetchSittingDebates(date);
    return debates.isNotEmpty;
  }

  /// Returns the closest previous parliamentary sitting date before [date].
  Future<DateTime?> getPreviousSittingDate(String date) async {
    final linked = await _hansardApi.fetchLinkedSittingDates(date);
    return linked.previousSittingDate;
  }

  /// Returns the closest next parliamentary sitting date after [date].
  Future<DateTime?> getNextSittingDate(String date) async {
    final linked = await _hansardApi.fetchLinkedSittingDates(date);
    return linked.nextSittingDate;
  }

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
    final lastFetched = DateTime.fromMillisecondsSinceEpoch(ts, isUtc: true);
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
  }

  Future<List<Speech>> _loadSpeechesFromDb(String date) async {
    final db = await _db.openSittingDb(date);
    final rows = await db.query(
      'speeches',
      orderBy: 'order_idx ASC',
    );
    return rows.map(Speech.fromDb).toList();
  }

  /// Deletes all cached sitting databases. Returns the number wiped.
  Future<int> wipeDebateCache() => _db.wipeDebateCache();

  void dispose() {
    _membersApi.dispose();
    _hansardApi.dispose();
  }
}
