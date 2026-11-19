import 'package:flutter_test/flutter_test.dart';
import 'package:open_parliament/models/amendment.dart';
import 'package:open_parliament/services/api_services.dart';
import 'package:open_parliament/services/parliamentary_data_service.dart';

/// Two bills share a title across sessions; only bill 20 sat on the vote day.
class _FakeBills extends BillsApiService {
  final List<String> calls = [];

  @override
  Future<List<Map<String, dynamic>>> searchBills(
    String query, {
    int take = 20,
  }) async {
    calls.add('search:$query');
    return [
      {'billId': 99, 'shortTitle': 'Broadcasting (Listed Sporting Events) Bill'},
      {'billId': 10, 'shortTitle': 'Railways Bill'},
      {'billId': 20, 'shortTitle': 'Railways Bill [HL]'},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> fetchBillStages(
    int id, {
    int take = 30,
  }) async {
    calls.add('stages:$id');
    if (id != 20) return const [];
    return [
      {
        'id': 7,
        'description': 'Report stage',
        'house': 'Lords',
        'stageSittings': [
          {'date': '2026-11-18T00:00:00'},
        ],
      },
    ];
  }

  @override
  Future<Map<String, dynamic>?> fetchStageAmendment(
    int billId,
    int stageId,
    String number,
  ) async {
    calls.add('amendment:$billId/$stageId/$number');
    if (number != '16') return null;
    return {
      'amendmentId': 2,
      'marshalledListText': '16',
      'amendmentType': 'EditBillBody',
      'decision': 'Agreed',
      'summaryText': ['truncated'],
      'sponsors': [
        {'name': 'Second', 'sortOrder': 2},
        {'name': 'Lead', 'sortOrder': 1},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>?> fetchAmendmentDetail(
    int billId,
    int stageId,
    int amendmentId,
  ) async =>
      {
        'amendmentId': amendmentId,
        'marshalledListText': null, // detail sometimes nulls list fields
        'explanatoryText': '<p>Plain words.</p>',
        'amendmentLines': [
          {'text': 'page 71, after “a” insert “b”', 'indentation': 0},
          {'text': '', 'isImage': true},
        ],
      };
}

class _FakeLords extends LordsVotesApiService {
  @override
  Future<Map<String, dynamic>?> fetchDivision(int id) async => {
        'amendmentMotionNotes':
            '<p>Baroness X moved amendment 16, after &ldquo;a&rdquo; to '
                'insert &ldquo;b&rdquo;.</p>',
      };
}

void main() {
  test('Lords division resolves via notes, date-confirmed bill and stage',
      () async {
    final bills = _FakeBills();
    final service = ParliamentaryDataService(
      billsApiService: bills,
      lordsVotesApiService: _FakeLords(),
    );

    final result = await service.fetchDivisionAmendment(
      divisionId: 3740,
      house: 2,
      title: 'Railways Bill',
      date: DateTime(2026, 11, 18),
    );

    expect(result.motionText, startsWith('Baroness X moved amendment 16'));
    expect(result.motionText, contains('“a”'));
    expect(result.billId, 20);
    expect(result.stageName, 'Report stage');
    final a = result.amendment!;
    expect(a.number, '16');
    expect(a.decisionLabel, 'Agreed');
    expect(a.sponsors, ['Lead', 'Second']);
    expect(a.explanatoryText, contains('Plain words'));
    expect(a.lines.map((l) => l.text), ['page 71, after “a” insert “b”']);
    // Bill 99's title doesn't match, so its stages are never fetched.
    expect(bills.calls, isNot(contains('stages:99')));
  });

  test('Commons division with no numbered amendment says so', () async {
    final service = ParliamentaryDataService(billsApiService: _FakeBills());
    final result = await service.fetchDivisionAmendment(
      divisionId: 1,
      house: 1,
      title: 'Railways Bill: Third Reading',
      date: DateTime(2026, 11, 18),
    );
    expect(result.amendment, isNull);
    expect(result.unavailableReason, isNotNull);
  });

  test('Commons vote on a Lords Amendment links the bill only', () async {
    final service = ParliamentaryDataService(billsApiService: _FakeBills());
    // Fake stages are Lords-only, so a Commons consideration finds nothing.
    final result = await service.fetchDivisionAmendment(
      divisionId: 1,
      house: 1,
      title: 'Railways Bill: motion to disagree with Lords Amendment 3',
      date: DateTime(2026, 11, 18),
    );
    expect(result.amendment, isNull);
    expect(result.unavailableReason, contains('match'));
  });

  test('stage amendments are looked up by number on the matched stage',
      () async {
    final bills = _FakeBills();
    await ParliamentaryDataService(
      billsApiService: bills,
      lordsVotesApiService: _FakeLords(),
    ).fetchDivisionAmendment(
      divisionId: 1,
      house: 2,
      title: 'Railways Bill',
      date: DateTime(2026, 11, 18),
    );
    expect(bills.calls, contains('amendment:20/7/16'));
  });

  test('Amendment.decisionLabel hides NoDecision', () {
    expect(
      Amendment.fromJson(const {'decision': 'NoDecision'}).decisionLabel,
      isNull,
    );
    expect(
      Amendment.fromJson(const {'decision': 'NotCalled'}).decisionLabel,
      'Not Called',
    );
  });
}
