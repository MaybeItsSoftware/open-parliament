import 'package:flutter/foundation.dart';

import '../models/debate.dart';
import '../models/member.dart';
import '../models/speech.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/member_lookup_index.dart';
import '../utils/party_tokens.dart';
import '../utils/speaker_identity.dart';

/// A party's share of the contributions in a single debate. [partyToken] is a
/// canonical token (e.g. `'labour'`); the view maps it to a brand colour.
class PartyContribution {
  final String partyToken;
  final int count;

  const PartyContribution({required this.partyToken, required this.count});
}

/// One row in the debate feed shown on the landing page for a sitting day.
class DebateFeedItem {
  final String title;
  final int durationMinutes;
  final String house;
  final String debateId;
  final int order;
  final String? startTimecode;
  final String? section;

  /// Number of distinct speakers who made a meaningful contribution.
  final int speakerCount;

  /// Number of meaningful contributions (excludes timestamps/procedural).
  final int contributionCount;

  /// Per-party contribution counts, sorted by count descending. Only parties
  /// that could be resolved are included; may be empty.
  final List<PartyContribution> partyBreakdown;

  /// The bill this debate relates to (parsed from [title]), or `null` if the
  /// title doesn't name a bill. Used to deep-link to bills.parliament.uk.
  final String? relatedBillTitle;

  const DebateFeedItem({
    required this.title,
    required this.durationMinutes,
    this.house = '',
    this.debateId = '',
    this.order = 0,
    this.startTimecode,
    this.section,
    this.speakerCount = 0,
    this.contributionCount = 0,
    this.partyBreakdown = const <PartyContribution>[],
    this.relatedBillTitle,
  });

  String get durationLabel {
    final hoursPart = durationMinutes ~/ 60;
    final minutesPart = durationMinutes % 60;
    if (hoursPart == 0) return '${minutesPart}m';
    if (minutesPart == 0) return '${hoursPart}h';
    return '${hoursPart}h ${minutesPart}m';
  }
}

/// View-model backing the date selector screen.
///
/// Provides the set of sitting days that are available to browse and tracks
/// the currently selected date.
class DateSelectorViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;

  DateSelectorViewModel(this._service);

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  /// The day currently displayed in the calendar widget.
  DateTime get focusedDay => _focusedDay;

  /// The day the user has tapped (may be `null` before any selection).
  DateTime? get selectedDay => _selectedDay;

  /// Whether [day] has already been fetched and cached locally.
  Future<bool> isCached(DateTime day) =>
      _service.isSittingCached(_formatDate(day));

  /// Returns true if Hansard has sitting data for [day].
  Future<bool> hasSittingData(DateTime day) =>
      _service.hasSittingData(_formatDate(day));

  /// Returns the closest previous parliamentary sitting day.
  Future<DateTime?> previousSittingDay(DateTime day) =>
      _service.getPreviousSittingDate(_formatDate(day));

  /// Returns the closest next parliamentary sitting day.
  Future<DateTime?> nextSittingDay(DateTime day) =>
      _service.getNextSittingDate(_formatDate(day));

  /// Returns [day] if it has data, otherwise the nearest available sitting day.
  Future<DateTime?> nearestSittingDay(DateTime day) async {
    if (await hasSittingData(day)) {
      return DateTime(day.year, day.month, day.day);
    }

    final previous = await previousSittingDay(day);
    final next = await nextSittingDay(day);

    if (previous == null) return next;
    if (next == null) return previous;

    final distanceToPrevious = day.difference(previous).inDays.abs();
    final distanceToNext = next.difference(day).inDays.abs();
    return distanceToPrevious <= distanceToNext ? previous : next;
  }

  /// Returns the latest sitting day on or before [day] that has debates.
  Future<DateTime?> mostRecentSittingDay(DateTime day) async {
    final normalized = DateTime(day.year, day.month, day.day);
    if (await hasSittingData(normalized)) {
      return normalized;
    }
    return previousSittingDay(normalized);
  }

  void setFocusedDay(DateTime day) {
    _focusedDay = day;
    notifyListeners();
  }

  void selectDay(DateTime day) {
    _selectedDay = day;
    notifyListeners();
  }

  /// Returns true if [day] is a weekday (Mon–Fri), which is the only time
  /// Parliament sits. This is used to disable weekends in the calendar.
  bool isSittingDay(DateTime day) {
    return day.weekday >= DateTime.monday && day.weekday <= DateTime.friday;
  }

  /// Formats [day] as `YYYY-MM-DD` for use with the API and database.
  static String formatDate(DateTime day) => _formatDate(day);

  static String _formatDate(DateTime day) {
    final y = day.year.toString().padLeft(4, '0');
    final m = day.month.toString().padLeft(2, '0');
    final d = day.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Resolves the bills.parliament.uk page for [billTitle] (as produced by
  /// [detectBillTitle]), or `null` if no matching bill is found. Called lazily
  /// when the user taps a debate's bill chip.
  Future<Uri?> billUrl(String billTitle) => _service.billPageUrl(billTitle);

  /// Extracts the bill name from a debate [title] (the portion up to and
  /// including the word "Bill", dropping any trailing stage suffix), or `null`
  /// when the title doesn't name a bill.
  static String? detectBillTitle(String title) {
    final match = _billTitlePattern.firstMatch(title.trim());
    if (match == null) return null;
    final name = match.group(1)!.trim();
    // Require a qualified name ("X Bill"), not a bare procedural "Bill …".
    return name.contains(' ') ? name : null;
  }

  static final RegExp _billTitlePattern = RegExp(r'^(.+?\bBill)\b');

  /// Loads the debate feed for [day]: one [DebateFeedItem] per root debate,
  /// with a coarse duration estimated from speech word counts. Placeholder
  /// debates (whose only content is the "The House met at …" announcement)
  /// are filtered out.
  Future<List<DebateFeedItem>> loadDebateFeed(DateTime day) async {
    final date = _formatDate(day);
    try {
      final speechesFuture = _service.getSpeeches(date);
      final debatesFuture = _service.getDebatesForDate(date);
      final membersFuture = _service.getMembers();
      final speeches = await speechesFuture;
      final debates = await debatesFuture;
      // Members come from the local cache; resolving party is best-effort and
      // never blocks the feed if it's unavailable.
      List<Member> members = const <Member>[];
      try {
        members = await membersFuture;
      } catch (_) {
        members = const <Member>[];
      }
      final lookup = members.isEmpty ? null : MemberLookupIndex(members);
      return _assembleDebateFeed(debates, speeches, lookup);
    } catch (_) {
      return const <DebateFeedItem>[];
    }
  }

  static List<DebateFeedItem> _assembleDebateFeed(
    List<Debate> debates,
    List<Speech> speeches,
    MemberLookupIndex? lookup,
  ) {
    final rootIds = {for (final d in debates) d.id};
    final houseByDebateId = {for (final d in debates) d.id: d.house};
    final titleByDebateId = {for (final d in debates) d.id: d.title};
    final orderByDebateId = {for (final d in debates) d.id: d.orderIndex};
    final sectionByDebateId = {for (final d in debates) d.id: d.section};

    // Group speeches by root debate — sub-section speeches inherit the
    // most recently seen root debate ID.
    final wordCountsByDebateId = <String, int>{};
    final firstTimecodeByDebateId = <String, String>{};
    final hasMeaningfulSpeechByRoot = <String, bool>{};
    // Per-root engagement stats, populated from meaningful contributions only.
    final speakerKeysByRoot = <String, Set<String>>{};
    final contributionCountByRoot = <String, int>{};
    final partyCountsByRoot = <String, Map<String, int>>{};
    String? currentRoot;
    for (final speech in speeches) {
      if (rootIds.contains(speech.debateId)) {
        currentRoot = speech.debateId;
      }
      if (currentRoot == null) continue;
      final timecode = _normalizedHansardTimecode(speech.timecode) ??
          (speech.isTimestamp
              ? _normalizedHansardTimecode(speech.speechText)
              : null);
      if (timecode != null) {
        firstTimecodeByDebateId.putIfAbsent(currentRoot, () => timecode);
      }
      wordCountsByDebateId[currentRoot] =
          (wordCountsByDebateId[currentRoot] ?? 0) +
              _wordCount(speech.speechText);
      if (_isMeaningfulSpeech(speech)) {
        hasMeaningfulSpeechByRoot[currentRoot] = true;
        contributionCountByRoot[currentRoot] =
            (contributionCountByRoot[currentRoot] ?? 0) + 1;
        final speakerKey = _speakerKey(speech);
        if (speakerKey != null) {
          (speakerKeysByRoot[currentRoot] ??= <String>{}).add(speakerKey);
        }
        final partyToken = _partyTokenForSpeech(speech, lookup);
        if (partyToken != null) {
          final counts = partyCountsByRoot[currentRoot] ??= <String, int>{};
          counts[partyToken] = (counts[partyToken] ?? 0) + 1;
        }
      }
    }

    final placeholderRoots = <String>{
      for (final d in debates)
        if (_isPlaceholderDebate(d, hasMeaningfulSpeechByRoot[d.id] ?? false))
          d.id,
    };

    if (wordCountsByDebateId.isEmpty) {
      // No speeches yet — fall back to debate titles, still filtering out
      // placeholders detectable from the title alone.
      return debates
          .where((d) => !placeholderRoots.contains(d.id))
          .map((d) => DebateFeedItem(
                debateId: d.id,
                title: d.title,
                durationMinutes: 0,
                house: d.house,
                order: d.orderIndex,
                section: d.section,
                startTimecode: firstTimecodeByDebateId[d.id],
                speakerCount: speakerKeysByRoot[d.id]?.length ?? 0,
                contributionCount: contributionCountByRoot[d.id] ?? 0,
                partyBreakdown: _partyBreakdown(partyCountsByRoot[d.id]),
                relatedBillTitle: detectBillTitle(d.title),
              ))
          .toList();
    }

    final items = wordCountsByDebateId.entries
        .where((entry) => !placeholderRoots.contains(entry.key))
        .map(
          (entry) => DebateFeedItem(
            debateId: entry.key,
            title: titleByDebateId[entry.key] ?? '',
            durationMinutes: _minutesFromWords(entry.value),
            house: houseByDebateId[entry.key] ?? '',
            order: orderByDebateId[entry.key] ?? 0,
            section: sectionByDebateId[entry.key],
            startTimecode: firstTimecodeByDebateId[entry.key],
            speakerCount: speakerKeysByRoot[entry.key]?.length ?? 0,
            contributionCount: contributionCountByRoot[entry.key] ?? 0,
            partyBreakdown: _partyBreakdown(partyCountsByRoot[entry.key]),
            relatedBillTitle: detectBillTitle(titleByDebateId[entry.key] ?? ''),
          ),
        )
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    return items;
  }

  static const int _averageWordsPerMinute = 130;
  static const int _maxDurationMinutes = 24 * 60;
  static final RegExp _wordRegex = RegExp(r'\S+');
  static final RegExp _placeholderTitlePattern = RegExp(
    r'^the\s+(house|lords|committee|grand\s+committee)\b.*\bmet\s+at\b',
  );

  static int _wordCount(String text) => _wordRegex.allMatches(text).length;

  static final RegExp _attributionPartyPattern = RegExp(r'\(([^)]+)\)');

  /// A stable key identifying the speaker of [speech], preferring the numeric
  /// member ID and falling back to a normalised display name. Returns `null`
  /// when no speaker can be identified.
  static String? _speakerKey(Speech speech) {
    if (speech.memberId != null) return 'id:${speech.memberId}';
    final name = MemberCandidate.normalizeName(speech.memberName);
    return name.isEmpty ? null : 'name:$name';
  }

  /// Resolves the canonical party token for [speech]: first via the member
  /// lookup (by ID), then from any party hint in the attribution string
  /// (e.g. "… (Lab)"). Returns `null` when nothing can be resolved.
  static String? _partyTokenForSpeech(Speech speech, MemberLookupIndex? lookup) {
    Member? member;
    if (lookup != null && speech.memberId != null) {
      member = lookup.memberById(speech.memberId!);
    }
    if (isSpeakerRole(speakerIdentityFor(speech, member))) {
      return 'speaker';
    }
    if (member != null) {
      final token = canonicalPartyToken(
        member.partyAbbreviation.isNotEmpty
            ? member.partyAbbreviation
            : member.party,
      );
      if (token != null) return token;
    }
    for (final match in _attributionPartyPattern.allMatches(speech.attributedTo)) {
      final token = canonicalPartyToken((match.group(1) ?? '').trim());
      if (token != null) return token;
    }
    return null;
  }

  /// Converts raw per-party counts into a list sorted by count descending.
  static List<PartyContribution> _partyBreakdown(Map<String, int>? counts) {
    if (counts == null || counts.isEmpty) {
      return const <PartyContribution>[];
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final e in entries)
        PartyContribution(partyToken: e.key, count: e.value),
    ];
  }

  /// A debate is a placeholder when it carries no real speech content —
  /// only the "The House met at …" announcement. Detected by the title
  /// pattern *and* the absence of any non-boilerplate speech.
  static bool _isPlaceholderDebate(Debate debate, bool hasMeaningfulSpeech) {
    if (hasMeaningfulSpeech) return false;
    final title = debate.title.toLowerCase().trim();
    return _placeholderTitlePattern.hasMatch(title);
  }

  static bool _isMeaningfulSpeech(Speech speech) {
    if (speech.isSittingStartAnnouncement) return false;
    if (speech.isTimestamp) return false;
    if (speech.isDateHeading) return false;
    return speech.speechText.trim().isNotEmpty;
  }

  static int _minutesFromWords(int words) {
    return (words / _averageWordsPerMinute)
        .round()
        .clamp(1, _maxDurationMinutes);
  }

  static String? _normalizedHansardTimecode(String? value) {
    if (value == null) return null;
    final parts = value.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final s = parts.length == 3 ? int.tryParse(parts[2]) : 0;
    if (h == null || m == null || s == null) return null;
    if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) return null;
    return '${h.toString().padLeft(2, '0')}:'
        '${m.toString().padLeft(2, '0')}:'
        '${s.toString().padLeft(2, '0')}';
  }
}
