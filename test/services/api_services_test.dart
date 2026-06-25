import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_hansard/services/api_services.dart';

// ─── Minimal HTTP client stub ─────────────────────────────────────────────

/// A simple stub HTTP client that returns a fixed response for every request.
class _StubHttpClient extends http.BaseClient {
  final List<http.Response> responses;
  int _callIndex = 0;

  _StubHttpClient(this.responses);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = responses[_callIndex.clamp(0, responses.length - 1)];
    _callIndex++;
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
    );
  }
}

http.Response _jsonResponse(Object body, {int statusCode = 200}) {
  return http.Response(
    jsonEncode(body),
    statusCode,
    headers: {'content-type': 'application/json'},
  );
}

// ─── MembersApiService tests ──────────────────────────────────────────────

void main() {
  group('MembersApiService', () {
    test('fetchAllMembers returns all pages', () async {
      final stub = _StubHttpClient([
        // Page 1: 2 members, totalResults = 3
        _jsonResponse({
          'totalResults': 3,
          'items': [
            {
              'value': {
                'id': 1,
                'nameDisplayAs': 'Alice',
                'thumbnailUrl': null,
                'latestParty': {'name': 'Labour', 'abbreviation': 'Lab'},
              },
            },
            {
              'value': {
                'id': 2,
                'nameDisplayAs': 'Bob',
                'thumbnailUrl': null,
                'latestParty': {
                  'name': 'Conservative',
                  'abbreviation': 'Con',
                },
              },
            },
          ],
        }),
        // Page 2: 1 member (exhausts pagination)
        _jsonResponse({
          'totalResults': 3,
          'items': [
            {
              'value': {
                'id': 3,
                'nameDisplayAs': 'Charlie',
                'thumbnailUrl': null,
                'latestParty': {'name': 'SNP', 'abbreviation': 'SNP'},
              },
            },
          ],
        }),
        // Sentinel empty page (should not be reached)
        _jsonResponse({'totalResults': 3, 'items': []}),
      ]);

      final service = MembersApiService(client: stub);
      final members = await service.fetchAllMembers();

      expect(members, hasLength(3));
      expect(
          members.map((m) => m.name), containsAll(['Alice', 'Bob', 'Charlie']));
    });

    test('fetchAllMembers returns empty list on HTTP error', () async {
      final stub = _StubHttpClient([http.Response('Error', 500)]);
      final service = MembersApiService(client: stub);
      final members = await service.fetchAllMembers();
      expect(members, isEmpty);
    });

    test('fetchAllMembers skips malformed items', () async {
      final stub = _StubHttpClient([
        _jsonResponse({
          'totalResults': 2,
          'items': [
            {
              'value': {
                'id': 1,
                'nameDisplayAs': 'Valid MP',
                'latestParty': {'name': 'Labour', 'abbreviation': 'Lab'},
              },
            },
            {'value': null}, // malformed – should be skipped
          ],
        }),
        _jsonResponse({'totalResults': 2, 'items': []}),
      ]);

      final service = MembersApiService(client: stub);
      final members = await service.fetchAllMembers();
      expect(members, hasLength(1));
      expect(members.first.name, 'Valid MP');
    });
  });

  // ─── HansardApiService tests ─────────────────────────────────────────────

  group('HansardApiService', () {
    test('fetchSittingDebates builds debates from overview endpoints',
        () async {
      final stub = _StubHttpClient([
        // /overview/sectionsforday.json
        _jsonResponse(['Debate']),
        // /overview/sectiontrees.json
        _jsonResponse([
          {
            'Title': 'Commons Chamber',
            'SectionTreeItems': [
              {
                'ParentId': null,
                'ExternalId': 'abc',
                'Title': 'Commons Chamber',
              },
            ],
          },
        ]),
        // Lords sections
        _jsonResponse([]),
      ]);

      final service = HansardApiService(client: stub);
      final debates = await service.fetchSittingDebates('2024-11-04');

      expect(debates, hasLength(1));
      expect(debates[0].id, 'abc');
      expect(debates[0].title, 'Commons Chamber');
      expect(debates[0].house, 'Commons');
    });

    test('fetchSittingDebates returns empty list on 404', () async {
      final stub = _StubHttpClient([http.Response('', 404)]);
      final service = HansardApiService(client: stub);
      final debates = await service.fetchSittingDebates('2024-11-04');
      expect(debates, isEmpty);
    });

    test('fetchSittingDebates throws HansardApiException on non-404 error',
        () async {
      final stub = _StubHttpClient([http.Response('', 500)]);
      final service = HansardApiService(client: stub);

      await expectLater(
        service.fetchSittingDebates('2024-11-04'),
        throwsA(isA<HansardApiException>()),
      );
    });

    test('fetchDebateSpeeches parses nested ChildDebates Items', () async {
      final stub = _StubHttpClient([
        _jsonResponse({
          'Overview': {'ExtId': 'root', 'Title': 'Commons Chamber'},
          'Items': [],
          'ChildDebates': [
            {
              'Overview': {'ExtId': 'abc', 'Title': 'PMQs'},
              'Items': [
                {
                  'ItemId': 'item-1',
                  'MemberId': 172,
                  'MemberName': 'Adam Smith',
                  'AttributedTo': 'Adam Smith (Labour)',
                  'Value': '<p>I thank the Minister.</p>',
                  'Timecode': '10:00:00',
                },
              ],
              'ChildDebates': [],
            },
          ],
        }),
      ]);

      final service = HansardApiService(client: stub);
      final speeches = await service.fetchDebateSpeeches('abc', 'PMQs');

      expect(speeches, hasLength(1));
      expect(speeches[0].id, 'item-1');
      expect(speeches[0].debateId, 'abc');
      expect(speeches[0].debateTitle, 'PMQs');
      expect(speeches[0].memberId, 172);
      expect(speeches[0].memberName, 'Adam Smith');
      expect(speeches[0].speechText, isNot(contains('<p>')));
      expect(speeches[0].speechText, contains('I thank the Minister.'));
    });

    test('fetchDebateSpeeches returns empty list on 404', () async {
      final stub = _StubHttpClient([http.Response('', 404)]);
      final service = HansardApiService(client: stub);
      final speeches = await service.fetchDebateSpeeches('abc', 'PMQs');
      expect(speeches, isEmpty);
    });

    test('fetchDebateSpeeches throws HansardApiException on HTTP error',
        () async {
      final stub = _StubHttpClient([http.Response('', 500)]);
      final service = HansardApiService(client: stub);

      await expectLater(
        service.fetchDebateSpeeches('abc', 'PMQs'),
        throwsA(isA<HansardApiException>()),
      );
    });

    test('fetchSittingCalendar parses ItemDate list into dates', () async {
      final stub = _StubHttpClient([
        _jsonResponse([
          {
            'House': 'Commons',
            'ItemDate': '2024-11-04T00:00:00',
            'Metadata': null,
          },
          {
            'House': 'Commons',
            'ItemDate': '2024-11-05T00:00:00',
            'Metadata': null,
          },
        ]),
      ]);
      final service = HansardApiService(client: stub);

      final dates = await service.fetchSittingCalendar(2024, 11, 'Commons');

      expect(dates, [DateTime(2024, 11, 4), DateTime(2024, 11, 5)]);
    });

    test('fetchSittingCalendar returns empty list on 404', () async {
      final stub = _StubHttpClient([http.Response('', 404)]);
      final service = HansardApiService(client: stub);
      final dates = await service.fetchSittingCalendar(2024, 11, 'Commons');
      expect(dates, isEmpty);
    });

    test('fetchSittingCalendar throws HansardApiException on non-404 error',
        () async {
      final stub = _StubHttpClient([http.Response('', 500)]);
      final service = HansardApiService(client: stub);

      await expectLater(
        service.fetchSittingCalendar(2024, 11, 'Commons'),
        throwsA(isA<HansardApiException>()),
      );
    });
  });
}
