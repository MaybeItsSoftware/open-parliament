import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/member.dart';
import 'package:open_hansard/models/speech.dart';
import 'package:open_hansard/services/parliamentary_data_service.dart';
import 'package:open_hansard/viewmodels/date_selector_viewmodel.dart';
import 'package:open_hansard/viewmodels/transcript_viewmodel.dart';

// ─── Manual mocks ──────────────────────────────────────────────────────────

class _FakeParliamentaryDataService implements ParliamentaryDataService {
  bool isCachedResult = false;
  List<Speech> speechesResult = [];
  Map<int, Member?> memberResults = {};
  Object? speechesError;

  @override
  Future<bool> isSittingCached(String date) async => isCachedResult;

  @override
  Future<List<Speech>> getSpeeches(String date) async {
    if (speechesError != null) throw speechesError!;
    return speechesResult;
  }

  @override
  Future<Member?> getMemberById(int memberId) async =>
      memberResults[memberId];

  @override
  Future<List<Member>> getMembers() async => [];

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
  });

  // ─── TranscriptViewModel tests ───────────────────────────────────────────

  group('TranscriptViewModel', () {
    late _FakeParliamentaryDataService fakeService;
    late TranscriptViewModel vm;

    const testDate = '2024-11-04';

    Speech makeSpeech({
      required String id,
      required String memberName,
      int? memberId,
      int orderIndex = 0,
    }) {
      return Speech(
        id: id,
        debateId: 'debate-1',
        debateTitle: 'Test Debate',
        memberId: memberId,
        memberName: memberName,
        attributedTo: memberName,
        speechText: 'Some speech text.',
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
        1: const Member(id: 1, name: 'Alice', party: 'Labour', partyAbbreviation: 'Lab'),
        2: const Member(id: 2, name: 'Bob', party: 'Conservative', partyAbbreviation: 'Con'),
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
  });
}
