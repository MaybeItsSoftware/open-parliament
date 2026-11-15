import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:open_parliament/models/boundary.dart';
import 'package:open_parliament/models/council.dart';
import 'package:open_parliament/models/councillor.dart';
import 'package:open_parliament/models/councillor_profile.dart';
import 'package:open_parliament/models/debate.dart';
import 'package:open_parliament/models/election_result.dart';
import 'package:open_parliament/models/member.dart';
import 'package:open_parliament/models/parliament_live_event.dart';
import 'package:open_parliament/models/recess_period.dart';
import 'package:open_parliament/models/speech.dart';
import 'package:open_parliament/services/parliamentary_data_service.dart';
import 'package:open_parliament/services/theme_service.dart';
import 'package:open_parliament/views/bill_view.dart';
import 'package:open_parliament/views/transcript_view.dart';

class _FakeTranscriptDataService implements ParliamentaryDataService {

  @override
  Future<List<Speech>?> getCachedSpeeches(String date) async => null;

  @override
  Future<void> refreshSitting(String date) async {}

  @override
  Future<List<Map<String, dynamic>>> searchHansardDebates(
    String query, {
    int limit = 20,
  }) async =>
      const [];
  final String debateTitle;
  int? billIdToReturn = 1234;

  _FakeTranscriptDataService({
    this.debateTitle = 'Renters (Reform) Bill: Second Reading',
  });

  @override
  Future<List<Speech>> getSpeeches(String date) async => [
        Speech(
          id: 's1',
          debateId: 'd1',
          debateTitle: debateTitle,
          memberId: 1,
          memberName: 'Alice',
          attributedTo: 'Alice (Lab)',
          speechText: 'I move that the Bill be now read a Second time.',
          orderIndex: 0,
        ),
      ];

  @override
  Future<List<Debate>> getDebatesForDate(String date) async => [
        Debate(
          id: 'd1',
          title: debateTitle,
          house: 'Commons',
          orderIndex: 0,
        ),
      ];

  @override
  Future<int?> findBillId(String billTitle) async => billIdToReturn;

  @override
  Future<Map<String, dynamic>?> fetchBillDetail(int id) async => {
        'billId': id,
        'shortTitle': 'Renters (Reform) Bill',
        'longTitle': 'A Bill to reform renting laws.',
        'currentHouse': 'Commons',
        'originatingHouse': 'Commons',
        'isAct': false,
        'sponsors': [],
      };

  @override
  Future<List<Map<String, dynamic>>> fetchBillStages(int id) async => [
        {
          'id': 1,
          'description': '2nd reading',
          'house': 'Commons',
        },
      ];

  @override
  Future<List<Map<String, dynamic>>> fetchBillNews(int id) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchBillPublications(int id) async => [];

  @override
  Future<List<Map<String, dynamic>>> fetchBillTypes() async => [];

  @override
  Future<List<Member>> getMembers() async => const [];

  @override
  Future<Uri?> billPageUrl(String billTitle) async => null;

  @override
  Future<List<Map<String, dynamic>>> fetchRecentBills({int skip = 0, int take = 40}) async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchBillsTimeline({
    int skip = 0,
    int take = 40,
    bool ascending = true,
    String? house,
    bool actsOnly = false,
    String? searchTerm,
  }) async =>
      const [];

  @override
  Future<List<Map<String, dynamic>>> fetchComingUpBills({int skip = 0, int take = 50}) async => const [];

  @override
  Future<List<Map<String, dynamic>>> searchBills(
    String query, {
    int take = 20,
  }) async =>
      const [];

  @override
  Future<List<BoundaryPolygon>> fetchConstituencyBoundaries() async => const [];

  @override
  Future<List<BoundaryPolygon>> fetchCouncilBoundaries() async => const [];

  @override
  Future<List<Council>> fetchCouncils() async => const [];

  @override
  Future<List<Councillor>> fetchCouncillors() async => const [];

  @override
  Future<CouncillorProfile?> fetchCouncillorProfile(Councillor councillor) async => null;

  @override
  Future<Member?> getMemberById(int memberId) async => null;

  @override
  Future<Map<String, int>> getSpeakerAliasMemberIds(Iterable<String> aliasKeys) async => {};

  @override
  Future<void> saveSpeakerAliasMemberIds(Map<String, int> aliasToMemberId) async {}

  @override
  Future<Member?> fetchAndCacheMemberById(int id) async => null;

  @override
  Future<List<Map<String, dynamic>>> searchCachedDebates(String query, {int limit = 40}) async => const [];

  @override
  Future<bool> isSittingCached(String date) async => true;

  @override
  Future<bool> hasSittingData(String date) async => true;

  @override
  Future<DateTime?> getPreviousSittingDate(String date) async => null;

  @override
  Future<DateTime?> getNextSittingDate(String date) async => null;

  @override
  Future<Set<DateTime>> getSittingDates(int year, int month) async => <DateTime>{};

  @override
  Future<List<RecessPeriod>> getRecessPeriods(int year, int month) async => const [];

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
  Future<List<Map<String, dynamic>>> fetchMemberContributions(int memberId) async => const [];

  @override
  Future<List<Map<String, dynamic>>> fetchMemberVoting(int memberId, {int house = 1, int page = 1}) async => const [];

  @override
  Future<List<double>?> geocodeConstituency(String constituencyName) async => null;

  @override
  Future<ConstituencyElectionResult?> fetchConstituencyResult(String constituencyName) async => null;

  @override
  Future<Council?> fetchCouncilForYear(String name, int year) async => null;

  @override
  int clearBillsCache() => 0;

  @override
  void dispose() {}
}

void main() {
  testWidgets('shows swipable bill tab when transcript debate relates to a bill', (tester) async {
    final fakeService = _FakeTranscriptDataService(
      debateTitle: 'Renters (Reform) Bill: Second Reading',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ThemeService()),
          Provider<ParliamentaryDataService>.value(value: fakeService),
        ],
        child: const MaterialApp(
          home: TranscriptView(
            date: '2024-11-04',
            displayDate: 'Monday, 4 November 2024',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify segmented bill tab bar is shown in the app bar
    expect(find.text('Transcript'), findsOneWidget);
    expect(find.text('Bill: Renters (Reform) Bill'), findsOneWidget);

    // Tap on the Bill Details tab to switch view to Page 1
    await tester.tap(find.text('Bill: Renters (Reform) Bill'));
    await tester.pumpAndSettle();

    // Verify BillDetailPane content is rendered
    expect(find.byType(BillDetailPane), findsOneWidget);
    expect(find.text('A Bill to reform renting laws.'), findsOneWidget);
  });

  testWidgets('does not show bill tab bar when debate has no related bill', (tester) async {
    final fakeService = _FakeTranscriptDataService(
      debateTitle: 'Oral Answers to Questions: Foreign Affairs',
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ThemeService()),
          Provider<ParliamentaryDataService>.value(value: fakeService),
        ],
        child: const MaterialApp(
          home: TranscriptView(
            date: '2024-11-04',
            displayDate: 'Monday, 4 November 2024',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Transcript'), findsNothing);
    expect(find.byType(BillDetailPane), findsNothing);
  });
}
