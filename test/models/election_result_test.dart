import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/election_result.dart';

void main() {
  group('ConstituencyElectionResult.fromJson', () {
    // Shape mirrors members-api .../ElectionResult/latest. The API wraps the
    // payload in a `value` object, like the rest of the Members API.
    Map<String, dynamic> sample() => {
          'value': {
            'electionId': 422,
            'electionTitle': '2024 General Election',
            'electionDate': '2024-07-04T00:00:00',
            'constituencyName': 'Islington North',
            'result': 'Ind Gain',
            'majority': 7247,
            'turnout': 49006,
            'electorate': 72852,
            'candidates': [
              {
                'name': 'Jeremy Corbyn',
                'party': {'name': 'Independent', 'abbreviation': 'Ind'},
                'votes': 24120,
                'voteShare': 49.2,
                'rankOrder': 1,
                'resultChange': '',
              },
              {
                'name': 'Praful Nargund',
                'party': {'name': 'Labour', 'abbreviation': 'Lab'},
                'votes': 16873,
                'voteShare': 34.4,
                'rankOrder': 2,
                'resultChange': '-29.9',
              },
            ],
          },
        };

    test('parses the wrapped election summary', () {
      final result = ConstituencyElectionResult.fromJson(sample());
      expect(result.electionTitle, '2024 General Election');
      expect(result.electionDate, DateTime.parse('2024-07-04T00:00:00'));
      expect(result.result, 'Ind Gain');
      expect(result.majority, 7247);
      expect(result.turnout, 49006);
      expect(result.electorate, 72852);
      expect(result.candidates, hasLength(2));
    });

    test('parses candidates sorted by rank with party and votes', () {
      final result = ConstituencyElectionResult.fromJson(sample());
      final winner = result.candidates.first;
      expect(winner.name, 'Jeremy Corbyn');
      expect(winner.party, 'Independent');
      expect(winner.partyAbbreviation, 'Ind');
      expect(winner.votes, 24120);
      expect(winner.voteShare, closeTo(49.2, 0.001));
      expect(winner.rankOrder, 1);
      expect(winner.isWinner, isTrue);
      expect(result.candidates[1].isWinner, isFalse);
    });

    test('accepts an unwrapped payload (no value envelope)', () {
      final unwrapped = sample()['value'] as Map<String, dynamic>;
      final result = ConstituencyElectionResult.fromJson(unwrapped);
      expect(result.electionTitle, '2024 General Election');
      expect(result.candidates, hasLength(2));
    });

    test('orders candidates by rank even when JSON is unsorted', () {
      final json = sample();
      final value = json['value'] as Map<String, dynamic>;
      value['candidates'] = (value['candidates'] as List).reversed.toList();
      final result = ConstituencyElectionResult.fromJson(json);
      expect(result.candidates.first.rankOrder, 1);
      expect(result.candidates.last.rankOrder, 2);
    });

    test('tolerates missing optional fields', () {
      final result = ConstituencyElectionResult.fromJson({
        'value': {
          'electionTitle': '2024 General Election',
          'candidates': [],
        },
      });
      expect(result.majority, 0);
      expect(result.turnout, 0);
      expect(result.electorate, 0);
      expect(result.candidates, isEmpty);
      expect(result.result, '');
    });
  });
}
