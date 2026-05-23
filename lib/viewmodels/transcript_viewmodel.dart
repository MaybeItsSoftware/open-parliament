import 'package:flutter/foundation.dart';

import '../models/debate.dart';
import '../models/member.dart';
import '../models/speech.dart';
import '../services/parliamentary_data_service.dart';

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
  final List<_TimeAnchor> _timeAnchors = [];
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
      ? _formatTimeToNearestMinute(_sittingStartSeconds!)
      : null;
  String? get sittingStartTimecode => _sittingStartSeconds != null
      ? _formatTimeToSecond(_sittingStartSeconds!)
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

      _speeches = _normaliseSpeeches(rawSpeeches);
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

  /// Returns an interpolated `HH:MM:SS` time estimate for transcript position.
  ///
  /// [position] is typically the top visible speech index, optionally including
  /// a fractional part within that item (e.g. `12.4`).
  String? estimatedTimeAtPosition(double position) {
    final seconds = _estimatedSecondsAtPosition(position);
    if (seconds == null) return null;
    return _formatTimeToNearestMinute(seconds);
  }

  /// Returns an interpolated `HH:MM:SS` estimate for a specific speech index.
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
      final seconds = _parseTimeToSeconds(raw);
      if (seconds != null) {
        return _formatTimeToSecond(seconds);
      }
    }

    final anchoredSeconds = _estimatedSecondsAtPosition(0);
    if (anchoredSeconds == null) return null;
    return _formatTimeToSecond(anchoredSeconds);
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
      final seconds = _parseTimeToSeconds(raw);
      if (seconds != null) {
        return _formatTimeToSecond(seconds);
      }
    }

    if (firstMatchIndex == null) return parliamentLiveStartTimecode;
    final anchoredSeconds =
        _estimatedSecondsAtPosition(firstMatchIndex.toDouble());
    if (anchoredSeconds == null) return null;
    return _formatTimeToSecond(anchoredSeconds);
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
    final lookup = _MemberLookupIndex(allMembers);
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

  List<Speech> _normaliseSpeeches(List<Speech> raw) {
    _timeAnchors.clear();
    final result = <Speech>[];
    int displayIndex = 0;
    String? lastProceduralNormalized;
    final redundantDatePhrases = _redundantDatePhrases();

    int i = 0;
    while (i < raw.length) {
      final speech = raw[i];
      if (speech.isTimestamp) {
        final seconds =
            _parseTimeToSeconds(speech.timecode ?? speech.speechText);
        if (seconds != null) {
          if (_timeAnchors.isNotEmpty &&
              _timeAnchors.last.index == displayIndex) {
            _timeAnchors[_timeAnchors.length - 1] = _TimeAnchor(
              index: displayIndex.toDouble(),
              secondsSinceMidnight: seconds,
            );
          } else {
            _timeAnchors.add(
              _TimeAnchor(
                index: displayIndex.toDouble(),
                secondsSinceMidnight: seconds,
              ),
            );
          }
        }
        i++;
        continue;
      }

      if (speech.isDateHeading) {
        i++;
        continue;
      }

      if (speech.isProceduralText) {
        final normalized = speech.speechText.trim().toLowerCase();
        if (normalized.isEmpty) {
          i++;
          continue;
        }
        if (redundantDatePhrases.contains(_normalizeForCompare(normalized))) {
          i++;
          continue;
        }
        // Reduce repetitive procedural headings often repeated in source blocks.
        if (normalized == lastProceduralNormalized) {
          i++;
          continue;
        }
        lastProceduralNormalized = normalized;

        // "The House met at 9.30 am" — harvest the start time as a free
        // anchor for timestamp interpolation, then drop the speech.
        if (speech.isSittingStartAnnouncement) {
          final seconds = speech.sittingStartSeconds;
          if (seconds != null) {
            _timeAnchors.add(
              _TimeAnchor(
                index: displayIndex.toDouble(),
                secondsSinceMidnight: seconds,
              ),
            );
          }
          i++;
          continue;
        }

        final mergedCommittee = _mergeCommitteeMembershipLines(
          raw: raw,
          startIndex: i,
          redundantDatePhrases: redundantDatePhrases,
        );
        if (mergedCommittee != null) {
          result.add(mergedCommittee.speech);
          displayIndex++;
          i = mergedCommittee.nextIndex;
          continue;
        }
      } else {
        lastProceduralNormalized = null;
      }

      result.add(speech);
      displayIndex++;
      i++;
    }

    return result;
  }

  _MergedProceduralBlock? _mergeCommitteeMembershipLines({
    required List<Speech> raw,
    required int startIndex,
    required Set<String> redundantDatePhrases,
  }) {
    final head = raw[startIndex];
    if (!_isCommitteeMembershipHeading(head.speechText)) {
      return null;
    }

    final lines = <String>[head.speechText.trim()];
    int i = startIndex + 1;
    while (i < raw.length) {
      final next = raw[i];
      if (next.isTimestamp) break;
      // Roster lines often have attribution set, so check for the † dagger
      // symbol as a reliable marker rather than relying on isProceduralText.
      final isRosterLine = next.speechText.trimLeft().startsWith('†');
      if (!next.isProceduralText && !isRosterLine) break;
      final text = next.speechText.trim();
      if (text.isEmpty) {
        i++;
        continue;
      }

      final normalized = _normalizeForCompare(text);
      if (redundantDatePhrases.contains(normalized)) break;
      if (_isCommitteeMembershipHeading(text)) {
        i++;
        continue;
      }

      lines.add(_formatCommitteeRosterLine(text));
      final lower = text.toLowerCase();
      if (lower.contains('attended the committee')) {
        i++;
        break;
      }

      if (lines.length >= 40) {
        i++;
        break;
      }

      i++;
    }

    if (lines.length == 1) {
      return _MergedProceduralBlock(speech: head, nextIndex: startIndex + 1);
    }

    return _MergedProceduralBlock(
      speech: Speech(
        id: head.id,
        debateId: head.debateId,
        debateTitle: head.debateTitle,
        itemType: head.itemType,
        memberId: head.memberId,
        memberName: head.memberName,
        attributedTo: head.attributedTo,
        speechText: lines.join('\n'),
        timecode: head.timecode,
        orderIndex: head.orderIndex,
      ),
      nextIndex: i,
    );
  }

  bool _isCommitteeMembershipHeading(String text) {
    return text
        .toLowerCase()
        .contains('the committee consisted of the following members:');
  }

  String _formatCommitteeRosterLine(String text) {
    return text.replaceFirst(RegExp(r'^\s*†\s*'), '• ');
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

  Set<String> _redundantDatePhrases() {
    final parsedDate = DateTime.tryParse(date);
    if (parsedDate == null) return const <String>{};

    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    final withComma =
        '${weekdays[parsedDate.weekday - 1]}, ${parsedDate.day} ${months[parsedDate.month - 1]} ${parsedDate.year}';
    final withoutComma =
        '${weekdays[parsedDate.weekday - 1]} ${parsedDate.day} ${months[parsedDate.month - 1]} ${parsedDate.year}';

    return {
      _normalizeForCompare(withComma),
      _normalizeForCompare(withoutComma),
    };
  }

  String _normalizeForCompare(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[,]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
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
        if (_canonicalPartyToken(bracketed) != null) continue;
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
      if (_canonicalPartyToken(bracketed) != null) continue;
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
      final token = _canonicalPartyToken(candidate);
      if (token != null) return token;
    }
    return null;
  }

  String? _canonicalPartyToken(String value) {
    final raw = value.toLowerCase().trim();
    final norm = raw.replaceAll(RegExp(r'[^a-z]'), '');
    if (norm.isEmpty) return null;

    if (norm == 'lab' ||
        norm == 'labour' ||
        norm == 'labourcooperative' ||
        norm == 'labcoop' ||
        raw.contains('lab co-op')) {
      return 'labour';
    }
    if (norm == 'con' ||
        norm == 'conservative' ||
        norm == 'conservativeparty') {
      return 'conservative';
    }
    if (norm == 'ld' ||
        norm == 'libdem' ||
        norm == 'liberaldemocrat' ||
        norm == 'liberaldemocrats' ||
        raw.contains('lib dem')) {
      return 'libdem';
    }
    if (norm == 'snp' || norm == 'scottishnationalparty') return 'snp';
    if (norm == 'green' || raw.contains('green party')) return 'green';
    if (norm == 'plaidcymru') return 'plaidcymru';
    if (norm == 'sinnfein') return 'sinnfein';
    if (norm == 'dup' || norm == 'democraticunionistparty') return 'dup';
    if (norm == 'uup' || norm == 'ulsterunionistparty') return 'uup';
    if (norm == 'alliance' || norm == 'allianceparty') return 'alliance';
    if (norm == 'cb' || norm == 'crossbench' || raw.contains('crossbench')) {
      return 'crossbench';
    }
    if (norm == 'nonaffiliated' || norm == 'independent') return 'independent';
    if (norm == 'reform' || norm == 'reformuk') return 'reform';
    return null;
  }

  int? _parseTimeToSeconds(String raw) {
    final parts = raw.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = parts.length == 3 ? int.tryParse(parts[2]) : 0;
    if (h == null || m == null || s == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) return null;
    return (h * 3600) + (m * 60) + s;
  }

  int? _estimatedSecondsAtPosition(double position) {
    if (_timeAnchors.isEmpty) return null;

    final first = _timeAnchors.first;
    final last = _timeAnchors.last;

    if (position <= first.index) {
      return first.secondsSinceMidnight;
    }

    if (position >= last.index) {
      return last.secondsSinceMidnight;
    }

    _TimeAnchor? previous;
    _TimeAnchor? next;
    for (final anchor in _timeAnchors) {
      if (anchor.index <= position) previous = anchor;
      if (anchor.index >= position) {
        next = anchor;
        break;
      }
    }

    if (previous == null && next == null) return null;
    if (previous == null) return next!.secondsSinceMidnight;
    if (next == null) return previous.secondsSinceMidnight;
    if (next.index == previous.index) return previous.secondsSinceMidnight;

    final ratio = (position - previous.index) / (next.index - previous.index);
    return previous.secondsSinceMidnight +
        ((next.secondsSinceMidnight - previous.secondsSinceMidnight) * ratio)
            .round();
  }

  int? _findSittingStartSeconds(List<Speech> speeches) {
    for (final speech in speeches) {
      if (!speech.isSittingStartAnnouncement) continue;
      final seconds = speech.sittingStartSeconds;
      if (seconds != null) return seconds;
    }
    return null;
  }

  String _formatTimeToNearestMinute(int secondsSinceMidnight) {
    final roundedMinutes = ((secondsSinceMidnight + 30) ~/ 60) % (24 * 60);
    final h = (roundedMinutes ~/ 60).toString().padLeft(2, '0');
    final m = (roundedMinutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatTimeToSecond(int secondsSinceMidnight) {
    final normalized = secondsSinceMidnight % (24 * 60 * 60);
    final h = (normalized ~/ 3600).toString().padLeft(2, '0');
    final m = ((normalized % 3600) ~/ 60).toString().padLeft(2, '0');
    final s = (normalized % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

class _TimeAnchor {
  final double index;
  final int secondsSinceMidnight;

  const _TimeAnchor({
    required this.index,
    required this.secondsSinceMidnight,
  });
}

class _MergedProceduralBlock {
  final Speech speech;
  final int nextIndex;

  const _MergedProceduralBlock({
    required this.speech,
    required this.nextIndex,
  });
}

class _MemberLookupIndex {
  final List<_MemberCandidate> _candidates;
  final Map<String, List<_MemberCandidate>> _exactByNormalizedName;
  final Map<int, _MemberCandidate> _byId;

  _MemberLookupIndex(List<Member> members)
      : _candidates = members.map(_MemberCandidate.fromMember).toList(),
        _exactByNormalizedName = {},
        _byId = {} {
    for (final candidate in _candidates) {
      _byId[candidate.member.id] = candidate;
      _exactByNormalizedName
          .putIfAbsent(candidate.normalizedName, () => <_MemberCandidate>[])
          .add(candidate);
    }
  }

  Member? memberById(int memberId) => _byId[memberId]?.member;

  Member? matchExact(List<String> nameCandidates, {String? partyHint}) {
    for (final raw in nameCandidates) {
      final normalized = _MemberCandidate.normalizeName(raw);
      if (normalized.isEmpty) continue;
      final exactMatches = _exactByNormalizedName[normalized];
      if (exactMatches != null && exactMatches.isNotEmpty) {
        return _pickByParty(exactMatches, partyHint).member;
      }
    }
    return null;
  }

  Member? matchFuzzy(List<String> nameCandidates, {String? partyHint}) {
    _MemberCandidate? best;
    double bestScore = 0;
    for (final raw in nameCandidates) {
      final probe = _MemberCandidate.normalizeName(raw);
      if (probe.isEmpty) continue;
      final probeTokens = probe.split(' ').where((t) => t.isNotEmpty).toSet();
      if (probeTokens.isEmpty) continue;

      for (final candidate in _candidates) {
        final score = _tokenOverlap(probeTokens, candidate.tokens);
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }
    }

    if (best == null || bestScore < 0.67) return null;
    // Very high confidence match — return regardless of party hint.
    if (bestScore >= 0.9) return best.member;
    if (partyHint == null || best.partyToken == null) return best.member;
    if (partyHint == best.partyToken) return best.member;
    return null;
  }

  _MemberCandidate _pickByParty(List<_MemberCandidate> options, String? party) {
    if (party == null) return options.first;
    for (final option in options) {
      if (option.partyToken == party) return option;
    }
    return options.first;
  }

  double _tokenOverlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length.toDouble();
    return intersection / a.length;
  }
}

class _MemberCandidate {
  final Member member;
  final String normalizedName;
  final Set<String> tokens;
  final String? partyToken;

  _MemberCandidate({
    required this.member,
    required this.normalizedName,
    required this.tokens,
    required this.partyToken,
  });

  factory _MemberCandidate.fromMember(Member member) {
    final normalized = normalizeName(member.name);
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toSet();
    return _MemberCandidate(
      member: member,
      normalizedName: normalized,
      tokens: tokens,
      partyToken: _normalizeParty(
        member.partyAbbreviation.isNotEmpty
            ? member.partyAbbreviation
            : member.party,
      ),
    );
  }

  static const _honorifics = {
    'rt',
    'hon',
    'right',
    'sir',
    'dame',
    'dr',
    'mr',
    'mrs',
    'ms',
    'prof',
    'lord',
    'lady',
    'baron',
    'baroness',
    'viscount',
    'viscountess',
    'earl',
    'countess',
    'duke',
    'duchess',
  };

  static String normalizeName(String raw) {
    final base = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final stripped = base
        .split(' ')
        .where((t) => t.isNotEmpty && !_honorifics.contains(t))
        .join(' ');
    return stripped.isNotEmpty ? stripped : base;
  }

  static String? _normalizeParty(String raw) {
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (normalized.isEmpty) return null;
    if (normalized == 'lab' ||
        normalized == 'labour' ||
        normalized == 'labourcooperative' ||
        normalized == 'labcoop') {
      return 'labour';
    }
    if (normalized == 'con' || normalized == 'conservative') {
      return 'conservative';
    }
    if (normalized == 'ld' ||
        normalized == 'libdem' ||
        normalized == 'liberaldemocrat') {
      return 'libdem';
    }
    if (normalized == 'snp' || normalized == 'scottishnationalparty') {
      return 'snp';
    }
    return normalized;
  }
}
