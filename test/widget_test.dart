// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

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
import 'package:open_hansard/services/theme_service.dart';
import 'package:open_hansard/viewmodels/date_selector_viewmodel.dart';
import 'package:open_hansard/views/date_selector_view.dart';

class _FakeParliamentaryDataService implements ParliamentaryDataService {
  /// Per-date scripted content, keyed by `YYYY-MM-DD`. Dates not present
  /// return no debates/speeches (i.e. no visible content).
  Map<String, List<Debate>> debatesByDate = {};
  Map<String, List<Speech>> speechesByDate = {};

  /// Scripts [getPreviousSittingDate]; may throw to simulate a network
  /// failure. Optionally gated by [previousSittingDateGate] so a test can
  /// pause resolution mid-flight and observe the loading state.
  DateTime? Function(String date)? previousSittingDateBuilder;
  Completer<void>? previousSittingDateGate;
  int previousSittingDateCalls = 0;

  @override
  Future<List<Member>> getMembers() async => const [];

  @override
  Future<Uri?> billPageUrl(String billTitle) async => null;

  @override
  Future<int?> findBillId(String billTitle) async => null;

  @override
  Future<List<Map<String, dynamic>>> fetchRecentBills({int skip = 0, int take = 40}) async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchComingUpBills({int skip = 0, int take = 50}) async => const [];

  @override
  Future<List<Map<String, dynamic>>> searchBills(
    String query, {
    int take = 20,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchBillTypes() async => const [];

  @override
  Future<Map<String, dynamic>?> fetchBillDetail(int id) async => null;

  @override
  Future<List<Map<String, dynamic>>> fetchBillStages(int id) async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchBillNews(int id) async => const [];

  @override
  Future<List<BoundaryPolygon>> fetchConstituencyBoundaries() async => const [];

  @override
  Future<List<BoundaryPolygon>> fetchCouncilBoundaries() async => const [];

  @override
  Future<List<Council>> fetchCouncils() async => const [];

  @override
  Future<List<Councillor>> fetchCouncillors() async => const [];

  @override
  Future<CouncillorProfile?> fetchCouncillorProfile(
    Councillor councillor,
  ) async =>
      null;

  @override
  Future<Member?> getMemberById(int memberId) async => null;

  @override
  Future<Map<String, int>> getSpeakerAliasMemberIds(
    Iterable<String> aliasKeys,
  ) async =>
      const <String, int>{};

  @override
  Future<void> saveSpeakerAliasMemberIds(
    Map<String, int> aliasToMemberId,
  ) async {}

  @override
  Future<List<Speech>> getSpeeches(String date) async =>
      speechesByDate[date] ?? const [];

  @override
  Future<Member?> fetchAndCacheMemberById(int id) async => null;

  @override
  Future<List<Debate>> getDebatesForDate(String date) async =>
      debatesByDate[date] ?? const [];

  @override
  Future<List<Map<String, dynamic>>> searchCachedDebates(
    String query, {
    int limit = 40,
  }) async =>
      const [];

  @override
  Future<bool> isSittingCached(String date) async => true;

  @override
  Future<bool> hasSittingData(String date) async => true;

  @override
  Future<DateTime?> getPreviousSittingDate(String date) async {
    previousSittingDateCalls++;
    if (previousSittingDateGate != null) {
      await previousSittingDateGate!.future;
    }
    return previousSittingDateBuilder?.call(date);
  }

  @override
  Future<DateTime?> getNextSittingDate(String date) async => null;

  @override
  Future<Set<DateTime>> getSittingDates(int year, int month) async =>
      <DateTime>{};

  /// Scripts [getRecessPeriods]; when unset (empty), no day is treated as
  /// in recess, so [DateSelectorViewModel.isSittingDayScheduled] is `true`
  /// for every weekday.
  List<RecessPeriod> recessPeriodsResult = const [];

  @override
  Future<List<RecessPeriod>> getRecessPeriods(int year, int month) async =>
      recessPeriodsResult;

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
  }) async =>
      const [];

  @override
  Future<List<double>?> geocodeConstituency(String constituencyName) async =>
      null;

  @override
  Future<ConstituencyElectionResult?> fetchConstituencyResult(
    String constituencyName,
  ) async =>
      null;

  @override
  Future<Council?> fetchCouncilForYear(String name, int year) async => null;

  @override
  void dispose() {}
}

void main() {
  testWidgets('Landing page renders redesigned main view', (tester) async {
    final fakeService = _FakeParliamentaryDataService();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ThemeService()),
          Provider<ParliamentaryDataService>.value(value: fakeService),
        ],
        child: const MaterialApp(
          home: DateSelectorView(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Today’s Key Debates'), findsOneWidget);
  });

  testWidgets(
      'shows a loading state while the landing day is still being resolved, '
      'then lands on the most recent day with real content instead of a '
      'premature "no debates" card', (tester) async {
    final fakeService = _FakeParliamentaryDataService();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = DateSelectorViewModel.formatDate(today);
    final priorDay = today.subtract(const Duration(days: 3));
    final priorKey = DateSelectorViewModel.formatDate(priorDay);

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
    // Today has no content; the prior day does. Nothing is scripted for
    // `todayKey` so it stays empty (no debates).
    fakeService.debatesByDate[priorKey] = [realDebate];
    fakeService.speechesByDate[priorKey] = [realSpeech];
    // Mark today as in recess (regardless of what real weekday the suite
    // happens to run on) so isSittingDayScheduled(today) is deterministically
    // false and landing-day resolution falls through to the walk-back path
    // this test exercises, rather than landing on today's pending-
    // publication state.
    fakeService.recessPeriodsResult = [
      RecessPeriod(
        description: 'Recess',
        startDate: today.subtract(const Duration(days: 30)),
        endDate: today.add(const Duration(days: 30)),
        house: 'Commons',
      ),
    ];

    // Walking back from today hits one transient failure before recovering
    // — simulates a network blip during landing-day resolution, which used
    // to propagate unhandled and strand the app on "today" forever.
    var previousSittingDateAttempts = 0;
    fakeService.previousSittingDateBuilder = (date) {
      previousSittingDateAttempts++;
      if (previousSittingDateAttempts == 1) {
        throw Exception('network blip');
      }
      return date == todayKey ? priorDay : null;
    };
    // Gate resolution so the test can observe the pre-resolution frame.
    fakeService.previousSittingDateGate = Completer<void>();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ThemeService()),
          Provider<ParliamentaryDataService>.value(value: fakeService),
        ],
        child: const MaterialApp(
          home: DateSelectorView(),
        ),
      ),
    );
    await tester.pump();

    // Still resolving: a loading indicator is shown, not a "no debates"
    // card for today (which hasn't actually been vetted for content yet).
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.textContaining('No debates are available'), findsNothing);

    // Let resolution proceed: the gated call fails once, retries, and the
    // walk lands on the prior day with real content.
    fakeService.previousSittingDateGate!.complete();
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('No debates are available'), findsNothing);
    expect(find.text('Oral Answers to Questions'), findsOneWidget);
  });

  testWidgets(
      'degrades gracefully (no crash, no permanent loading state) when the '
      'sitting-day walk persistently fails', (tester) async {
    final fakeService = _FakeParliamentaryDataService();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    // getDebatesForDate/getSpeeches default to empty for every date, so
    // today never has content; every attempt to walk backward also fails,
    // simulating a fully offline device.
    fakeService.previousSittingDateBuilder = (_) =>
        throw Exception('offline');
    // Mark today as in recess so isSittingDayScheduled(today) is
    // deterministically false and landing-day resolution actually attempts
    // the (persistently failing) walk-back path this test exercises.
    fakeService.recessPeriodsResult = [
      RecessPeriod(
        description: 'Recess',
        startDate: today.subtract(const Duration(days: 30)),
        endDate: today.add(const Duration(days: 30)),
        house: 'Commons',
      ),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ThemeService()),
          Provider<ParliamentaryDataService>.value(value: fakeService),
        ],
        child: const MaterialApp(
          home: DateSelectorView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Resolution must still complete deterministically — no unhandled
    // exception, and no indefinitely-stuck loading spinner.
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'lands on today with the "not yet published" empty state and a '
      'working "view previous sitting day" action, when today is a '
      'scheduled sitting day with nothing published yet', (tester) async {
    final now = DateTime.now();
    // isSittingDayScheduled requires a weekday; skip on a weekend CI run
    // rather than asserting a scenario that can't occur for real "today".
    if (now.weekday > DateTime.friday) return;

    final fakeService = _FakeParliamentaryDataService();
    final today = DateTime(now.year, now.month, now.day);
    final todayKey = DateSelectorViewModel.formatDate(today);
    final priorDay = today.subtract(const Duration(days: 1));

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
    // Today has no content, and (unlike the other tests) is left out of
    // recessPeriodsResult, so it's a scheduled-but-unpublished weekday.
    fakeService.debatesByDate[DateSelectorViewModel.formatDate(priorDay)] =
        [realDebate];
    fakeService.speechesByDate[DateSelectorViewModel.formatDate(priorDay)] =
        [realSpeech];
    fakeService.previousSittingDateBuilder =
        (date) => date == todayKey ? priorDay : null;

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ThemeService()),
          Provider<ParliamentaryDataService>.value(value: fakeService),
        ],
        child: const MaterialApp(
          home: DateSelectorView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Landed on today, not silently substituted for the prior day.
    expect(
      find.textContaining('haven’t been published yet'),
      findsOneWidget,
    );
    expect(find.text('Oral Answers to Questions'), findsNothing);

    // The affordance jumps to the previous sitting day.
    await tester.tap(find.text('View previous sitting day'));
    await tester.pumpAndSettle();

    expect(find.text('Oral Answers to Questions'), findsOneWidget);
  });
}
