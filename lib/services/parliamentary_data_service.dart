import 'package:sqflite/sqflite.dart';

import '../models/boundary.dart';
import '../models/council.dart';
import '../models/councillor.dart';
import '../models/councillor_profile.dart';
import '../models/debate.dart';
import '../models/election_result.dart';
import '../models/member.dart';
import '../models/parliament_live_event.dart';
import '../models/speech.dart';
import '../utils/area_match.dart';
import '../utils/parliament_live.dart' as live_match;
import 'api_services.dart';
import 'boundary_service.dart';
import 'council_control_service.dart';
import 'councillor_enrichment_service.dart';
import 'councillor_service.dart';
import 'database_service.dart';

/// How long cached member profiles are considered fresh.
const Duration _membersCacheTtl = Duration(days: 30);
const Duration _recentBillsCacheTtl = Duration(minutes: 30);

/// The high-level service that coordinates API calls with local SQLite caches.
class ParliamentaryDataService {
  final DatabaseService _db;
  final MembersApiService _membersApi;
  final HansardApiService _hansardApi;
  final ParliamentLiveApiService _liveApi;
  final BillsApiService _billsApi;
  final BoundaryService _boundaryService;
  final CouncilControlService _councilControlService;
  final CouncillorService _councillorService;
  final CouncillorEnrichmentService _councillorEnrichmentService;
  List<Map<String, dynamic>>? _recentBillsCache;
  DateTime? _recentBillsCachedAt;

  ParliamentaryDataService({
    DatabaseService? databaseService,
    MembersApiService? membersApiService,
    HansardApiService? hansardApiService,
    ParliamentLiveApiService? parliamentLiveApiService,
    BillsApiService? billsApiService,
    BoundaryService? boundaryService,
    CouncilControlService? councilControlService,
    CouncillorService? councillorService,
    CouncillorEnrichmentService? councillorEnrichmentService,
  })  : _db = databaseService ?? DatabaseService(),
        _membersApi = membersApiService ?? MembersApiService(),
        _hansardApi = hansardApiService ?? HansardApiService(),
        _liveApi = parliamentLiveApiService ?? ParliamentLiveApiService(),
        _billsApi = billsApiService ?? BillsApiService(),
        _boundaryService = boundaryService ?? BoundaryService(),
        _councilControlService =
            councilControlService ?? CouncilControlService(),
        _councillorService = councillorService ?? CouncillorService(),
        _councillorEnrichmentService =
            councillorEnrichmentService ?? CouncillorEnrichmentService();

  Future<Uri?> billPageUrl(String billTitle) async {
    final id = await _billsApi.findBillId(billTitle);
    if (id == null) return null;
    return Uri.parse('https://bills.parliament.uk/bills/$id');
  }

  Future<int?> findBillId(String billTitle) =>
      _billsApi.findBillId(billTitle);

  Future<List<Map<String, dynamic>>> fetchRecentBills({
    int skip = 0,
    int take = 40,
  }) async {
    if (skip == 0) {
      final cached = _recentBillsCache;
      final cachedAt = _recentBillsCachedAt;
      if (cached != null &&
          cachedAt != null &&
          DateTime.now().toUtc().difference(cachedAt) < _recentBillsCacheTtl) {
        return cached;
      }
    }
    final bills = await _billsApi.fetchRecentBills(skip: skip, take: take);
    if (skip == 0 && bills.isNotEmpty) {
      _recentBillsCache = bills;
      _recentBillsCachedAt = DateTime.now().toUtc();
    }
    return bills;
  }

  Future<List<Map<String, dynamic>>> fetchComingUpBills({int skip = 0, int take = 50}) async {
    final rawSittings = await _billsApi.fetchComingUpSittings(skip: skip, take: take);
    final sittings = List<Map<String, dynamic>>.from(rawSittings);

    sittings.sort((a, b) {
      final da = DateTime.tryParse(a["date"] ?? "") ?? DateTime(9999);
      final db = DateTime.tryParse(b["date"] ?? "") ?? DateTime(9999);
      return da.compareTo(db);
    });

    final billIds = <int>[];
    for (final s in sittings) {
      final id = (s["billId"] as num?)?.toInt();
      if (id != null && !billIds.contains(id)) {
        billIds.add(id);
      }
    }

    final bills = <Map<String, dynamic>>[];
    for (final id in billIds) {
      final detail = await _billsApi.fetchBillDetail(id);
      if (detail != null) {
        final billSittings = sittings.where((s) => s["billId"] == id).toList();
        if (billSittings.isNotEmpty) {
          detail["_nextSittingDate"] = billSittings.first["date"];
        }
        bills.add(detail);
      }
    }
    return bills;
  }

  Future<List<Map<String, dynamic>>> searchBills(
    String query, {
    int take = 20,
  }) =>
      _billsApi.searchBills(query, take: take);

  Future<List<Map<String, dynamic>>> fetchBillTypes() =>
      _billsApi.fetchBillTypes();

  Future<Map<String, dynamic>?> fetchBillDetail(int id) =>
      _billsApi.fetchBillDetail(id);

  Future<List<Map<String, dynamic>>> fetchBillStages(int id) =>
      _billsApi.fetchBillStages(id);

  Future<List<Map<String, dynamic>>> fetchBillNews(int id) =>
      _billsApi.fetchBillNews(id);

  Future<List<BoundaryPolygon>> fetchConstituencyBoundaries() =>
      _boundaryService.loadBoundaries(BoundaryType.constituency);

  Future<List<BoundaryPolygon>> fetchCouncilBoundaries() =>
      _boundaryService.loadBoundaries(BoundaryType.council);

  /// Every GB local authority with its control string and seat composition.
  Future<List<Council>> fetchCouncils() =>
      _councilControlService.loadCouncils();

  /// The control/seat composition for a single council in a given [year], or
  /// null when that council isn't present in that year's table. Matched by
  /// normalised name so ONS / OpenCouncilData spelling differences still line
  /// up. Used to build a council's control history.
  Future<Council?> fetchCouncilForYear(String name, int year) async {
    final councils = await _councilControlService.loadCouncils(year: year);
    final target = normaliseCouncilName(name);
    for (final c in councils) {
      if (normaliseCouncilName(c.name) == target) return c;
    }
    return null;
  }

  /// Every UK councillor (name, ward, party), cached nationally.
  Future<List<Councillor>> fetchCouncillors() =>
      _councillorService.loadCouncillors();

  /// Democracy Club enrichment (photo, email, links, first elected) for a
  /// single councillor, or null when no match is found. Best-effort.
  Future<CouncillorProfile?> fetchCouncillorProfile(Councillor councillor) =>
      _councillorEnrichmentService.profileFor(councillor);

  Future<ParliamentLiveEvent?> findLiveEventForDebate({
    required String date,
    required String debateTitle,
    String? house,
  }) async {
    final events = await _liveApi.fetchEventsForDate(date);
    final title = debateTitle.trim();
    if (title.isNotEmpty) {
      final direct = live_match.bestParliamentLiveMatch(title, events);
      if (direct != null) return direct;
    }
    return live_match.fallbackParliamentLiveMatchForHouse(
      events: events,
      house: house,
    );
  }

  Future<List<Member>> getMembers() async {
    final db = await _db.openMembersDb();
    if (await _isMembersCacheFresh(db)) {
      return _loadMembersFromDb(db);
    }
    return _fetchAndCacheMembers(db);
  }

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

  Future<List<Speech>> getSpeeches(String date) async {
    final alreadyCached = await _db.sittingDbExists(date);
    if (alreadyCached) {
      return _loadSpeechesFromDb(date);
    }
    return _fetchAndCacheSitting(date);
  }

  Future<Map<String, dynamic>?> fetchMemberDetail(int id) =>
      _membersApi.fetchMemberDetail(id);

  Future<Map<String, dynamic>?> fetchMemberBiography(int id) =>
      _membersApi.fetchMemberBiography(id);

  Future<List<Map<String, dynamic>>> fetchMemberContributions(int memberId) =>
      _hansardApi.fetchMemberContributions(memberId);

  Future<List<Map<String, dynamic>>> fetchMemberVoting(
    int memberId, {
    int house = 1,
    int page = 1,
  }) =>
      _membersApi.fetchMemberVoting(memberId, house: house, page: page);

  Future<List<double>?> geocodeConstituency(String constituencyName) =>
      _membersApi.geocodeConstituency(constituencyName);

  /// The latest general-election result for a constituency (by name), or null
  /// when the seat can't be resolved or has no published result.
  Future<ConstituencyElectionResult?> fetchConstituencyResult(
    String constituencyName,
  ) async {
    final id = await _membersApi.fetchConstituencyId(constituencyName);
    if (id == null) return null;
    return _membersApi.fetchLatestElectionResult(id);
  }

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

  Future<List<Debate>> getDebatesForDate(String date) async {
    if (!await _db.sittingDbExists(date)) return const [];
    final db = await _db.openSittingDb(date);
    final rows = await db.query('debates', orderBy: 'order_idx ASC');
    return rows.map(Debate.fromDb).toList();
  }

  /// Searches locally cached debate titles for [query], newest sittings first.
  ///
  /// Returns maps with keys: debateId, title, house, section, date.
  Future<List<Map<String, dynamic>>> searchCachedDebates(
    String query, {
    int limit = 40,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final dates = await _db.cachedSittingDates();
    if (dates.isEmpty) return const [];
    final matches = <Map<String, dynamic>>[];
    final needle = trimmed.toLowerCase();
    for (final date in dates) {
      final db = await _db.openSittingDb(date);
      final rows = await db.query(
        'debates',
        columns: ['id', 'title', 'house', 'section', 'order_idx'],
        where: 'LOWER(title) LIKE ?',
        whereArgs: ['%$needle%'],
        orderBy: 'order_idx ASC',
      );
      for (final row in rows) {
        final title = (row['title'] as String?)?.trim() ?? '';
        if (title.isEmpty) continue;
        matches.add({
          'debateId': row['id'],
          'title': title,
          'house': row['house'],
          'section': row['section'],
          'date': date,
        });
        if (matches.length >= limit) return matches;
      }
    }
    return matches;
  }

  Future<bool> isSittingCached(String date) => _db.sittingDbExists(date);

  Future<bool> hasSittingData(String date) async {
    final alreadyCached = await _db.sittingDbExists(date);
    if (alreadyCached) {
      final cachedSpeeches = await _loadSpeechesFromDb(date);
      return cachedSpeeches.isNotEmpty;
    }

    final debates = await _hansardApi.fetchSittingDebates(date);
    return debates.isNotEmpty;
  }

  Future<DateTime?> getPreviousSittingDate(String date) async {
    final linked = await _hansardApi.fetchLinkedSittingDates(date);
    return linked.previousSittingDate;
  }

  Future<DateTime?> getNextSittingDate(String date) async {
    final linked = await _hansardApi.fetchLinkedSittingDates(date);
    return linked.nextSittingDate;
  }

  /// Returns the set of sitting dates (normalised to midnight) in [month] of
  /// [year] across both houses, fetched in one request per house via the
  /// Hansard calendar endpoint.
  Future<Set<DateTime>> getSittingDates(int year, int month) async {
    final result = <DateTime>{};
    for (final house in const ['Commons', 'Lords']) {
      final dates = await _hansardApi.fetchSittingCalendar(year, month, house);
      result.addAll(dates);
    }
    return result;
  }

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

  Future<int> wipeDebateCache() => _db.wipeDebateCache();

  /// Deletes cached map boundary geometry (constituencies + councils).
  Future<int> clearMapBoundaries() => _boundaryService.clearCache();

  /// Deletes cached council data: the councillor list and the control table.
  Future<int> clearCouncilData() async {
    final councillors = await _councillorService.clearCache();
    final control = await _councilControlService.clearCache();
    return councillors + control;
  }

  /// Clears cached MP profiles, forcing a re-fetch on next read.
  Future<int> clearCachedMembers() => _db.wipeMembersCache();

  void dispose() {
    _membersApi.dispose();
    _hansardApi.dispose();
    _liveApi.dispose();
    _billsApi.dispose();
    _boundaryService.dispose();
    _councilControlService.dispose();
    _councillorService.dispose();
    _councillorEnrichmentService.dispose();
  }
}
