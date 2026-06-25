import 'package:flutter/foundation.dart';

import '../models/debate.dart';
import '../models/member.dart';
import '../models/speech.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/member_lookup_index.dart';
import '../utils/parliament_live.dart' as live_url;
import '../utils/party_tokens.dart';
import '../utils/speech_normaliser.dart';
import '../utils/speech_timecodes.dart';

/// The launch URL (always) and optional inline player URL for embedding a
/// parliamentlive.tv video for the current transcript.
class ParliamentLiveTarget {
  final Uri launchUrl;
  final Uri? inlineUrl;
  final String title;
  final bool hasDirectEvent;

  const ParliamentLiveTarget({
    required this.launchUrl,
    required this.inlineUrl,
    required this.title,
    required this.hasDirectEvent,
  });
}

/// Represents a unique speaker and the index of their first speech in the
/// current transcript list (used for Jump-to-Member scrolling).
class SpeakerEntry {
  final String name;
  final int? memberId;
  final int firstSpeechIndex;

  const SpeakerEntry({
    required this.name,
    required this.memberId,
    required this.firstSpeechIndex,
  });
}

/// View-model for the transcript screen.
///
/// Loads speeches for a given sitting date, and exposes:
///  - the full ordered list of [Speech] objects for the SliverList.
///  - a deduplicated [speakers] list for the Jump-to-Member drawer.
///  - per-member profile data (portrait URL, party) from the local members DB.
class TranscriptViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;
  final String date;

  /// When set, only speeches belonging to this root debate are shown.
  final String? initialDebateId;

  TranscriptViewModel(this._service,
      {required this.date, this.initialDebateId});

  List<Speech> _speeches = [];
  final Map<int, Member> _memberCache = {};
  final Map<String, Member> _speechMemberCache = {};
  List<SpeakerEntry> _speakers = [];
  List<TimeAnchor> _timeAnchors = const [];
  int? _sittingStartSeconds;
  String? _primaryDebateTitle;

  /// "Commons", "Lords", "Commons & Lords", or null if unknown.
  String? _primaryHouse;
  String? _primarySection;
  bool _isLoading = false;
  String? _error;
  bool _isDisposed = false;

  List<Speech> get speeches => List.unmodifiable(_speeches);
  Map<int, Member> get memberCache => Map.unmodifiable(_memberCache);
  List<SpeakerEntry> get speakers => List.unmodifiable(_speakers);
  String? get primaryDebateTitle => _primaryDebateTitle;
  String? get primaryHouse => _primaryHouse;
  String? get primarySection => _primarySection;
  String? get sittingStartTimeLabel => _sittingStartSeconds != null
      ? formatSecondsAsClockMinute(_sittingStartSeconds!)
      : null;
  String? get sittingStartTimecode => _sittingStartSeconds != null
      ? formatSecondsAsTimecode(_sittingStartSeconds!)
      : null;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Loads speeches for [date] from the local cache or network.
  Future<void> loadSpeeches() async {
    _isLoading = true;
    _error = null;
    if (!_isDisposed) notifyListeners();

    try {
      final allRawSpeeches = await _service.getSpeeches(date);
      final debates = await _service.getDebatesForDate(date);
      final rootIds = debates.map((d) => d.id).toSet();

      _sittingStartSeconds = _findSittingStartSeconds(allRawSpeeches);
      final rawSpeeches = initialDebateId != null
          ? _speechesForRootDebate(allRawSpeeches, rootIds, initialDebateId!)
          : allRawSpeeches;

      final normalised = normaliseSpeeches(raw: rawSpeeches, date: date);
      _speeches = normalised.speeches;
      _timeAnchors = normalised.anchors;
      _primaryDebateTitle = _computePrimaryDebateTitle(_speeches);
      _primaryHouse = _computePrimaryHouseFromDebates(debates);
      _primarySection = _computePrimarySectionFromDebates(debates);
      await _loadMemberProfiles();
      _buildSpeakersIndex();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      if (!_isDisposed) notifyListeners();
    }
  }

  /// Returns the index of the first speech belonging to [debateId], or null.
  int? firstIndexForDebate(String debateId) {
    for (int i = 0; i < _speeches.length; i++) {
      if (_speeches[i].debateId == debateId) return i;
    }
    return null;
  }

  /// Returns the [Member] associated with [memberId], or `null` if unknown.
  Member? memberFor(int? memberId) {
    if (memberId == null) return null;
    return _memberCache[memberId];
  }

  /// Returns a member profile for a speech, including name-match fallback.
  Member? memberForSpeech(Speech speech) {
    if (speech.memberId != null) {
      return _memberCache[speech.memberId!];
    }
    return _speechMemberCache[speech.id];
  }

  /// Returns an interpolated `HH:MM` time estimate for transcript position.
  ///
  /// [position] is typically the top visible speech index, optionally including
  /// a fractional part within that item (e.g. `12.4`).
  String? estimatedTimeAtPosition(double position) {
    final seconds = interpolateSecondsAtPosition(_timeAnchors, position);
    if (seconds == null) return null;
    return formatSecondsAsClockMinute(seconds);
  }

  /// Returns an interpolated `HH:MM` estimate for a specific speech index.
  String? estimatedTimeForSpeechIndex(int index) {
    return estimatedTimeAtPosition(index.toDouble());
  }

  /// Best available Hansard timecode (`HH:MM:SS`) for deep-linking the
  /// currently loaded transcript to parliamentlive.tv.
  ///
  /// Prefers explicit `Speech.timecode` values from Hansard rows, then falls
  /// back to timestamp-derived anchors when explicit per-speech timecodes are
  /// absent.
  String? get parliamentLiveStartTimecode {
    for (final speech in _speeches) {
      final raw = speech.timecode;
      if (raw == null || raw.trim().isEmpty) continue;
      final seconds = parseTimecodeToSeconds(raw);
      if (seconds != null) {
        return formatSecondsAsTimecode(seconds);
      }
    }

    final anchoredSeconds = interpolateSecondsAtPosition(_timeAnchors, 0);
    if (anchoredSeconds == null) return null;
    return formatSecondsAsTimecode(anchoredSeconds);
  }

  /// Debate-specific Hansard timecode (`HH:MM:SS`) for parliamentlive deep-linking.
  ///
  /// When [debateTitle] is provided, this scopes lookup to that debate's first
  /// matching speech in the loaded transcript so chamber-wide videos shared by
  /// multiple debates start at the right point.
  String? parliamentLiveStartTimecodeForDebateTitle(String? debateTitle) {
    final target = debateTitle?.trim();
    if (target == null || target.isEmpty) return parliamentLiveStartTimecode;

    int? firstMatchIndex;
    for (int i = 0; i < _speeches.length; i++) {
      final speech = _speeches[i];
      if (speech.debateTitle.trim() != target) continue;
      firstMatchIndex ??= i;
      final raw = speech.timecode;
      if (raw == null || raw.trim().isEmpty) continue;
      final seconds = parseTimecodeToSeconds(raw);
      if (seconds != null) {
        return formatSecondsAsTimecode(seconds);
      }
    }

    if (firstMatchIndex == null) return parliamentLiveStartTimecode;
    final anchoredSeconds =
        interpolateSecondsAtPosition(_timeAnchors, firstMatchIndex.toDouble());
    if (anchoredSeconds == null) return null;
    return formatSecondsAsTimecode(anchoredSeconds);
  }

  /// Human-readable HH:MM label for the parliamentlive deep-link start time
  /// of [debateTitle]. Returns `null` when no anchored time is available.
  String? parliamentLiveStartLabelForDebateTitle(String? debateTitle) {
    final timecode = parliamentLiveStartTimecodeForDebateTitle(debateTitle);
    if (timecode == null) return null;
    final seconds = parseTimecodeToSeconds(timecode);
    if (seconds == null) return null;
    return formatSecondsAsClockMinute(seconds);
  }

  Future<ParliamentLiveTarget>? _liveTargetFuture;
  String? _liveTargetCacheKey;

  /// Resolves a parliamentlive.tv video for the loaded debate. Memoized for
  /// the lifetime of this view-model so repeated rebuilds don't refetch.
  Future<ParliamentLiveTarget> parliamentLiveTarget() {
    final debateTitle = (primaryDebateTitle ?? '').trim();
    final seekTimecode =
        parliamentLiveStartTimecodeForDebateTitle(debateTitle) ??
            sittingStartTimecode;
    final key =
        '$date|$debateTitle|${primaryHouse ?? ''}|${seekTimecode ?? ''}';
    if (_liveTargetFuture != null && _liveTargetCacheKey == key) {
      return _liveTargetFuture!;
    }
    _liveTargetCacheKey = key;
    _liveTargetFuture = _resolveParliamentLiveTarget(
      debateTitle: debateTitle,
      seekTimecode: seekTimecode,
    );
    return _liveTargetFuture!;
  }

  Future<ParliamentLiveTarget> _resolveParliamentLiveTarget({
    required String debateTitle,
    required String? seekTimecode,
  }) async {
    final event = await _service.findLiveEventForDebate(
      date: date,
      debateTitle: debateTitle,
      house: primaryHouse,
    );
    if (event != null) {
      final launchUrl = live_url.parliamentLiveEventUrl(
        event.guid,
        timecode: seekTimecode,
      );
      return ParliamentLiveTarget(
        launchUrl: launchUrl,
        inlineUrl: _inlineParliamentLiveUrl(launchUrl),
        title: event.title,
        hasDirectEvent: true,
      );
    }
    final launchUrl = live_url.parliamentLiveSearchUrl(
      date: date,
      house: primaryHouse,
    );
    return ParliamentLiveTarget(
      launchUrl: launchUrl,
      inlineUrl: null,
      title: date,
      hasDirectEvent: false,
    );
  }

  Uri? _inlineParliamentLiveUrl(Uri launchUrl) {
    if (!_supportsInlineWebView) return null;
    final guid = _eventGuidFromEventUrl(launchUrl);
    if (guid == null) return null;
    // Always embed the standalone player so the tray shows just the video and
    // its media controls — never the scrollable event page. Any `?in=` seek is
    // forwarded (both as a player query and via the parent URL) so the video
    // still starts at the debate's timecode where the player honours it.
    final timecode = launchUrl.queryParameters['in'];
    return live_url.parliamentLivePlayerUrl(
      guid,
      parentUrl: launchUrl,
      timecode: timecode,
    );
  }

  static bool get _supportsInlineWebView {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  static final RegExp _guidPattern = RegExp(
    r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
  );

  static String? _eventGuidFromEventUrl(Uri url) {
    if (url.host.toLowerCase() != 'parliamentlive.tv') return null;
    final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.length < 3) return null;
    if (segments[0].toLowerCase() != 'event' ||
        segments[1].toLowerCase() != 'index') {
      return null;
    }
    final guid = segments[2].toLowerCase();
    if (!_guidPattern.hasMatch(guid)) return null;
    return guid;
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// Builds the sorted [_speakers] list from [_speeches].
  void _buildSpeakersIndex() {
    final seen = <String>{};
    final result = <SpeakerEntry>[];

    for (int i = 0; i < _speeches.length; i++) {
      final s = _speeches[i];
      final key = s.memberName.isNotEmpty ? s.memberName : s.attributedTo;
      if (key.isNotEmpty && !seen.contains(key)) {
        seen.add(key);
        final matchedMemberId = s.memberId ?? _speechMemberCache[s.id]?.id;
        result.add(
          SpeakerEntry(
            name: key,
            memberId: matchedMemberId,
            firstSpeechIndex: i,
          ),
        );
      }
    }

    // Sort alphabetically for the drawer list.
    result.sort((a, b) => a.name.compareTo(b.name));
    _speakers = result;
  }

  /// Pre-fetches [Member] records for all member IDs in [_speeches].
  Future<void> _loadMemberProfiles() async {
    final ids = _speeches.map((s) => s.memberId).whereType<int>().toSet();

    for (final id in ids) {
      if (!_memberCache.containsKey(id)) {
        var member = await _service.getMemberById(id);
        member ??= await _service.fetchAndCacheMemberById(id);
        if (member != null) {
          _memberCache[id] = member;
        }
      }
    }

    final allMembers = await _service.getMembers();
    if (allMembers.isEmpty) return;
    final lookup = MemberLookupIndex(allMembers);
    final aliasKeys = <String>{};
    final aliasUpdates = <String, int>{};

    for (final speech in _speeches) {
      aliasKeys.addAll(_aliasKeysForSpeech(speech));
      if (speech.memberId != null) {
        final direct = _memberCache[speech.memberId!] ??
            lookup.memberById(speech.memberId!);
        if (direct != null) {
          for (final key in _aliasKeysForSpeech(speech)) {
            aliasUpdates[key] = direct.id;
          }
        }
      }
    }

    // Resolve "in the Chair" procedural speeches by name matching.
    for (final speech in _speeches) {
      final chairName = speech.inChairName;
      if (chairName == null) continue;
      final match =
          lookup.matchExact([chairName]) ?? lookup.matchFuzzy([chairName]);
      if (match != null) {
        _speechMemberCache[speech.id] = match;
        _memberCache[match.id] = match;
      }
    }

    final cachedAliases = await _service.getSpeakerAliasMemberIds(aliasKeys);

    for (final speech in _speeches) {
      final hasDirectMatch =
          speech.memberId != null && _memberCache.containsKey(speech.memberId!);
      if (hasDirectMatch || !speech.hasNamedSpeaker) continue;

      final partyHint = _partyHintForSpeech(speech);
      final keysForSpeech = _aliasKeysForSpeech(speech);

      Member? match;

      for (final key in keysForSpeech) {
        final memberId = cachedAliases[key];
        if (memberId == null) continue;
        match = _memberCache[memberId] ?? lookup.memberById(memberId);
        if (match != null) break;
      }

      match ??= lookup.matchExact(
        _personNameCandidatesForSpeech(speech),
        partyHint: partyHint,
      );

      match ??= lookup.matchFuzzy(
        _nameCandidatesForSpeech(speech),
        partyHint: partyHint,
      );

      if (match == null) continue;
      _speechMemberCache[speech.id] = match;
      _memberCache[match.id] = match;
      for (final key in keysForSpeech) {
        aliasUpdates[key] = match.id;
      }
    }

    await _service.saveSpeakerAliasMemberIds(aliasUpdates);
  }

  String _computePrimaryDebateTitle(List<Speech> speeches) {
    final counts = <String, int>{};
    final firstSeen = <String, int>{};
    int seq = 0;
    for (final speech in speeches) {
      final title = speech.debateTitle.trim();
      if (title.isEmpty) continue;
      counts[title] = (counts[title] ?? 0) + 1;
      firstSeen.putIfAbsent(title, () => seq++);
    }
    if (counts.isEmpty) return '';
    final sorted = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        if (byCount != 0) return byCount;
        return (firstSeen[a.key] ?? 0).compareTo(firstSeen[b.key] ?? 0);
      });
    return sorted.first.key;
  }

  /// Filters [speeches] (in order) to only those belonging to [rootDebateId].
  ///
  /// Speeches are assigned to root debates by walking in order and tracking
  /// which root debate was most recently seen — sub-section speeches (whose
  /// debateId is not in [rootIds]) inherit the previous root debate.
  static List<Speech> _speechesForRootDebate(
    List<Speech> speeches,
    Set<String> rootIds,
    String rootDebateId,
  ) {
    final result = <Speech>[];
    String? currentRoot;
    for (final speech in speeches) {
      if (rootIds.contains(speech.debateId)) {
        currentRoot = speech.debateId;
      }
      if (currentRoot == rootDebateId) {
        result.add(speech);
      }
    }
    return result;
  }

  String? _computePrimaryHouseFromDebates(List<Debate> debates) {
    if (debates.isEmpty) return null;
    final houseByDebateId = {for (final d in debates) d.id: d.house};

    // Count speeches per house to find the dominant one.
    final houseCounts = <String, int>{};
    for (final speech in _speeches) {
      final house = houseByDebateId[speech.debateId];
      if (house != null && house.isNotEmpty) {
        houseCounts[house] = (houseCounts[house] ?? 0) + 1;
      }
    }

    if (houseCounts.isEmpty) {
      // Fall back to distinct house values from debates.
      final houses = debates.map((d) => d.house).toSet();
      return houses.length == 1 ? houses.first : null;
    }
    if (houseCounts.length == 1) return houseCounts.keys.first;

    final total = houseCounts.values.fold(0, (a, b) => a + b);
    for (final entry in houseCounts.entries) {
      if (entry.value / total > 0.7) return entry.key;
    }
    return 'Commons & Lords';
  }

  String? _computePrimarySectionFromDebates(List<Debate> debates) {
    if (debates.isEmpty) return null;
    final sectionByDebateId = {for (final d in debates) d.id: d.section};

    if (initialDebateId != null) {
      final direct = sectionByDebateId[initialDebateId!];
      return (direct == null || direct.trim().isEmpty) ? null : direct;
    }

    final rootIds = debates.map((d) => d.id).toSet();
    final sectionCounts = <String, int>{};
    String? currentRoot;

    for (final speech in _speeches) {
      if (rootIds.contains(speech.debateId)) {
        currentRoot = speech.debateId;
      }
      final section = sectionByDebateId[currentRoot ?? speech.debateId];
      if (section != null && section.trim().isNotEmpty) {
        sectionCounts[section] = (sectionCounts[section] ?? 0) + 1;
      }
    }

    if (sectionCounts.isEmpty) {
      final sections = debates
          .map((d) => d.section)
          .whereType<String>()
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toSet();
      return sections.length == 1 ? sections.first : null;
    }

    if (sectionCounts.length == 1) return sectionCounts.keys.first;
    final total = sectionCounts.values.fold(0, (a, b) => a + b);
    for (final entry in sectionCounts.entries) {
      if (entry.value / total > 0.7) return entry.key;
    }
    return null;
  }

  List<String> _nameCandidatesForSpeech(Speech speech) {
    final candidates = <String>[];
    final directName = speech.memberName.trim();
    if (directName.isNotEmpty && !_looksLikeOfficeTitle(directName)) {
      candidates.add(directName);
    }

    final attribution = speech.attributedTo.trim();
    if (attribution.isNotEmpty) {
      final lead = attribution.split('(').first.trim();
      if (lead.isNotEmpty && !_looksLikeOfficeTitle(lead)) candidates.add(lead);
      for (final match in RegExp(r'\(([^)]+)\)').allMatches(attribution)) {
        final bracketed = (match.group(1) ?? '').trim();
        if (bracketed.isEmpty) continue;
        if (canonicalPartyToken(bracketed) != null) continue;
        candidates.add(bracketed);
      }
    }
    return candidates.toSet().toList();
  }

  List<String> _personNameCandidatesForSpeech(Speech speech) {
    final candidates = <String>[];
    final directName = speech.memberName.trim();
    if (directName.isNotEmpty && !_looksLikeOfficeTitle(directName)) {
      candidates.add(directName);
    }

    final attribution = speech.attributedTo.trim();
    for (final match in RegExp(r'\(([^)]+)\)').allMatches(attribution)) {
      final bracketed = (match.group(1) ?? '').trim();
      if (bracketed.isEmpty) continue;
      if (canonicalPartyToken(bracketed) != null) continue;
      candidates.add(bracketed);
    }

    final lead = attribution.split('(').first.trim();
    if (lead.isNotEmpty && !_looksLikeOfficeTitle(lead)) {
      candidates.add(lead);
    }
    return candidates.toSet().toList();
  }

  List<String> _aliasKeysForSpeech(Speech speech) {
    final keys = <String>{};
    final attribution = speech.attributedTo.trim();
    if (attribution.isNotEmpty) {
      keys.add('attr:${_normalizeAliasKey(attribution)}');
      final lead = attribution.split('(').first.trim();
      if (lead.isNotEmpty && _looksLikeOfficeTitle(lead)) {
        keys.add('office:$date:${_normalizeAliasKey(lead)}');
      }
    }

    final name = speech.memberName.trim();
    if (name.isNotEmpty) {
      keys.add('name:${_normalizeAliasKey(name)}');
    }
    return keys.toList();
  }

  String _normalizeAliasKey(String raw) {
    return raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  bool _looksLikeOfficeTitle(String value) {
    final v = value.toLowerCase().trim();
    if (v.startsWith('the ')) return true;
    return v.contains('secretary') ||
        v.contains('minister') ||
        v.contains('chancellor') ||
        v.contains('whip') ||
        v.contains('spokesperson') ||
        v.contains('attorney') ||
        v.contains('advocate') ||
        v.contains('commissioner') ||
        v.contains('speaker') ||
        v.contains('captain of') ||
        v.contains('comptroller') ||
        v.contains('adjutant') ||
        v.contains('treasurer of');
  }

  String? _partyHintForSpeech(Speech speech) {
    for (final match
        in RegExp(r'\(([^)]+)\)').allMatches(speech.attributedTo)) {
      final candidate = (match.group(1) ?? '').trim();
      final token = canonicalPartyToken(candidate);
      if (token != null) return token;
    }
    return null;
  }

  int? _findSittingStartSeconds(List<Speech> speeches) {
    for (final speech in speeches) {
      if (!speech.isSittingStartAnnouncement) continue;
      final seconds = speech.sittingStartSeconds;
      if (seconds != null) return seconds;
    }
    return null;
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
