import 'package:flutter_test/flutter_test.dart';
import 'package:open_parliament/models/party_stats.dart';
import 'package:open_parliament/services/parliamentary_data_service.dart';
import 'package:open_parliament/services/party_service.dart';
import 'package:open_parliament/viewmodels/party_viewmodel.dart';
import 'package:open_parliament/viewmodels/settings_viewmodel.dart';

class _FakePartyService extends PartyService {
  Object? currentError;
  Object? historicalError;
  String? requestedToken;

  @override
  Future<PartyStats> loadCurrentStats(String partyName) async {
    if (currentError != null) throw currentError!;
    return PartyStats(partyName: partyName, partyToken: 'lab', mpCount: 400);
  }

  @override
  Future<Map<String, HistoricalTrend>> loadHistoricalTrends(
    String partyToken,
  ) async {
    requestedToken = partyToken;
    if (historicalError != null) throw historicalError!;
    return {
      'mps': const HistoricalTrend(
        label: 'MPs',
        points: [
          HistoricalDataPoint(year: 2019, value: 202),
          HistoricalDataPoint(year: 2024, value: 411),
        ],
      ),
    };
  }
}

class _FakeDataService implements ParliamentaryDataService {
  final calls = <String>[];

  @override
  Future<int> wipeDebateCache() async {
    calls.add('debates');
    return 3;
  }

  @override
  Future<int> clearMapBoundaries() async {
    calls.add('boundaries');
    return 2;
  }

  @override
  Future<int> clearCouncilData() async {
    calls.add('councils');
    return 1;
  }

  @override
  Future<int> clearCachedMembers() async {
    calls.add('members');
    return 650;
  }

  @override
  int clearBillsCache() {
    calls.add('bills');
    return 4;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('PartyViewModel', () {
    test('loads current stats, then merges historical trends', () async {
      final service = _FakePartyService();
      final vm = PartyViewModel(service, partyName: 'Labour');
      final loadingStates = <bool>[];
      vm.addListener(() => loadingStates.add(vm.isLoadingHistorical));

      await vm.load();

      expect(vm.error, isNull);
      expect(vm.isLoadingCurrent, isFalse);
      expect(vm.isLoadingHistorical, isFalse);
      expect(vm.stats!.mpCount, 400);
      expect(vm.stats!.mpTrend.latestValue, 411);
      expect(service.requestedToken, 'lab');
      expect(loadingStates, contains(true));
    });

    test('a current-stats failure sets error and stops loading', () async {
      final service = _FakePartyService()..currentError = Exception('down');
      final vm = PartyViewModel(service, partyName: 'Labour');
      await vm.load();
      expect(vm.error, contains('down'));
      expect(vm.stats, isNull);
      expect(vm.isLoadingCurrent, isFalse);
      expect(service.requestedToken, isNull);
    });

    test(
      'a historical failure keeps current stats and sets no error',
      () async {
        final service =
            _FakePartyService()..historicalError = Exception('slow');
        final vm = PartyViewModel(service, partyName: 'Labour');
        await vm.load();
        expect(vm.error, isNull);
        expect(vm.stats!.mpCount, 400);
        expect(vm.stats!.mpTrend.points, isEmpty);
        expect(vm.isLoadingHistorical, isFalse);
      },
    );
  });

  group('SettingsViewModel', () {
    test(
      'each action delegates to the data service and returns its count',
      () async {
        final service = _FakeDataService();
        final vm = SettingsViewModel(service);
        expect(await vm.clearCachedDebates(), 3);
        expect(await vm.clearMapBoundaries(), 2);
        expect(await vm.clearCouncilData(), 1);
        expect(await vm.clearCachedMembers(), 650);
        expect(await vm.clearBillsCache(), 4);
        expect(service.calls, [
          'debates',
          'boundaries',
          'councils',
          'members',
          'bills',
        ]);
      },
    );
  });
}
