import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/boundary.dart';
import 'package:open_hansard/models/council.dart';
import 'package:open_hansard/models/councillor.dart';
import 'package:open_hansard/models/councillor_profile.dart';
import 'package:open_hansard/models/debate.dart';
import 'package:open_hansard/models/election_result.dart';
import 'package:open_hansard/models/member.dart';
import 'package:open_hansard/models/parliament_live_event.dart';
import 'package:open_hansard/models/recess_period.dart';
import 'package:open_hansard/models/speech.dart';
import 'package:open_hansard/services/parliamentary_data_service.dart';
import 'package:latlong2/latlong.dart';
import 'package:open_hansard/utils/party_colors.dart' as party_util;
import 'package:open_hansard/viewmodels/bill_viewmodel.dart';
import 'package:open_hansard/viewmodels/bills_list_viewmodel.dart';
import 'package:open_hansard/viewmodels/constituency_map_viewmodel.dart';
import 'package:open_hansard/viewmodels/constituency_viewmodel.dart';
import 'package:open_hansard/viewmodels/council_history_viewmodel.dart';
import 'package:open_hansard/viewmodels/date_selector_viewmodel.dart';
import 'package:open_hansard/viewmodels/house_seating_viewmodel.dart';
import 'package:open_hansard/viewmodels/member_viewmodel.dart';
import 'package:open_hansard/viewmodels/search_viewmodel.dart';
import 'package:open_hansard/viewmodels/transcript_viewmodel.dart';

// ─── Manual mocks ──────────────────────────────────────────────────────────

class _FakeParliamentaryDataService implements ParliamentaryDataService {
  bool isCachedResult = false;
  bool hasSittingDataResult = true;
  DateTime? previousSittingDateResult;
  DateTime? nextSittingDateResult;

  /// Optional per-date overrides for [getPreviousSittingDate] /
  /// [getNextSittingDate], used to script multi-hop chains. When unset, the
  /// fixed `previousSittingDateResult`/`nextSittingDateResult` are returned
  /// regardless of the requested date.
  DateTime? Function(String date)? previousSittingDateBuilder;
  DateTime? Function(String date)? nextSittingDateBuilder;

  /// Optional per-date overrides for [getDebatesForDate] / [getSpeeches],
  /// used to script which dates have real vs. placeholder-only content. When
  /// unset, [getDebatesForDate] returns an empty list and [getSpeeches]
  /// falls back to its existing fixed-result behaviour below.
  List<Debate> Function(String date)? debatesForDateBuilder;
  List<Speech> Function(String date)? speechesForDateBuilder;

  /// Optional scripted override for [getSittingDates], called with the
  /// requested (year, month). When unset, [sittingDatesResult] is returned.
  /// [getSittingDatesCalls] counts every invocation.
  Set<DateTime> Function(int year, int month)? sittingDatesBuilder;
  Set<DateTime> sittingDatesResult = <DateTime>{};
  int getSittingDatesCalls = 0;

  /// Fixed result / error for [getRecessPeriods]; [getRecessPeriodsCalls]
  /// counts every invocation.
  List<RecessPeriod> recessPeriodsResult = const <RecessPeriod>[];
  Object? recessPeriodsError;
  int getRecessPeriodsCalls = 0;
  List<Speech> speechesResult = [];
  List<Member> membersResult = [];
  Map<int, Member?> memberResults = {};
  Map<String, int> speakerAliasMemberIds = {};
  Map<String, int> lastSavedSpeakerAliasMemberIds = {};
  List<BoundaryPolygon> constituencyBoundariesResult = const [];
  List<BoundaryPolygon> councilBoundariesResult = const [];
  List<Council> councilsResult = const [];
  List<Councillor> councillorsResult = const [];
  Object? speechesError;
  Duration speechesDelay = Duration.zero;

  @override
  Future<Uri?> billPageUrl(String billTitle) async => null;

  int? billIdResult;
  Map<String, dynamic>? billDetailResult;
  List<Map<String, dynamic>> billStagesResult = const [];
  List<Map<String, dynamic>> billNewsResult = const [];
  List<Map<String, dynamic>> recentBillsResult = const [];
  List<Map<String, dynamic>> searchBillsResult = const [];
  List<Map<String, dynamic>> cachedDebateResults = const [];

  @override
  Future<int?> findBillId(String billTitle) async => billIdResult;

  @override
  Future<List<Map<String, dynamic>>> fetchRecentBills({int skip = 0, int take = 40}) async =>
      recentBillsResult;

  @override
  Future<List<Map<String, dynamic>>> fetchComingUpBills({int skip = 0, int take = 50}) async => [];

  @override
  Future<List<Map<String, dynamic>>> searchBills(
    String query, {
    int take = 20,
  }) async =>
      searchBillsResult;

  @override
  Future<List<Map<String, dynamic>>> fetchBillTypes() async => const [];

  @override
  Future<Map<String, dynamic>?> fetchBillDetail(int id) async =>
      billDetailResult;

  @override
  Future<List<Map<String, dynamic>>> fetchBillStages(int id) async =>
      billStagesResult;

  @override
  Future<List<Map<String, dynamic>>> fetchBillNews(int id) async =>
      billNewsResult;

  @override
  Future<List<BoundaryPolygon>> fetchConstituencyBoundaries() async =>
      constituencyBoundariesResult;

  @override
  Future<List<BoundaryPolygon>> fetchCouncilBoundaries() async =>
      councilBoundariesResult;

  @override
  Future<List<Council>> fetchCouncils() async => councilsResult;

  @override
  Future<List<Councillor>> fetchCouncillors() async => councillorsResult;

  @override
  Future<CouncillorProfile?> fetchCouncillorProfile(
    Councillor councillor,
  ) async =>
      null;

  @override
  Future<bool> isSittingCached(String date) async => isCachedResult;

  @override
  Future<bool> hasSittingData(String date) async => hasSittingDataResult;

  @override
  Future<DateTime?> getPreviousSittingDate(String date) async =>
      previousSittingDateBuilder?.call(date) ?? previousSittingDateResult;

  @override
  Future<DateTime?> getNextSittingDate(String date) async =>
      nextSittingDateBuilder?.call(date) ?? nextSittingDateResult;

  @override
  Future<Set<DateTime>> getSittingDates(int year, int month) async {
    getSittingDatesCalls++;
    final builder = sittingDatesBuilder;
    if (builder != null) return builder(year, month);
    return sittingDatesResult;
  }

  @override
  Future<List<RecessPeriod>> getRecessPeriods(int year, int month) async {
    getRecessPeriodsCalls++;
    if (recessPeriodsError != null) throw recessPeriodsError!;
    return recessPeriodsResult;
  }

  @override
  Future<List<Speech>> getSpeeches(String date) async {
    if (speechesDelay > Duration.zero) {
      await Future<void>.delayed(speechesDelay);
    }
    if (speechesError != null) throw speechesError!;
    return speechesForDateBuilder?.call(date) ?? speechesResult;
  }

  @override
  Future<Member?> getMemberById(int memberId) async => memberResults[memberId];

  @override
  Future<List<Member>> getMembers() async => membersResult;

  @override
  Future<Member?> fetchAndCacheMemberById(int id) async => memberResults[id];

  @override
  Future<Map<String, int>> getSpeakerAliasMemberIds(
    Iterable<String> aliasKeys,
  ) async {
    final out = <String, int>{};
    for (final key in aliasKeys) {
      final id = speakerAliasMemberIds[key];
      if (id != null) out[key] = id;
    }
    return out;
  }

  @override
  Future<void> saveSpeakerAliasMemberIds(
      Map<String, int> aliasToMemberId) async {
    lastSavedSpeakerAliasMemberIds = Map<String, int>.from(aliasToMemberId);
    speakerAliasMemberIds.addAll(aliasToMemberId);
  }

  @override
  Future<List<Debate>> getDebatesForDate(String date) async =>
      debatesForDateBuilder?.call(date) ?? const [];

  @override
  Future<List<Map<String, dynamic>>> searchCachedDebates(
    String query, {
    int limit = 40,
  }) async =>
      cachedDebateResults;

  @override
  Future<int> wipeDebateCache() async => 0;

  @override
  Future<int> clearMapBoundaries() async => 0;

  @override
  Future<int> clearCouncilData() async => 0;

  @override
  Future<int> clearCachedMembers() async => 0;

  @override
  Future<ParliamentLiveEvent?> findLiveEventForDebate({
    required String date,
    required String debateTitle,
    String? house,
  }) async =>
      null;

  @override
  Future<Map<String, dynamic>?> fetchMemberDetail(int id) async => null;

  @override
  Future<Map<String, dynamic>?> fetchMemberBiography(int id) async => null;

  @override
  Future<List<Map<String, dynamic>>> fetchMemberContributions(int memberId) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchMemberVoting(
    int memberId, {
    int house = 1,
    int page = 1,
  }) async {
    if (memberVotingPages.isNotEmpty) {
      return memberVotingPages[page] ?? const [];
    }
    return page == 1 ? memberVotingResult : const [];
  }

  List<Map<String, dynamic>> memberVotingResult = const [];
  Map<int, List<Map<String, dynamic>>> memberVotingPages = const {};

  @override
  Future<List<double>?> geocodeConstituency(String constituencyName) async =>
      null;

  Map<String, ConstituencyElectionResult?> constituencyResults = {};

  @override
  Future<ConstituencyElectionResult?> fetchConstituencyResult(
    String constituencyName,
  ) async =>
      constituencyResults[constituencyName];

  // Per-year council control, keyed by year. Phase-2 control history.
  Map<int, Council?> councilByYear = {};

  @override
  Future<Council?> fetchCouncilForYear(String name, int year) async =>
      councilByYear[year];

  @override
  void dispose() {}
}

// ─── DateSelectorViewModel tests ────────────────────────────────────────────

void main() {
  group('DateSelectorViewModel', () {
    late _FakeParliamentaryDataService fakeService;
    late DateSelectorViewModel vm;

    setUp(() {
      fakeService = _FakeParliamentaryDataService();
      vm = DateSelectorViewModel(fakeService);
    });

    tearDown(() => vm.dispose());

    test('initial state has no selectedDay', () {
      expect(vm.selectedDay, isNull);
    });

    test('selectDay updates selectedDay and notifies listeners', () {
      var notified = false;
      vm.addListener(() => notified = true);

      final day = DateTime(2024, 11, 4); // Monday
      vm.selectDay(day);

      expect(vm.selectedDay, day);
      expect(notified, isTrue);
    });

    test('setFocusedDay updates focusedDay and notifies listeners', () {
      var notified = false;
      vm.addListener(() => notified = true);

      final day = DateTime(2024, 11, 4);
      vm.setFocusedDay(day);

      expect(vm.focusedDay, day);
      expect(notified, isTrue);
    });

    group('isSittingDay', () {
      test('returns true for weekdays', () {
        expect(vm.isSittingDay(DateTime(2024, 11, 4)), isTrue); // Monday
        expect(vm.isSittingDay(DateTime(2024, 11, 5)), isTrue); // Tuesday
        expect(vm.isSittingDay(DateTime(2024, 11, 8)), isTrue); // Friday
      });

      test('returns false for weekends', () {
        expect(vm.isSittingDay(DateTime(2024, 11, 2)), isFalse); // Saturday
        expect(vm.isSittingDay(DateTime(2024, 11, 3)), isFalse); // Sunday
      });
    });

    test('formatDate produces YYYY-MM-DD string', () {
      expect(
        DateSelectorViewModel.formatDate(DateTime(2024, 1, 5)),
        '2024-01-05',
      );
      expect(
        DateSelectorViewModel.formatDate(DateTime(2024, 11, 20)),
        '2024-11-20',
      );
    });

    test('isCached delegates to service', () async {
      fakeService.isCachedResult = true;
      final result = await vm.isCached(DateTime(2024, 11, 4));
      expect(result, isTrue);
    });

    test('isCached returns false when service returns false', () async {
      fakeService.isCachedResult = false;
      final result = await vm.isCached(DateTime(2024, 11, 4));
      expect(result, isFalse);
    });

    test('nearestSittingDay returns same day when data exists', () async {
      fakeService.hasSittingDataResult = true;

      final result = await vm.nearestSittingDay(DateTime(2024, 11, 4));
      expect(result, DateTime(2024, 11, 4));
    });

    test('nearestSittingDay returns nearest linked day when in recess',
        () async {
      fakeService.hasSittingDataResult = false;
      fakeService.previousSittingDateResult = DateTime(2024, 7, 22);
      fakeService.nextSittingDateResult = DateTime(2024, 9, 2);

      final result = await vm.nearestSittingDay(DateTime(2024, 8, 15));
      expect(result, DateTime(2024, 9, 2));
    });

    test('mostRecentSittingDay returns same day when data exists', () async {
      fakeService.hasSittingDataResult = true;
      final result = await vm.mostRecentSittingDay(DateTime(2024, 11, 4));
      expect(result, DateTime(2024, 11, 4));
    });

    test('mostRecentSittingDay returns previous sitting day in recess',
        () async {
      fakeService.hasSittingDataResult = false;
      fakeService.previousSittingDateResult = DateTime(2024, 7, 22);
      final result = await vm.mostRecentSittingDay(DateTime(2024, 8, 15));
      expect(result, DateTime(2024, 7, 22));
    });

    group('hasVisibleDebates', () {
      const placeholderDebate = Debate(
        id: 'd-placeholder',
        title: 'The House met at 11.30 am',
        house: 'Commons',
        orderIndex: 0,
      );
      const realDebate = Debate(
        id: 'd-real',
        title: 'Oral Answers to Questions',
        house: 'Commons',
        orderIndex: 0,
      );
      const realSpeech = Speech(
        id: 's1',
        debateId: 'd-real',
        debateTitle: 'Oral Answers to Questions',
        memberId: 1,
        memberName: 'Alice',
        attributedTo: 'Alice',
        speechText: 'A real contribution.',
        orderIndex: 0,
      );

      test('returns false for a placeholder-only day', () async {
        fakeService.debatesForDateBuilder = (_) => [placeholderDebate];
        fakeService.speechesForDateBuilder = (_) => [];

        final result = await vm.hasVisibleDebates(DateTime(2024, 11, 4));
        expect(result, isFalse);
      });

      test('returns true when a debate has real content', () async {
        fakeService.debatesForDateBuilder = (_) => [realDebate];
        fakeService.speechesForDateBuilder = (_) => [realSpeech];

        final result = await vm.hasVisibleDebates(DateTime(2024, 11, 4));
        expect(result, isTrue);
      });
    });

    group('content-aware lookback', () {
      const placeholderDate = '2024-11-06';
      const placeholderDebate = Debate(
        id: 'd-placeholder',
        title: 'The House met at 11.30 am',
        house: 'Commons',
        orderIndex: 0,
      );
      const realDebate = Debate(
        id: 'd-real',
        title: 'Oral Answers to Questions',
        house: 'Commons',
        orderIndex: 0,
      );
      const realSpeech = Speech(
        id: 's1',
        debateId: 'd-real',
        debateTitle: 'Oral Answers to Questions',
        memberId: 1,
        memberName: 'Alice',
        attributedTo: 'Alice',
        speechText: 'A real contribution.',
        orderIndex: 0,
      );

      test(
          'mostRecentSittingDay skips a placeholder-only day and returns '
          'the previous real day', () async {
        fakeService.debatesForDateBuilder =
            (date) => date == placeholderDate ? [placeholderDebate] : [realDebate];
        fakeService.speechesForDateBuilder =
            (date) => date == placeholderDate ? [] : [realSpeech];
        fakeService.previousSittingDateBuilder =
            (date) => date == placeholderDate ? DateTime(2024, 11, 5) : null;

        final result = await vm.mostRecentSittingDay(DateTime(2024, 11, 6));
        expect(result, DateTime(2024, 11, 5));
      });

      test(
          'mostRecentSittingDay gives up after the lookback bound and '
          'returns the last day seen', () async {
        fakeService.debatesForDateBuilder = (_) => [placeholderDebate];
        fakeService.speechesForDateBuilder = (_) => [];
        // Always resolves to the day before the requested one, so every
        // candidate in the chain is placeholder-only.
        fakeService.previousSittingDateBuilder =
            (date) => DateTime.parse(date).subtract(const Duration(days: 1));

        final result = await vm.mostRecentSittingDay(DateTime(2024, 11, 30));
        // 15 hops back from Nov 30 lands on Nov 16 (30 - 14).
        expect(result, DateTime(2024, 11, 16));
      });

      test('previousVisibleSittingDay skips a placeholder-only day',
          () async {
        // The intermediate day (Nov 5) is placeholder-only; Nov 4 is real.
        // Nov 6 itself is never content-checked by this walk.
        const intermediateDate = '2024-11-05';
        fakeService.debatesForDateBuilder = (date) =>
            date == intermediateDate ? [placeholderDebate] : [realDebate];
        fakeService.speechesForDateBuilder =
            (date) => date == intermediateDate ? [] : [realSpeech];
        fakeService.previousSittingDateBuilder = (date) {
          if (date == '2024-11-06') return DateTime(2024, 11, 5);
          if (date == intermediateDate) return DateTime(2024, 11, 4);
          return null;
        };

        final result = await vm.previousVisibleSittingDay(DateTime(2024, 11, 6));
        expect(result, DateTime(2024, 11, 4));
      });

      test('nextVisibleSittingDay skips a placeholder-only day', () async {
        // The intermediate day (Nov 5) is placeholder-only; Nov 6 is real.
        const intermediateDate = '2024-11-05';
        fakeService.debatesForDateBuilder = (date) =>
            date == intermediateDate ? [placeholderDebate] : [realDebate];
        fakeService.speechesForDateBuilder =
            (date) => date == intermediateDate ? [] : [realSpeech];
        fakeService.nextSittingDateBuilder = (date) {
          if (date == '2024-11-04') return DateTime(2024, 11, 5);
          if (date == intermediateDate) return DateTime(2024, 11, 6);
          return null;
        };

        final result = await vm.nextVisibleSittingDay(DateTime(2024, 11, 4));
        expect(result, DateTime(2024, 11, 6));
      });
    });

    group('sittingDaysInMonth', () {
      Set<DateTime> weekdaysOfMonth(int year, int month) {
        final days = <DateTime>{};
        final last = DateTime(year, month + 1, 0).day;
        for (var d = 1; d <= last; d++) {
          final day = DateTime(year, month, d);
          if (day.weekday <= DateTime.friday) days.add(day);
        }
        return days;
      }

      test('returns the sitting dates supplied by the service', () async {
        fakeService.sittingDatesBuilder = weekdaysOfMonth;

        final result = await vm.sittingDaysInMonth(DateTime(2024, 11));

        expect(result, weekdaysOfMonth(2024, 11));
      });

      test('normalises any time component to midnight', () async {
        fakeService.sittingDatesResult = {
          DateTime(2024, 11, 4, 9, 30),
          DateTime(2024, 11, 5, 14),
        };

        final result = await vm.sittingDaysInMonth(DateTime(2024, 11));

        expect(result, {DateTime(2024, 11, 4), DateTime(2024, 11, 5)});
      });

      test('caps the result at today for the current month', () async {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        fakeService.sittingDatesBuilder = weekdaysOfMonth;

        final result =
            await vm.sittingDaysInMonth(DateTime(now.year, now.month));

        expect(result.every((d) => !d.isAfter(today)), isTrue);
      });

      test('returns empty set with no service call for a future month',
          () async {
        fakeService.sittingDatesBuilder = weekdaysOfMonth;
        final now = DateTime.now();
        final nextMonth = DateTime(now.year, now.month + 1);

        final result = await vm.sittingDaysInMonth(nextMonth);

        expect(result, isEmpty);
        expect(fakeService.getSittingDatesCalls, 0);
      });

      test('returns empty set for a recess month', () async {
        fakeService.sittingDatesResult = <DateTime>{};

        final result = await vm.sittingDaysInMonth(DateTime(2024, 11));

        expect(result, isEmpty);
      });

      test('caches the result so a second call makes no service call',
          () async {
        fakeService.sittingDatesBuilder = weekdaysOfMonth;

        await vm.sittingDaysInMonth(DateTime(2024, 11));
        await vm.sittingDaysInMonth(DateTime(2024, 11));

        expect(fakeService.getSittingDatesCalls, 1);
      });
    });

    group('recessDaysInMonth', () {
      test('labels each day covered by a recess period', () async {
        fakeService.recessPeriodsResult = [
          RecessPeriod(
            description: 'Christmas recess',
            startDate: DateTime(2024, 12, 20),
            endDate: DateTime(2025, 1, 6),
            house: 'Commons',
          ),
        ];

        final result = await vm.recessDaysInMonth(DateTime(2024, 12));

        expect(result[DateTime(2024, 12, 19)], isNull);
        expect(result[DateTime(2024, 12, 20)], 'Christmas recess');
        expect(result[DateTime(2024, 12, 31)], 'Christmas recess');
        // Days in the next month belong to that month's map.
        expect(result.keys.every((d) => d.month == 12), isTrue);
      });

      test('first matching period wins when houses overlap', () async {
        fakeService.recessPeriodsResult = [
          RecessPeriod(
            description: 'Summer recess',
            startDate: DateTime(2024, 7, 23),
            endDate: DateTime(2024, 8, 30),
            house: 'Commons',
          ),
          RecessPeriod(
            description: 'Summer adjournment',
            startDate: DateTime(2024, 7, 30),
            endDate: DateTime(2024, 8, 30),
            house: 'Lords',
          ),
        ];

        final result = await vm.recessDaysInMonth(DateTime(2024, 8));

        expect(result[DateTime(2024, 8, 1)], 'Summer recess');
      });

      test('returns empty map for a month with no recess', () async {
        final result = await vm.recessDaysInMonth(DateTime(2024, 11));

        expect(result, isEmpty);
      });

      test('caches the result so a second call makes no service call',
          () async {
        await vm.recessDaysInMonth(DateTime(2024, 12));
        await vm.recessDaysInMonth(DateTime(2024, 12));

        expect(fakeService.getRecessPeriodsCalls, 1);
      });

      test('a service failure yields an empty, uncached map', () async {
        fakeService.recessPeriodsError = Exception('offline');

        final failed = await vm.recessDaysInMonth(DateTime(2024, 12));
        expect(failed, isEmpty);

        fakeService.recessPeriodsError = null;
        fakeService.recessPeriodsResult = [
          RecessPeriod(
            description: 'Christmas recess',
            startDate: DateTime(2024, 12, 20),
            endDate: DateTime(2025, 1, 6),
          ),
        ];

        final retried = await vm.recessDaysInMonth(DateTime(2024, 12));
        expect(retried, isNotEmpty);
      });
    });
  });

  // ─── TranscriptViewModel tests ───────────────────────────────────────────

  group('TranscriptViewModel', () {
    late _FakeParliamentaryDataService fakeService;
    late TranscriptViewModel vm;

    const testDate = '2024-11-04';

    Speech makeSpeech({
      required String id,
      required String memberName,
      String debateTitle = 'Test Debate',
      String? attributedTo,
      int? memberId,
      String itemType = 'Contribution',
      String speechText = 'Some speech text.',
      String? timecode,
      int orderIndex = 0,
    }) {
      return Speech(
        id: id,
        debateId: 'debate-1',
        debateTitle: debateTitle,
        itemType: itemType,
        memberId: memberId,
        memberName: memberName,
        attributedTo: attributedTo ?? memberName,
        speechText: speechText,
        timecode: timecode,
        orderIndex: orderIndex,
      );
    }

    setUp(() {
      fakeService = _FakeParliamentaryDataService();
      vm = TranscriptViewModel(fakeService, date: testDate);
    });

    tearDown(() => vm.dispose());

    test('initial state is empty and not loading', () {
      expect(vm.speeches, isEmpty);
      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
    });

    test('loadSpeeches populates speeches on success', () async {
      fakeService.speechesResult = [
        makeSpeech(id: 's1', memberName: 'Alice', memberId: 1),
        makeSpeech(id: 's2', memberName: 'Bob', memberId: 2, orderIndex: 1),
      ];
      fakeService.memberResults = {
        1: const Member(
            id: 1, name: 'Alice', party: 'Labour', partyAbbreviation: 'Lab'),
        2: const Member(
            id: 2,
            name: 'Bob',
            party: 'Conservative',
            partyAbbreviation: 'Con'),
      };

      await vm.loadSpeeches();

      expect(vm.speeches, hasLength(2));
      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
    });

    test('loadSpeeches sets error on exception', () async {
      fakeService.speechesError = Exception('Network error');

      await vm.loadSpeeches();

      expect(vm.error, isNotNull);
      expect(vm.speeches, isEmpty);
      expect(vm.isLoading, isFalse);
    });

    test('loadSpeeches does not notify after dispose', () async {
      fakeService.speechesDelay = const Duration(milliseconds: 10);
      fakeService.speechesResult = [
        makeSpeech(id: 's1', memberName: 'Alice', memberId: 1),
      ];

      final vm2 = TranscriptViewModel(fakeService, date: testDate);
      final loadFuture = vm2.loadSpeeches();
      vm2.dispose();

      await loadFuture;
      expect(vm2.speeches, hasLength(1));
    });

    test('speakers list is built alphabetically after loading', () async {
      fakeService.speechesResult = [
        makeSpeech(id: 's1', memberName: 'Zara', orderIndex: 0),
        makeSpeech(id: 's2', memberName: 'Alice', orderIndex: 1),
        makeSpeech(id: 's3', memberName: 'Bob', orderIndex: 2),
        makeSpeech(id: 's4', memberName: 'Alice', orderIndex: 3), // duplicate
      ];

      await vm.loadSpeeches();

      final names = vm.speakers.map((s) => s.name).toList();
      expect(names, ['Alice', 'Bob', 'Zara']);
      // Duplicate Alice should not appear twice.
      expect(names.where((n) => n == 'Alice').length, 1);
    });

    test('speakers firstSpeechIndex points to first occurrence', () async {
      fakeService.speechesResult = [
        makeSpeech(id: 's1', memberName: 'Alice', orderIndex: 0),
        makeSpeech(id: 's2', memberName: 'Bob', orderIndex: 1),
        makeSpeech(id: 's3', memberName: 'Alice', orderIndex: 2),
      ];

      await vm.loadSpeeches();

      final alice = vm.speakers.firstWhere((s) => s.name == 'Alice');
      expect(alice.firstSpeechIndex, 0);
    });

    test('memberFor returns cached member after loading', () async {
      const member = Member(
        id: 1,
        name: 'Alice',
        party: 'Labour',
        partyAbbreviation: 'Lab',
      );
      fakeService.speechesResult = [
        makeSpeech(id: 's1', memberName: 'Alice', memberId: 1),
      ];
      fakeService.memberResults = {1: member};

      await vm.loadSpeeches();

      expect(vm.memberFor(1), member);
      expect(vm.memberFor(999), isNull);
      expect(vm.memberFor(null), isNull);
    });

    test('memberForSpeech resolves fallback by name when memberId is missing',
        () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 's1',
          memberName: 'Captain of the Guard',
          attributedTo:
              'Captain of the Guard (Lord Kennedy of Southwark) (Lab Co-op)',
          speechText: 'Intro',
        ),
      ];
      fakeService.membersResult = const [
        Member(
          id: 4153,
          name: 'Lord Kennedy of Southwark',
          party: 'Labour',
          partyAbbreviation: 'Lab',
          thumbnailUrl: 'https://example.com/lord-kennedy.jpg',
        ),
      ];

      await vm.loadSpeeches();
      final matched = vm.memberForSpeech(vm.speeches.first);
      expect(matched, isNotNull);
      expect(matched!.id, 4153);
      expect(matched.thumbnailUrl, isNotEmpty);
    });

    test('memberForSpeech resolves office-only line via cached alias',
        () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 's1',
          memberName: 'Captain of the Honourable Corps of Gentlemen-at-Arms',
          attributedTo:
              'Captain of the Honourable Corps of Gentlemen-at-Arms and Chief Whip',
          speechText: 'Statement',
        ),
      ];
      fakeService.membersResult = const [
        Member(
          id: 4153,
          name: 'Lord Kennedy of Southwark',
          party: 'Labour',
          partyAbbreviation: 'Lab',
        ),
      ];
      fakeService.speakerAliasMemberIds = const {
        'office:2024-11-04:captain of the honourable corps of gentlemen at arms and chief whip':
            4153,
      };

      await vm.loadSpeeches();
      final matched = vm.memberForSpeech(vm.speeches.first);
      expect(matched, isNotNull);
      expect(matched!.id, 4153);
    });

    test('loadSpeeches removes timestamp rows from display list', () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 't1',
          memberName: '',
          itemType: 'Timestamp',
          speechText: '10:00:00',
        ),
        makeSpeech(id: 's1', memberName: 'Alice', memberId: 1, orderIndex: 1),
      ];

      await vm.loadSpeeches();
      expect(vm.speeches, hasLength(1));
      expect(vm.speeches.first.memberName, 'Alice');
    });

    test('estimatedTimeAtPosition interpolates between timestamps', () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 't1',
          memberName: '',
          itemType: 'Timestamp',
          speechText: '10:00:00',
        ),
        makeSpeech(id: 's1', memberName: 'Alice', memberId: 1, orderIndex: 1),
        makeSpeech(id: 's2', memberName: 'Bob', memberId: 2, orderIndex: 2),
        makeSpeech(
          id: 't2',
          memberName: '',
          itemType: 'Timestamp',
          speechText: '10:10:00',
        ),
        makeSpeech(id: 's3', memberName: 'Cara', memberId: 3, orderIndex: 4),
      ];

      await vm.loadSpeeches();

      expect(vm.estimatedTimeAtPosition(0), '10:00');
      expect(vm.estimatedTimeAtPosition(1), '10:05');
      expect(vm.estimatedTimeAtPosition(2), '10:10');
    });

    test('parliamentLiveStartTimecode prefers explicit speech timecode',
        () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 's1',
          memberName: 'Alice',
          memberId: 1,
          timecode: '10:03:04',
          orderIndex: 0,
        ),
        makeSpeech(
          id: 's2',
          memberName: 'Bob',
          memberId: 2,
          timecode: '10:05:00',
          orderIndex: 1,
        ),
      ];

      await vm.loadSpeeches();
      expect(vm.parliamentLiveStartTimecode, '10:03:04');
    });

    test('parliamentLiveStartTimecode falls back to timestamp anchors',
        () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 't1',
          memberName: '',
          itemType: 'Timestamp',
          speechText: '10:00:00',
          orderIndex: 0,
        ),
        makeSpeech(
          id: 's1',
          memberName: 'Alice',
          memberId: 1,
          orderIndex: 1,
        ),
      ];

      await vm.loadSpeeches();
      expect(vm.parliamentLiveStartTimecode, '10:00:00');
    });

    test('parliamentLiveStartTimecode returns null when no time is available',
        () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 's1',
          memberName: 'Alice',
          memberId: 1,
          orderIndex: 0,
        ),
      ];

      await vm.loadSpeeches();
      expect(vm.parliamentLiveStartTimecode, isNull);
    });

    test('parliamentLiveStartTimecodeForDebateTitle scopes by debate title',
        () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 's1',
          memberName: 'Alice',
          memberId: 1,
          debateTitle: 'Debate A',
          timecode: '09:00:00',
          orderIndex: 0,
        ),
        makeSpeech(
          id: 's2',
          memberName: 'Bob',
          memberId: 2,
          debateTitle: 'Debate B',
          timecode: '10:15:00',
          orderIndex: 1,
        ),
      ];

      await vm.loadSpeeches();
      expect(
          vm.parliamentLiveStartTimecodeForDebateTitle('Debate B'), '10:15:00');
    });

    test('primaryDebateTitle is fixed from loaded transcript', () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 's1',
          memberName: 'Alice',
          debateTitle: 'Business and Trade',
          orderIndex: 0,
        ),
        makeSpeech(
          id: 's2',
          memberName: 'Bob',
          debateTitle: 'Another Debate',
          orderIndex: 1,
        ),
      ];

      await vm.loadSpeeches();
      expect(vm.primaryDebateTitle, 'Business and Trade');
    });

    test('loadSpeeches removes procedural date heading matching sitting day',
        () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 'p1',
          memberName: '',
          speechText: 'Monday 4 November 2024',
        ),
        makeSpeech(id: 's1', memberName: 'Alice', memberId: 1, orderIndex: 1),
      ];

      await vm.loadSpeeches();
      expect(vm.speeches, hasLength(1));
      expect(vm.speeches.first.memberName, 'Alice');
    });

    test('loadSpeeches merges committee member roster into heading block',
        () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 'c1',
          memberName: '',
          speechText: 'The Committee consisted of the following Members:',
          orderIndex: 0,
        ),
        makeSpeech(
          id: 'c2',
          memberName: '',
          speechText: 'Chair: Sir Desmond Swayne',
          orderIndex: 1,
        ),
        makeSpeech(
          id: 'c3',
          memberName: '',
          speechText: '† Argar, Edward (Melton and Syston) (Con)',
          orderIndex: 2,
        ),
        makeSpeech(
          id: 'c4',
          memberName: '',
          speechText: '† attended the Committee',
          orderIndex: 3,
        ),
      ];

      await vm.loadSpeeches();
      expect(vm.speeches, hasLength(1));
      expect(
        vm.speeches.first.speechText,
        contains('Chair: Sir Desmond Swayne'),
      );
      expect(
        vm.speeches.first.speechText,
        contains('• Argar, Edward (Melton and Syston) (Con)'),
      );
    });

    test('loadSpeeches drops "House met at" speech and seeds a time anchor',
        () async {
      fakeService.speechesResult = [
        makeSpeech(
          id: 'p-met',
          memberName: '',
          speechText: 'The House met at 9.30 am.',
          orderIndex: 0,
        ),
        makeSpeech(id: 's1', memberName: 'Alice', memberId: 1, orderIndex: 1),
        makeSpeech(id: 's2', memberName: 'Bob', memberId: 2, orderIndex: 2),
      ];

      await vm.loadSpeeches();
      expect(vm.speeches.map((s) => s.id), ['s1', 's2']);
      // Without timestamp rows the only anchor available comes from the
      // sitting-start announcement — interpolation should return that time.
      expect(vm.estimatedTimeAtPosition(0), '09:30');
      expect(vm.sittingStartTimeLabel, '09:30');
      expect(vm.sittingStartTimecode, '09:30:00');
    });

    test('loadSpeeches does not stall on empty procedural rows', () async {
      fakeService.speechesResult = [
        makeSpeech(
            id: 'p-empty', memberName: '', speechText: '   ', orderIndex: 0),
        makeSpeech(
          id: 'p-date',
          memberName: '',
          speechText: 'Monday 4 November 2024',
          orderIndex: 1,
        ),
        makeSpeech(id: 's1', memberName: 'Alice', memberId: 1, orderIndex: 2),
      ];

      await vm.loadSpeeches().timeout(const Duration(seconds: 2));
      expect(vm.speeches, hasLength(1));
      expect(vm.speeches.first.memberName, 'Alice');
    });
  });

  // ─── MemberViewModel tests ────────────────────────────────────────────────

  group('MemberViewModel', () {
    late _FakeParliamentaryDataService fakeService;

    const member = Member(
      id: 1,
      name: 'Alice',
      party: 'Labour',
      partyAbbreviation: 'Lab',
    );

    setUp(() {
      fakeService = _FakeParliamentaryDataService();
    });

    test('load parses voting record newest-first', () async {
      fakeService.memberVotingResult = [
        {
          'id': 100,
          'title': 'Second Reading',
          'date': '2024-11-04T00:00:00',
          'inAffirmativeLobby': true,
          'inNegativeLobby': false,
          'actedAsTeller': false,
          'numberInFavour': 320,
          'numberAgainst': 210,
        },
        {
          'id': 101,
          'title': 'Amendment 7',
          'date': '2024-10-30T00:00:00',
          'inAffirmativeLobby': false,
          'inNegativeLobby': false,
          'actedAsTeller': true,
        },
      ];

      final vm = MemberViewModel(fakeService, member: member);
      await vm.load();

      expect(vm.votes, hasLength(2));
      expect(vm.votes.first.divisionId, 100);
      expect(vm.votes.first.position, VotePosition.aye);
      expect(vm.votes.first.ayeCount, 320);
      expect(vm.votes[1].position, VotePosition.teller);
      vm.dispose();
    });

    test('load drops vote entries without a title', () async {
      fakeService.memberVotingResult = [
        {'id': 1, 'date': '2024-01-01', 'inAffirmativeLobby': true},
      ];

      final vm = MemberViewModel(fakeService, member: member);
      await vm.load();

      expect(vm.votes, isEmpty);
      vm.dispose();
    });

    test('voteGroups clusters divisions by the title before the colon',
        () async {
      fakeService.memberVotingResult = [
        {
          'id': 1,
          'title': 'Courts Bill: Lords Amendment 6',
          'date': '2024-11-04',
          'inAffirmativeLobby': true,
        },
        {
          'id': 2,
          'title': 'Courts Bill: Lords Amendment 5',
          'date': '2024-11-04',
          'inAffirmativeLobby': true,
        },
        {
          'id': 3,
          'title': 'Privilege',
          'date': '2024-11-03',
          'inNegativeLobby': true,
        },
      ];

      final vm = MemberViewModel(fakeService, member: member);
      await vm.load();

      final groups = vm.voteGroups;
      expect(groups.map((g) => g.title), ['Courts Bill', 'Privilege']);
      expect(groups.first.votes, hasLength(2));
      expect(groups[1].votes.single.divisionId, 3);
      vm.dispose();
    });

    test('loadMoreVotes appends the next page and stops at the end', () async {
      // A full first page (20) signals there may be more; a short second page
      // ends pagination.
      fakeService.memberVotingPages = {
        1: [
          for (var i = 0; i < 20; i++)
            {
              'id': i,
              'title': 'Bill A: Clause $i',
              'date': '2024-11-04',
              'inAffirmativeLobby': true,
            },
        ],
        2: [
          {
            'id': 100,
            'title': 'Bill B',
            'date': '2024-10-01',
            'inNegativeLobby': true,
          },
        ],
      };

      final vm = MemberViewModel(fakeService, member: member);
      await vm.load();
      expect(vm.votes, hasLength(20));
      expect(vm.hasMoreVotes, isTrue);

      await vm.loadMoreVotes();
      expect(vm.votes, hasLength(21));
      expect(vm.hasMoreVotes, isFalse);

      // Further calls are a no-op once exhausted.
      await vm.loadMoreVotes();
      expect(vm.votes, hasLength(21));
      vm.dispose();
    });

    test('does not throw if notified after dispose', () async {
      final vm = MemberViewModel(fakeService, member: member);
      final loadFuture = vm.load();
      vm.dispose();
      await loadFuture;
    });
  });

  group('DateSelectorViewModel.detectBillTitle', () {
    test('extracts the bill name from a debate title', () {
      expect(
        DateSelectorViewModel.detectBillTitle('Football Governance Bill'),
        'Football Governance Bill',
      );
    });

    test('drops a trailing stage suffix', () {
      expect(
        DateSelectorViewModel.detectBillTitle(
          'Tobacco and Vapes Bill: Second Reading',
        ),
        'Tobacco and Vapes Bill',
      );
      expect(
        DateSelectorViewModel.detectBillTitle('Finance Bill (Committee)'),
        'Finance Bill',
      );
    });

    test('returns null for non-bill or procedural titles', () {
      expect(DateSelectorViewModel.detectBillTitle('Oral Answers'), isNull);
      expect(DateSelectorViewModel.detectBillTitle('Presentation of Bills'),
          isNull);
      expect(DateSelectorViewModel.detectBillTitle('Bill Presented'), isNull);
    });
  });

  // ─── BillViewModel tests ───────────────────────────────────────────────────

  group('BillViewModel', () {
    late _FakeParliamentaryDataService fakeService;

    setUp(() {
      fakeService = _FakeParliamentaryDataService();
    });

    test('load sets error when no matching bill is found', () async {
      fakeService.billIdResult = null;

      final vm = BillViewModel(fakeService, billTitle: 'Imaginary Bill');
      await vm.load();

      expect(vm.bill, isNull);
      expect(vm.error, isNotNull);
      expect(vm.isLoading, isFalse);
      vm.dispose();
    });

    test('load parses detail, status, newest-first stages and news', () async {
      fakeService.billIdResult = 3968;
      fakeService.billDetailResult = {
        'billId': 3968,
        'shortTitle': 'Victims and Courts Bill',
        'longTitle': 'A Bill to make provision about victims.',
        'summary': null,
        'currentHouse': 'Commons',
        'originatingHouse': 'Commons',
        'isAct': true,
        'isDefeated': false,
        'billWithdrawn': null,
        'lastUpdate': '2026-04-29T10:00:00',
        'currentStage': {'id': 200, 'description': 'Royal Assent'},
        'sponsors': [
          {
            'member': {
              'memberId': 5035,
              'name': 'Will Stone',
              'party': 'Labour',
              'memberFrom': 'Swindon North',
            },
          },
        ],
      };
      // API returns stages chronologically; the VM reverses to newest-first.
      fakeService.billStagesResult = [
        {
          'id': 100,
          'description': '1st reading',
          'house': 'Commons',
          'stageSittings': [
            {'date': '2025-05-07T00:00:00'},
          ],
        },
        {
          'id': 200,
          'description': 'Royal Assent',
          'house': 'Commons',
          'stageSittings': [
            {'date': '2026-04-29T00:00:00'},
          ],
        },
      ];
      fakeService.billNewsResult = [
        {
          'title': 'Royal Assent',
          'content': '<p>The bill received <b>Royal Assent</b>.</p>',
          'displayDate': '2026-04-29T00:00:00',
        },
      ];

      final vm = BillViewModel(fakeService, billTitle: 'Victims and Courts');
      await vm.load();

      expect(vm.error, isNull);
      expect(vm.bill, isNotNull);
      expect(vm.bill!.status, BillStatus.act);
      expect(vm.bill!.sponsors.single.name, 'Will Stone');

      // Newest stage first, and the current stage is flagged.
      expect(vm.stages.first.description, 'Royal Assent');
      expect(vm.stages.first.isCurrent, isTrue);
      expect(vm.stages.last.description, '1st reading');

      // HTML is stripped from news content.
      expect(vm.news.single.content, 'The bill received Royal Assent.');
      expect(vm.billPageUrl.toString(),
          'https://bills.parliament.uk/bills/3968');
      vm.dispose();
    });

    test('load derives withdrawn and defeated statuses', () async {
      fakeService.billIdResult = 1;
      fakeService.billDetailResult = {
        'billId': 1,
        'shortTitle': 'Some Bill',
        'longTitle': 'A Bill.',
        'isAct': false,
        'isDefeated': false,
        'billWithdrawn': '2025-01-01T00:00:00',
      };

      final vm = BillViewModel(fakeService, billTitle: 'Some Bill');
      await vm.load();
      expect(vm.bill!.status, BillStatus.withdrawn);
      vm.dispose();
    });

    test('supplied billId skips the title lookup', () async {
      fakeService.billIdResult = null; // would fail if findBillId were used
      fakeService.billDetailResult = {
        'billId': 42,
        'shortTitle': 'Pre-resolved Bill',
        'longTitle': 'A Bill.',
      };

      final vm = BillViewModel(fakeService, billTitle: 'x', billId: 42);
      await vm.load();
      expect(vm.error, isNull);
      expect(vm.bill!.shortTitle, 'Pre-resolved Bill');
      vm.dispose();
    });
  });

  // ─── BillsListViewModel tests ──────────────────────────────────────────────

  group('BillsListViewModel', () {
    late _FakeParliamentaryDataService fakeService;

    setUp(() {
      fakeService = _FakeParliamentaryDataService();
    });

    test('load parses recent bills and drops malformed entries', () async {
      fakeService.recentBillsResult = [
        {
          'billId': 4123,
          'shortTitle': 'Steel Industry (Nationalisation) Bill',
          'currentHouse': 'Commons',
          'lastUpdate': '2026-05-22T12:51:15',
          'currentStage': {'description': 'Committee of the whole House'},
        },
        {'billId': 0, 'shortTitle': ''}, // dropped
      ];

      final vm = BillsListViewModel(fakeService);
      await vm.load();

      expect(vm.bills, hasLength(1));
      expect(vm.bills.first.id, 4123);
      expect(vm.bills.first.stageDescription, 'Committee of the whole House');
      expect(vm.error, isNull);
      vm.dispose();
    });

    test('load sets error when no bills come back', () async {
      fakeService.recentBillsResult = const [];

      final vm = BillsListViewModel(fakeService);
      await vm.load();

      expect(vm.bills, isEmpty);
      expect(vm.error, isNotNull);
      vm.dispose();
    });
  });

  group('ConstituencyMapViewModel', () {
    late _FakeParliamentaryDataService fakeService;

    BoundaryPolygon square(String name) => BoundaryPolygon(
          outer: const [
            LatLng(0, 0),
            LatLng(0, 1),
            LatLng(1, 1),
            LatLng(1, 0),
          ],
          name: name,
        );

    setUp(() => fakeService = _FakeParliamentaryDataService());

    test('colours constituencies by the sitting MP party', () async {
      fakeService.constituencyBoundariesResult = [
        square('Aldershot'),
        square('Unheld Seat'),
      ];
      fakeService.membersResult = const [
        Member(
          id: 1,
          name: 'A MP',
          party: 'Labour',
          partyAbbreviation: 'Lab',
          constituency: 'Aldershot',
        ),
      ];

      final vm = ConstituencyMapViewModel(fakeService);
      await vm.load(MapMode.constituency);

      expect(vm.areas, hasLength(2));
      final aldershot =
          vm.areas.firstWhere((a) => a.name == 'Aldershot');
      expect(aldershot.border, party_util.partyColor('Lab'));
      expect(aldershot.controller, contains('A MP'));

      // Unmatched constituency falls back to the no-control grey.
      final unheld = vm.areas.firstWhere((a) => a.name == 'Unheld Seat');
      expect(unheld.border, party_util.noControlColor);
      vm.dispose();
    });

    test('colours councils by control string', () async {
      fakeService.councilBoundariesResult = [
        square('Adur'),
        square('Nowhere'),
      ];
      fakeService.councilsResult = const [
        Council(
          name: 'Adur',
          type: 'District',
          control: 'LAB',
          seats: {'Lab': 17, 'Green': 2},
          total: 19,
        ),
      ];

      final vm = ConstituencyMapViewModel(fakeService);
      await vm.load(MapMode.council);

      final adur = vm.areas.firstWhere((a) => a.name == 'Adur');
      expect(adur.border, party_util.partyColor('Lab'));
      expect(adur.controller, 'LAB');
      expect(adur.council?.total, 19);

      final nowhere = vm.areas.firstWhere((a) => a.name == 'Nowhere');
      expect(nowhere.border, party_util.noControlColor);
      expect(nowhere.council, isNull);
      vm.dispose();
    });

    test('caches per mode and surfaces load errors', () async {
      fakeService.constituencyBoundariesResult = [square('Aldershot')];
      final vm = ConstituencyMapViewModel(fakeService);

      await vm.load(MapMode.constituency);
      expect(vm.error, isNull);
      expect(vm.isLoading, isFalse);
      expect(vm.areas, hasLength(1));
      vm.dispose();
    });
  });

  group('SearchViewModel', () {
    late _FakeParliamentaryDataService fakeService;
    late SearchViewModel vm;

    setUp(() {
      fakeService = _FakeParliamentaryDataService();
      vm = SearchViewModel(fakeService, debounceDuration: Duration.zero);
    });

    tearDown(() => vm.dispose());

    test('searches members and constituencies separately', () async {
      fakeService.membersResult = const [
        Member(
          id: 1,
          name: 'Alex Smith',
          party: 'Labour',
          partyAbbreviation: 'Lab',
          constituency: 'Cambridge',
        ),
        Member(
          id: 2,
          name: 'Baroness Jones',
          party: 'Green',
          partyAbbreviation: '',
        ),
      ];

      await vm.searchNow('Cambridge');
      expect(vm.results.constituencies, hasLength(1));
      expect(vm.results.constituencies.first.name, 'Cambridge');
      expect(vm.results.members, isEmpty);

      await vm.searchNow('Jones');
      expect(vm.results.members, hasLength(1));
      expect(vm.results.members.first.name, 'Baroness Jones');
    });

    test('searches bills, debates, and councillors', () async {
      fakeService.searchBillsResult = [
        {
          'billId': 1,
          'shortTitle': 'Test Bill',
          'currentHouse': 'Commons',
          'currentStage': {'description': 'Second Reading'},
          'lastUpdate': '2025-01-01T00:00:00',
        },
      ];
      fakeService.cachedDebateResults = [
        {
          'debateId': 'abc',
          'title': 'Economy',
          'house': 'Commons',
          'section': 'Business',
          'date': '2025-02-01',
        },
      ];
      fakeService.councilsResult = const [
        Council(
          name: 'Test Council',
          type: 'Unitary',
          control: 'LAB',
          seats: {'Lab': 10},
          total: 10,
        ),
      ];
      fakeService.councillorsResult = const [
        Councillor(
          council: 'Test Council',
          ward: 'North',
          name: 'Pat Doe',
          party: 'Labour',
          partyCode: '',
        ),
      ];

      await vm.searchNow('Test');
      expect(vm.results.bills, hasLength(1));
      expect(vm.results.debates, hasLength(1));
      expect(vm.results.councillors, hasLength(1));
      expect(vm.results.councillors.first.council, isNotNull);
    });
  });

  group('HouseSeatingViewModel', () {
    late _FakeParliamentaryDataService fakeService;
    late HouseSeatingViewModel vm;

    setUp(() {
      fakeService = _FakeParliamentaryDataService();
      vm = HouseSeatingViewModel(fakeService);
    });

    tearDown(() => vm.dispose());

    test('load filters members by house and builds breakdown', () async {
      fakeService.membersResult = const [
        Member(
          id: 1,
          name: 'Alice',
          party: 'Labour',
          partyAbbreviation: 'Lab',
          constituency: 'Cambridge',
        ),
        Member(
          id: 2,
          name: 'Bob',
          party: 'Conservative',
          partyAbbreviation: 'Con',
          constituency: 'York',
        ),
        Member(
          id: 3,
          name: 'Lord Example',
          party: 'Crossbench',
          partyAbbreviation: '',
        ),
      ];

      await vm.load(HouseType.commons);

      expect(vm.seats, hasLength(2));
      expect(vm.totalMembers, 2);
      expect(vm.breakdown, hasLength(2));

      await vm.load(HouseType.lords);

      expect(vm.seats, hasLength(1));
      expect(vm.totalMembers, 1);
      expect(vm.breakdown.single.label, 'Crossbench');
    });

    test('seats include normalized positions', () async {
      fakeService.membersResult = const [
        Member(
          id: 1,
          name: 'Alice',
          party: 'Labour',
          partyAbbreviation: 'Lab',
          constituency: 'Cambridge',
        ),
      ];

      await vm.load(HouseType.commons);

      final seat = vm.seats.single;
      expect(seat.position.dx, inInclusiveRange(0.0, 1.0));
      expect(seat.position.dy, inInclusiveRange(0.0, 1.0));
    });
  });

  // ─── ConstituencyViewModel tests ──────────────────────────────────────────

  group('ConstituencyViewModel', () {
    late _FakeParliamentaryDataService fakeService;

    setUp(() => fakeService = _FakeParliamentaryDataService());

    ConstituencyElectionResult buildResult() => const ConstituencyElectionResult(
          electionTitle: '2024 General Election',
          electionDate: null,
          result: 'Lab Hold',
          majority: 100,
          turnout: 1000,
          electorate: 2000,
          candidates: [
            ElectionCandidate(
              name: 'A',
              party: 'Labour',
              partyAbbreviation: 'Lab',
              votes: 600,
              voteShare: 60,
              rankOrder: 1,
              resultChange: '',
            ),
          ],
        );

    test('load populates the result and clears loading', () async {
      fakeService.constituencyResults = {'Islington North': buildResult()};
      final vm = ConstituencyViewModel(
        fakeService,
        constituencyName: 'Islington North',
      );
      expect(vm.isLoading, isTrue);
      await vm.load();
      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
      expect(vm.result?.result, 'Lab Hold');
    });

    test('load sets error when no result is available', () async {
      final vm = ConstituencyViewModel(
        fakeService,
        constituencyName: 'Nowhere',
      );
      await vm.load();
      expect(vm.isLoading, isFalse);
      expect(vm.result, isNull);
      expect(vm.error, isNotNull);
    });

    test('does not throw if notified after dispose', () async {
      fakeService.constituencyResults = {'X': buildResult()};
      final vm = ConstituencyViewModel(fakeService, constituencyName: 'X');
      final future = vm.load();
      vm.dispose();
      await future; // notifyListeners after dispose must be a no-op, not throw
    });
  });

  // ─── CouncilHistoryViewModel tests ────────────────────────────────────────

  group('CouncilHistoryViewModel', () {
    late _FakeParliamentaryDataService fakeService;

    setUp(() => fakeService = _FakeParliamentaryDataService());

    Council councilFor(int year) => Council(
          name: 'Adur',
          type: 'District',
          control: 'LAB',
          seats: {'Lab': year % 30, 'Con': 5},
          total: 29,
        );

    void seedYears(Iterable<int> years) {
      for (final y in years) {
        fakeService.councilByYear[y] = councilFor(y);
      }
    }

    test('load fetches the last 10 years, newest first', () async {
      seedYears([for (var y = 2017; y <= 2026; y++) y]);
      final vm = CouncilHistoryViewModel(
        fakeService,
        councilName: 'Adur',
        fromYear: 2026,
      );
      await vm.load();
      expect(vm.isLoading, isFalse);
      expect(vm.history, hasLength(10));
      expect(vm.history.first.year, 2026);
      expect(vm.history.last.year, 2017);
    });

    test('omits years that have no data', () async {
      seedYears([2026, 2025, 2023]); // 2024 missing
      final vm = CouncilHistoryViewModel(
        fakeService,
        councilName: 'Adur',
        fromYear: 2026,
      );
      await vm.load();
      expect(vm.history.map((h) => h.year), [2026, 2025, 2023]);
    });

    test('loadOlder appends the next batch of years', () async {
      seedYears([for (var y = 2007; y <= 2026; y++) y]);
      final vm = CouncilHistoryViewModel(
        fakeService,
        councilName: 'Adur',
        fromYear: 2026,
      );
      await vm.load();
      expect(vm.history, hasLength(10));
      await vm.loadOlder();
      expect(vm.history, hasLength(20));
      expect(vm.history.last.year, 2007);
    });

    test('stops offering older years past the data floor', () async {
      seedYears([for (var y = 1973; y <= 1975; y++) y]);
      final vm = CouncilHistoryViewModel(
        fakeService,
        councilName: 'Adur',
        fromYear: 1975,
      );
      await vm.load();
      // Scanning down through the floor (1973) exhausts the range.
      while (vm.canLoadOlder) {
        await vm.loadOlder();
      }
      expect(vm.canLoadOlder, isFalse);
    });
  });
}
