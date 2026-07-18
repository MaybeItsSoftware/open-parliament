import 'package:flutter/foundation.dart';

import '../models/debate.dart';
import '../models/member.dart';
import '../models/recess_period.dart';
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

/// One speaker's engagement in a single debate, used to rank the debate's
/// top speakers. [partyToken] colours the avatar ring; [wordCount] drives the
/// ranking (a proxy for how much of the debate a speaker dominated) while
/// [contributionCount] is the number shown on the card.
class SpeakerContribution {
  final String name;
  final String? partyToken;
  final int contributionCount;
  final int wordCount;
  final String? thumbnailUrl;

  const SpeakerContribution({
    required this.name,
    this.partyToken,
    required this.contributionCount,
    required this.wordCount,
    this.thumbnailUrl,
  });
}

/// Mutable accumulator for a single speaker's stats within one root debate,
/// used only while assembling the feed in [DateSelectorViewModel._assembleDebateFeed].
class _SpeakerAgg {
  String name;
  String? partyToken;
  String? thumbnailUrl;
  int contributionCount = 0;
  int wordCount = 0;

  _SpeakerAgg({required this.name, this.partyToken, this.thumbnailUrl});
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

  /// The debate's most engaged speakers, sorted by word count descending
  /// (capped at 3). May be empty.
  final List<SpeakerContribution> topSpeakers;

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
    this.topSpeakers = const <SpeakerContribution>[],
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

/// Result of [DateSelectorViewModel.loadDebateFeedWithStatus]: the debate
/// feed for a day, plus — only meaningful when [items] is empty — whether
/// the day was a scheduled sitting day whose transcripts simply haven't been
/// published by Hansard yet, as opposed to Parliament genuinely not sitting
/// (weekend/recess).
class DebateFeedResult {
  final List<DebateFeedItem> items;
  final bool isPendingPublication;

  const DebateFeedResult({
    required this.items,
    this.isPendingPublication = false,
  });
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

  /// Returns true if [day] has at least one real (non-placeholder) debate.
  /// Unlike [hasSittingData], this excludes days whose only "debate" is a
  /// procedural placeholder (e.g. "The House met at ... and adjourned").
  Future<bool> hasVisibleDebates(DateTime day) async {
    final feed = await loadDebateFeed(day);
    return feed.isNotEmpty;
  }

  /// How many sitting-day hops [_walkToVisibleDay] and [mostRecentSittingDay]
  /// will take before giving up. Hansard's linked-sitting-dates chain already
  /// skips weekends/recess, so this only needs to cover runs of *consecutive*
  /// placeholder-only sitting days, which is rare.
  static const int _maxContentLookbackHops = 15;

  /// Calls [previousSittingDay] or [nextSittingDay] for [day], retrying once
  /// on failure before giving up. Those hit the network and can throw (no
  /// connectivity, API error); left unguarded, a single throw would propagate
  /// out of [_walkToVisibleDay] / [mostRecentSittingDay] and abandon
  /// landing-day resolution entirely — the app would never move off "today"
  /// even when today has no content. A failure that survives the retry is
  /// treated the same as "no further sitting day in that direction", so
  /// callers fall back to whatever candidate they already have instead of
  /// hanging or crashing.
  Future<DateTime?> _stepSittingDay(DateTime day, {required bool forward}) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return forward ? await nextSittingDay(day) : await previousSittingDay(day);
      } catch (_) {
        if (attempt == 1) return null;
      }
    }
    return null;
  }

  /// Walks the Hansard sitting-day chain from [start], skipping
  /// placeholder-only days, until a day with real debate content is found or
  /// [_maxContentLookbackHops] hops are exhausted. Returns `null` if there
  /// are no more sitting days in that direction (including when the chain
  /// can't be walked further due to a persistent service failure).
  Future<DateTime?> _walkToVisibleDay(
    DateTime start, {
    required bool forward,
  }) async {
    DateTime? candidate = await _stepSittingDay(start, forward: forward);
    for (var hop = 0;
        hop < _maxContentLookbackHops && candidate != null;
        hop++) {
      if (await hasVisibleDebates(candidate)) return candidate;
      candidate = await _stepSittingDay(candidate, forward: forward);
    }
    return null;
  }

  /// Returns the next sitting day after [start] with real debate content,
  /// skipping any placeholder-only days in between.
  Future<DateTime?> nextVisibleSittingDay(DateTime start) =>
      _walkToVisibleDay(start, forward: true);

  /// Returns the closest sitting day before [start] with real debate content,
  /// skipping any placeholder-only days in between.
  Future<DateTime?> previousVisibleSittingDay(DateTime start) =>
      _walkToVisibleDay(start, forward: false);

  /// Returns the latest sitting day on or before [day] with real debate
  /// content, walking backward past any placeholder-only days. Falls back to
  /// the last candidate seen if the lookback is exhausted (including when a
  /// persistent service failure stops the walk short), so the caller always
  /// has something to show rather than nothing.
  Future<DateTime?> mostRecentSittingDay(DateTime day) async {
    DateTime? candidate = DateTime(day.year, day.month, day.day);
    DateTime? lastSeen;
    for (var hop = 0;
        hop < _maxContentLookbackHops && candidate != null;
        hop++) {
      lastSeen = candidate;
      if (await hasVisibleDebates(candidate)) return candidate;
      candidate = await _stepSittingDay(candidate, forward: false);
    }
    return lastSeen;
  }

  /// Resolves which day the landing screen should open on for [today].
  ///
  ///  - If [today] already has real debate content, returns [today]
  ///    unchanged (the common case).
  ///  - Else, if [today] was a scheduled sitting day (per
  ///    [isSittingDayScheduled]) but nothing has been published yet, still
  ///    returns [today] — the caller is expected to show an explicit "not
  ///    published yet" empty state (see [loadDebateFeedWithStatus]) rather
  ///    than silently substituting another day.
  ///  - Otherwise (today isn't a scheduled sitting day — weekend/recess —
  ///    or the recess check itself failed and defensively resolved to "not
  ///    scheduled") falls back to [mostRecentSittingDay], preserving the
  ///    original silent walk-back-to-content behaviour exactly.
  Future<DateTime> resolveLandingDay(DateTime today) async {
    final normalizedToday = DateTime(today.year, today.month, today.day);
    if (await hasVisibleDebates(normalizedToday)) return normalizedToday;
    if (await isSittingDayScheduled(normalizedToday)) return normalizedToday;
    return await mostRecentSittingDay(normalizedToday) ?? normalizedToday;
  }

  /// In-memory cache of enumerated sitting days, keyed by `YYYY-MM`.
  final Map<String, Set<DateTime>> _sittingDaysByMonth = {};

  /// Returns the set of sitting days (normalised to midnight) within the
  /// calendar month containing [month].
  ///
  /// Fetched in one request per house via the Hansard calendar endpoint
  /// ([ParliamentaryDataService.getSittingDates]) and capped at today. Results
  /// are cached per year-month so paging the calendar back and forth never
  /// refetches. A month with no sittings (recess) or one entirely in the future
  /// yields an empty set (the future case makes no network call).
  Future<Set<DateTime>> sittingDaysInMonth(DateTime month) async {
    final key = _monthKey(month);
    final cached = _sittingDaysByMonth[key];
    if (cached != null) return cached;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstOfMonth = DateTime(month.year, month.month, 1);

    final result = <DateTime>{};

    // The whole month is in the future — nothing to fetch, no API calls.
    if (firstOfMonth.isAfter(today)) {
      _sittingDaysByMonth[key] = result;
      return result;
    }

    final dates = await _service.getSittingDates(month.year, month.month);
    for (final date in dates) {
      final normalized = DateTime(date.year, date.month, date.day);
      if (!normalized.isAfter(today)) result.add(normalized);
    }

    _sittingDaysByMonth[key] = result;
    return result;
  }

  /// In-memory cache of recess-day periods, keyed by `YYYY-MM`.
  final Map<String, Map<DateTime, RecessPeriod>> _recessDaysByMonth = {};

  /// Returns a map from each day (normalised to midnight) of the calendar
  /// month containing [month] that falls inside a named non-sitting period,
  /// to the covering [RecessPeriod] (the calendar shows its name and range).
  ///
  /// Days covered by a period for either house are included; the calendar
  /// only decorates days that aren't sitting days, so a day where one house
  /// sat while the other was in recess still renders as a sitting day.
  /// Capped at today, like [sittingDaysInMonth] — the API publishes recess
  /// dates in advance, but a not-yet-happened recess shouldn't be surfaced.
  /// Results are cached per year-month like [sittingDaysInMonth]. A failure
  /// yields an empty map (uncached, so paging back retries) — recess labels
  /// are decorative and must never block the calendar.
  Future<Map<DateTime, RecessPeriod>> recessDaysInMonth(DateTime month) async {
    final key = _monthKey(month);
    final cached = _recessDaysByMonth[key];
    if (cached != null) return cached;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final result = <DateTime, RecessPeriod>{};
    try {
      final periods = await _service.getRecessPeriods(month.year, month.month);
      final lastDayOfMonth = DateTime(month.year, month.month + 1, 0).day;
      for (var d = 1; d <= lastDayOfMonth; d++) {
        final day = DateTime(month.year, month.month, d);
        if (day.isAfter(today)) continue;
        for (final RecessPeriod period in periods) {
          if (period.contains(day)) {
            result[day] = period;
            break;
          }
        }
      }
    } catch (_) {
      return const <DateTime, RecessPeriod>{};
    }
    _recessDaysByMonth[key] = result;
    return result;
  }

  /// Returns true if [day] was scheduled for Parliament to sit — a weekday
  /// not covered by any recess/non-sitting period ([recessDaysInMonth]) —
  /// independent of whether Hansard has actually *published* transcripts
  /// for that day yet.
  ///
  /// Used to tell "Parliament wasn't sitting" (weekend/recess) apart from
  /// "Parliament sat but Hansard hasn't published yet" when
  /// [hasVisibleDebates] is false for [day]. Hansard's own sitting calendar
  /// ([sittingDaysInMonth]) is unsuitable for this check — it's populated
  /// retroactively as Hansard processes each day, so it suffers the same
  /// publish-lag problem this method exists to detect around. The recess
  /// calendar, by contrast, is published well in advance.
  ///
  /// Fails closed: if the recess check itself fails, [recessDaysInMonth]
  /// returns an empty map (its own documented best-effort behaviour), which
  /// makes this return `true` for any weekday. A genuine recess day hit
  /// during a recess-API outage would therefore be mistaken for "scheduled
  /// but unpublished" rather than falling back to the walk-back behaviour —
  /// an accepted, bounded tradeoff (the caller still offers a manual
  /// "view previous sitting day" escape hatch), consistent with how recess
  /// data is treated as best-effort everywhere else in this view-model.
  Future<bool> isSittingDayScheduled(DateTime day) async {
    if (!isSittingDay(day)) return false;
    final recess = await recessDaysInMonth(DateTime(day.year, day.month));
    return !recess.containsKey(DateTime(day.year, day.month, day.day));
  }

  static String _monthKey(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';

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

  /// Loads the debate feed for [day] and, only when it turns out empty *and*
  /// [isToday] is true, additionally checks [isSittingDayScheduled] to
  /// classify the empty state as "pending publication" vs. genuinely no
  /// sitting. Bundled into a single awaited value so the view has one
  /// loading → resolved transition rather than a second nested future for
  /// the empty-state classification.
  Future<DebateFeedResult> loadDebateFeedWithStatus(
    DateTime day, {
    required bool isToday,
  }) async {
    final items = await loadDebateFeed(day);
    if (items.isNotEmpty || !isToday) {
      return DebateFeedResult(items: items);
    }
    final scheduled = await isSittingDayScheduled(day);
    return DebateFeedResult(items: items, isPendingPublication: scheduled);
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
    final speakerStatsByRoot = <String, Map<String, _SpeakerAgg>>{};
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
        final member = lookup != null && speech.memberId != null
            ? lookup.memberById(speech.memberId!)
            : null;
        final partyToken = _partyTokenForSpeech(speech, lookup, member: member);
        if (partyToken != null) {
          final counts = partyCountsByRoot[currentRoot] ??= <String, int>{};
          counts[partyToken] = (counts[partyToken] ?? 0) + 1;
        }
        if (speakerKey != null) {
          final stats = speakerStatsByRoot[currentRoot] ??=
              <String, _SpeakerAgg>{};
          final agg = stats.putIfAbsent(
            speakerKey,
            () => _SpeakerAgg(
              name: speakerIdentityFor(speech, member).name,
              partyToken: partyToken,
              thumbnailUrl: member?.thumbnailUrl,
            ),
          );
          agg.contributionCount += 1;
          agg.wordCount += _wordCount(speech.speechText);
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
                topSpeakers: _topSpeakers(speakerStatsByRoot[d.id]),
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
            topSpeakers: _topSpeakers(speakerStatsByRoot[entry.key]),
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
  /// (e.g. "… (Lab)"). Returns `null` when nothing can be resolved. Pass an
  /// already-resolved [member] to avoid a redundant lookup.
  static String? _partyTokenForSpeech(
    Speech speech,
    MemberLookupIndex? lookup, {
    Member? member,
  }) {
    member ??=
        lookup != null && speech.memberId != null ? lookup.memberById(speech.memberId!) : null;
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

  /// The debate's top 3 speakers by word count (ties broken by contribution
  /// count, then name), used to populate [DebateFeedItem.topSpeakers].
  static const int _topSpeakerCount = 3;

  static List<SpeakerContribution> _topSpeakers(Map<String, _SpeakerAgg>? stats) {
    if (stats == null || stats.isEmpty) {
      return const <SpeakerContribution>[];
    }
    final aggs = stats.values.toList()
      ..sort((a, b) {
        final byWords = b.wordCount.compareTo(a.wordCount);
        if (byWords != 0) return byWords;
        final byContributions = b.contributionCount.compareTo(a.contributionCount);
        if (byContributions != 0) return byContributions;
        return a.name.compareTo(b.name);
      });
    return [
      for (final agg in aggs.take(_topSpeakerCount))
        SpeakerContribution(
          name: agg.name,
          partyToken: agg.partyToken,
          contributionCount: agg.contributionCount,
          wordCount: agg.wordCount,
          thumbnailUrl: agg.thumbnailUrl,
        ),
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
