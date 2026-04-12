import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/debate.dart';
import 'package:open_hansard/models/member.dart';
import 'package:open_hansard/models/speech.dart';
import 'package:open_hansard/services/parliamentary_data_service.dart';
import 'package:open_hansard/viewmodels/date_selector_viewmodel.dart';
import 'package:open_hansard/viewmodels/transcript_viewmodel.dart';

// ─── Manual mocks ──────────────────────────────────────────────────────────

class _FakeParliamentaryDataService implements ParliamentaryDataService {
  bool isCachedResult = false;
  bool hasSittingDataResult = true;
  DateTime? previousSittingDateResult;
  DateTime? nextSittingDateResult;
  List<Speech> speechesResult = [];
  List<Member> membersResult = [];
  Map<int, Member?> memberResults = {};
  Map<String, int> speakerAliasMemberIds = {};
  Map<String, int> lastSavedSpeakerAliasMemberIds = {};
  Object? speechesError;
  Duration speechesDelay = Duration.zero;

  @override
  Future<bool> isSittingCached(String date) async => isCachedResult;

  @override
  Future<bool> hasSittingData(String date) async => hasSittingDataResult;

  @override
  Future<DateTime?> getPreviousSittingDate(String date) async =>
      previousSittingDateResult;

  @override
  Future<DateTime?> getNextSittingDate(String date) async =>
      nextSittingDateResult;

  @override
  Future<List<Speech>> getSpeeches(String date) async {
    if (speechesDelay > Duration.zero) {
      await Future<void>.delayed(speechesDelay);
    }
    if (speechesError != null) throw speechesError!;
    return speechesResult;
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
  Future<List<Debate>> getDebatesForDate(String date) async => const [];

  @override
  Future<int> wipeDebateCache() async => 0;

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
}
