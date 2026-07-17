// Verifies that long debate titles in the home-screen debate feed remain
// readable on narrow (phone-width) screens, per _DebateCardContent in
// date_selector_view.dart: narrow cards always get 2 title lines instead of
// being capped at 1 by the card's height tier, and a Tooltip carrying the
// full title is always attached as a fallback for titles too long even for
// that.

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
import 'package:open_hansard/models/speech.dart';
import 'package:open_hansard/services/parliamentary_data_service.dart';
import 'package:open_hansard/services/theme_service.dart';
import 'package:open_hansard/views/date_selector_view.dart';

const _longTitle =
    'Motion to Approve the Comprehensive Report on the Reform of '
    'Environmental, Social and Economic Policy Affecting Rural Communities '
    'and Coastal Infrastructure Bill';

/// A [ParliamentaryDataService] that serves a single, very short debate with
/// a long title for every date — enough to drive the debate feed without
/// hitting the network.
class _FakeParliamentaryDataService implements ParliamentaryDataService {
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
  Future<List<Speech>> getSpeeches(String date) async => const [];

  @override
  Future<Member?> fetchAndCacheMemberById(int id) async => null;

  @override
  Future<List<Debate>> getDebatesForDate(String date) async => const [
        Debate(
          id: 'debate-1',
          title: _longTitle,
          house: 'Commons',
          orderIndex: 0,
        ),
      ];

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
  Future<DateTime?> getPreviousSittingDate(String date) async => null;

  @override
  Future<DateTime?> getNextSittingDate(String date) async => null;

  @override
  Future<Set<DateTime>> getSittingDates(int year, int month) async =>
      <DateTime>{};

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

Future<void> _pumpDebateFeed(WidgetTester tester) async {
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
  // Settle the async landing-day lookup and the debate feed's FutureBuilder.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'long debate title is readable on a narrow phone screen',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1.0;

      await _pumpDebateFeed(tester);

      // The card must be short (duration falls back to 0 with no speeches,
      // clamping to the minimum card height) — exactly the case where the
      // old height-only tiering capped the title at 1 line.
      final titleFinder = find.text(_longTitle);
      expect(titleFinder, findsOneWidget);

      final titleText = tester.widget<Text>(titleFinder);
      // Narrow cards always get 2 lines, not just 1, so far more of a long
      // title is visible up front instead of being cut after a few words.
      expect(titleText.maxLines, 2);

      // Even 2 lines won't always be enough for very long bill/motion
      // titles, so a Tooltip carrying the *full* title must always be
      // attached — the full title is never a dead end behind an ellipsis.
      final tooltipFinder = find.ancestor(
        of: titleFinder,
        matching: find.byType(Tooltip),
      );
      expect(tooltipFinder, findsOneWidget);
      final tooltip = tester.widget<Tooltip>(tooltipFinder);
      expect(tooltip.message, _longTitle);

      // No overflow/render errors from the 2-line title at the minimum card
      // height.
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short debate card on a wide screen keeps the original 1-line title',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;

      await _pumpDebateFeed(tester);

      final titleFinder = find.text(_longTitle);
      expect(titleFinder, findsOneWidget);

      final titleText = tester.widget<Text>(titleFinder);
      // Wide/tablet layouts are unchanged: a short card still shows 1 line,
      // relying on the Tooltip (still present) for the rest.
      expect(titleText.maxLines, 1);

      expect(tester.takeException(), isNull);
    },
  );
}
