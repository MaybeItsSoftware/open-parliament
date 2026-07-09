import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/council.dart';
import '../models/councillor.dart';
import '../models/councillor_profile.dart';
import '../models/member.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/area_match.dart';

class SearchResults {
  final List<Member> members;
  final List<CouncillorSearchResult> councillors;
  final List<BillSearchResult> bills;
  final List<DebateSearchResult> debates;
  final List<ConstituencySearchResult> constituencies;

  const SearchResults({
    this.members = const [],
    this.councillors = const [],
    this.bills = const [],
    this.debates = const [],
    this.constituencies = const [],
  });

  bool get isEmpty =>
      members.isEmpty &&
      councillors.isEmpty &&
      bills.isEmpty &&
      debates.isEmpty &&
      constituencies.isEmpty;
}

class BillSearchResult {
  final int id;
  final String title;
  final String house;
  final String? stage;
  final DateTime? lastUpdate;

  const BillSearchResult({
    required this.id,
    required this.title,
    required this.house,
    this.stage,
    this.lastUpdate,
  });

  factory BillSearchResult.fromJson(Map<String, dynamic> json) {
    final stage = json['currentStage'] as Map<String, dynamic>?;
    final lastRaw = json['lastUpdate'] as String?;
    return BillSearchResult(
      id: (json['billId'] as num?)?.toInt() ?? 0,
      title: (json['shortTitle'] as String?) ?? '',
      house: (json['currentHouse'] as String?) ?? '',
      stage: stage?['description'] as String?,
      lastUpdate: lastRaw != null ? DateTime.tryParse(lastRaw) : null,
    );
  }
}

class DebateSearchResult {
  final String debateId;
  final String title;
  final String house;
  final String date;
  final String? section;

  const DebateSearchResult({
    required this.debateId,
    required this.title,
    required this.house,
    required this.date,
    this.section,
  });

  DateTime? get dateValue => DateTime.tryParse(date);
}

class CouncillorSearchResult {
  final Councillor councillor;
  final Council? council;

  const CouncillorSearchResult({
    required this.councillor,
    required this.council,
  });
}

class ConstituencySearchResult {
  final String name;
  final Member member;

  const ConstituencySearchResult({
    required this.name,
    required this.member,
  });
}

class SearchViewModel extends ChangeNotifier {
  static const int _minQueryLength = 2;
  static const int _billMinQueryLength = 3;
  static const int _memberLimit = 12;
  static const int _billLimit = 12;
  static const int _debateLimit = 20;
  static const int _councillorLimit = 20;
  static const int _constituencyLimit = 12;

  static final RegExp _nonWord = RegExp(r'[^a-z0-9]+');
  static final RegExp _multiSpace = RegExp(r'\s+');

  final ParliamentaryDataService _service;
  final Duration _debounceDuration;
  Timer? _debounce;

  bool _disposed = false;
  bool _isLoading = false;
  String _query = '';
  String? _error;
  SearchResults _results = const SearchResults();
  int _searchToken = 0;

  Future<List<Member>>? _membersFuture;
  List<_IndexedMember>? _memberIndex;
  Future<List<Councillor>>? _councillorsFuture;
  List<Councillor>? _cachedCouncillors;
  List<_IndexedCouncillor>? _councillorIndex;
  Future<List<Council>>? _councilsFuture;
  Map<String, Council>? _councilLookup;
  final Map<String, Future<CouncillorProfile?>> _profileCache = {};

  SearchViewModel(
    this._service, {
    Duration debounceDuration = const Duration(milliseconds: 300),
  }) : _debounceDuration = debounceDuration;

  bool get isLoading => _isLoading;
  String get query => _query;
  String? get error => _error;
  SearchResults get results => _results;

  bool get isQueryShort {
    final normalized = _normalize(_query);
    return normalized.isNotEmpty && normalized.length < _minQueryLength;
  }

  void updateQuery(String query) {
    _query = query;
    _debounce?.cancel();
    final normalized = _normalize(query);
    if (normalized.isEmpty) {
      _results = const SearchResults();
      _error = null;
      _isLoading = false;
      _safeNotify();
      return;
    }
    if (normalized.length < _minQueryLength) {
      _results = const SearchResults();
      _error = null;
      _isLoading = false;
      _safeNotify();
      return;
    }
    _isLoading = true;
    _error = null;
    _safeNotify();
    if (_debounceDuration == Duration.zero) {
      _startSearch(query);
    } else {
      _debounce = Timer(_debounceDuration, () => _startSearch(query));
    }
  }

  Future<void> searchNow(String query) async {
    _query = query;
    _debounce?.cancel();
    final normalized = _normalize(query);
    if (normalized.isEmpty || normalized.length < _minQueryLength) {
      _results = const SearchResults();
      _error = null;
      _isLoading = false;
      _safeNotify();
      return;
    }
    _isLoading = true;
    _error = null;
    _safeNotify();
    await _performSearch(query);
  }

  List<Councillor> councillorsForCouncil(String councilName) {
    final all = _cachedCouncillors ?? const <Councillor>[];
    if (all.isEmpty) return const [];
    final key = normaliseCouncilName(councilName);
    return [
      for (final c in all)
        if (normaliseCouncilName(c.council) == key) c,
    ];
  }

  /// Democracy Club photo/contact enrichment for a councillor, memoized for
  /// the life of this view model so repeated rebuilds (e.g. on every
  /// keystroke) don't re-hit the on-disk cache for the same person.
  Future<CouncillorProfile?> profileFor(Councillor councillor) {
    final key = '${councillor.council}|${councillor.ward}|${councillor.name}';
    return _profileCache.putIfAbsent(
      key,
      () => _service.fetchCouncillorProfile(councillor),
    );
  }

  void _startSearch(String query) {
    _performSearch(query);
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    final normalized = _normalize(trimmed);
    if (normalized.length < _minQueryLength) {
      _results = const SearchResults();
      _error = null;
      _isLoading = false;
      _safeNotify();
      return;
    }
    final token = ++_searchToken;
    final errors = <String>[];

    List<Member> members = const [];
    List<ConstituencySearchResult> constituencies = const [];
    List<CouncillorSearchResult> councillors = const [];
    List<BillSearchResult> bills = const [];
    List<DebateSearchResult> debates = const [];

    try {
      members = await _searchMembers(normalized);
    } catch (e) {
      errors.add('Members: ${e.toString()}');
    }

    try {
      constituencies = await _searchConstituencies(normalized);
    } catch (e) {
      errors.add('Constituencies: ${e.toString()}');
    }

    try {
      councillors = await _searchCouncillors(normalized);
    } catch (e) {
      errors.add('Councillors: ${e.toString()}');
    }

    try {
      bills = await _searchBills(trimmed);
    } catch (e) {
      errors.add('Bills: ${e.toString()}');
    }

    try {
      debates = await _searchDebates(trimmed);
    } catch (e) {
      errors.add('Debates: ${e.toString()}');
    }

    if (token != _searchToken) return;
    _results = SearchResults(
      members: members,
      councillors: councillors,
      bills: bills,
      debates: debates,
      constituencies: constituencies,
    );
    _error = errors.isEmpty ? null : errors.join('\n');
    _isLoading = false;
    _safeNotify();
  }

  Future<List<Member>> _searchMembers(String query) async {
    final index = await _loadMemberIndex();
    final matches = <_Scored<Member>>[];
    for (final entry in index) {
      final score = _score(entry.nameKey, query);
      if (score == null) continue;
      matches.add(
        _Scored(value: entry.member, score: score, sortKey: entry.member.name),
      );
    }
    matches.sort(_compareScored);
    return [
      for (final m in matches.take(_memberLimit)) m.value,
    ];
  }

  Future<List<ConstituencySearchResult>> _searchConstituencies(
    String query,
  ) async {
    final index = await _loadMemberIndex();
    final matches = <_Scored<ConstituencySearchResult>>[];
    for (final entry in index) {
      final constituency = entry.member.constituency;
      if (constituency.isEmpty) continue;
      final score = _score(entry.constituencyKey, query);
      if (score == null) continue;
      matches.add(
        _Scored(
          value: ConstituencySearchResult(
            name: constituency,
            member: entry.member,
          ),
          score: score,
          sortKey: constituency,
        ),
      );
    }
    matches.sort(_compareScored);
    return [
      for (final m in matches.take(_constituencyLimit)) m.value,
    ];
  }

  Future<List<CouncillorSearchResult>> _searchCouncillors(
    String query,
  ) async {
    if (query.length < _minQueryLength) return const [];
    final index = await _loadCouncillorIndex();
    final lookup = await _loadCouncilLookup();
    final matches = <_Scored<CouncillorSearchResult>>[];
    for (final entry in index) {
      final score = _bestScore(
        query,
        entry.nameKey,
        entry.wardKey,
        entry.councilKey,
      );
      if (score == null) continue;
      matches.add(
        _Scored(
          value: CouncillorSearchResult(
            councillor: entry.councillor,
            council: lookup[normaliseCouncilName(entry.councillor.council)],
          ),
          score: score,
          sortKey: entry.councillor.name,
        ),
      );
    }
    matches.sort(_compareScored);
    return [
      for (final m in matches.take(_councillorLimit)) m.value,
    ];
  }

  Future<List<BillSearchResult>> _searchBills(String query) async {
    if (_normalize(query).length < _billMinQueryLength) return const [];
    final raw = await _service.searchBills(query, take: _billLimit);
    final results = <BillSearchResult>[];
    for (final json in raw) {
      final bill = BillSearchResult.fromJson(json);
      if (bill.id == 0 || bill.title.isEmpty) continue;
      results.add(bill);
    }
    return results;
  }

  Future<List<DebateSearchResult>> _searchDebates(String query) async {
    final raw = await _service.searchCachedDebates(query, limit: _debateLimit);
    return raw
        .map((json) {
          final id = json['debateId'] as String? ?? '';
          final title = json['title'] as String? ?? '';
          final date = json['date'] as String? ?? '';
          if (id.isEmpty || title.isEmpty || date.isEmpty) return null;
          return DebateSearchResult(
            debateId: id,
            title: title,
            house: (json['house'] as String?) ?? '',
            date: date,
            section: json['section'] as String?,
          );
        })
        .whereType<DebateSearchResult>()
        .toList();
  }

  Future<List<_IndexedMember>> _loadMemberIndex() async {
    if (_memberIndex != null) return _memberIndex!;
    final members = await (_membersFuture ??= _service.getMembers());
    _memberIndex = [
      for (final m in members)
        _IndexedMember(
          member: m,
          nameKey: _normalize(m.name),
          constituencyKey: _normalize(m.constituency),
        ),
    ];
    return _memberIndex!;
  }

  Future<List<_IndexedCouncillor>> _loadCouncillorIndex() async {
    if (_councillorIndex != null) return _councillorIndex!;
    _cachedCouncillors ??=
        await (_councillorsFuture ??= _service.fetchCouncillors());
    _councillorIndex = [
      for (final c in _cachedCouncillors!)
        _IndexedCouncillor(
          councillor: c,
          nameKey: _normalize(c.name),
          wardKey: _normalize(c.ward),
          councilKey: _normalize(c.council),
        ),
    ];
    return _councillorIndex!;
  }

  Future<Map<String, Council>> _loadCouncilLookup() async {
    if (_councilLookup != null) return _councilLookup!;
    final councils = await (_councilsFuture ??= _service.fetchCouncils());
    _councilLookup = {
      for (final c in councils) normaliseCouncilName(c.name): c,
    };
    return _councilLookup!;
  }

  int? _score(String value, String query) {
    final idx = value.indexOf(query);
    return idx == -1 ? null : idx;
  }

  int? _bestScore(String query, String a, String b, String c) {
    int? best;
    for (final value in [a, b, c]) {
      final idx = value.indexOf(query);
      if (idx == -1) continue;
      if (best == null || idx < best) best = idx;
    }
    return best;
  }

  int _compareScored<T>(_Scored<T> a, _Scored<T> b) {
    final byScore = a.score.compareTo(b.score);
    if (byScore != 0) return byScore;
    return a.sortKey.compareTo(b.sortKey);
  }

  String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(_nonWord, ' ')
        .replaceAll(_multiSpace, ' ')
        .trim();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    super.dispose();
  }
}

class _IndexedMember {
  final Member member;
  final String nameKey;
  final String constituencyKey;

  const _IndexedMember({
    required this.member,
    required this.nameKey,
    required this.constituencyKey,
  });
}

class _IndexedCouncillor {
  final Councillor councillor;
  final String nameKey;
  final String wardKey;
  final String councilKey;

  const _IndexedCouncillor({
    required this.councillor,
    required this.nameKey,
    required this.wardKey,
    required this.councilKey,
  });
}

class _Scored<T> {
  final T value;
  final int score;
  final String sortKey;

  const _Scored({
    required this.value,
    required this.score,
    required this.sortKey,
  });
}
