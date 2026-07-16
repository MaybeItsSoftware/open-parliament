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

/// Stub that records the URLs it was asked for, returning a fixed body.
class _CapturingHttpClient extends http.BaseClient {
  final String body;
  final List<Uri> requests = [];

  _CapturingHttpClient(this.body);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'text/html'},
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

  // ─── Constituency election results ───────────────────────────────────────

  group('MembersApiService constituency results', () {
    test('fetchConstituencyId returns the id of the matching constituency',
        () async {
      final stub = _StubHttpClient([
        _jsonResponse({
          'items': [
            {
              'value': {'id': 4120, 'name': 'Islington North'},
            },
            {
              'value': {'id': 4121, 'name': 'Islington South and Finsbury'},
            },
          ],
        }),
      ]);
      final service = MembersApiService(client: stub);
      final id = await service.fetchConstituencyId('Islington North');
      expect(id, 4120);
    });

    test('fetchConstituencyId matches ignoring case/punctuation, else first',
        () async {
      final stub = _StubHttpClient([
        _jsonResponse({
          'items': [
            {
              'value': {'id': 99, 'name': 'Some Other Seat'},
            },
            {
              'value': {'id': 7, 'name': 'Ashton-under-Lyne'},
            },
          ],
        }),
      ]);
      final service = MembersApiService(client: stub);
      final id = await service.fetchConstituencyId('ashton under lyne');
      expect(id, 7);
    });

    test('fetchConstituencyId returns null when no items', () async {
      final stub = _StubHttpClient([
        _jsonResponse({'items': []}),
      ]);
      final service = MembersApiService(client: stub);
      expect(await service.fetchConstituencyId('Nowhere'), isNull);
    });

    test('fetchLatestElectionResult parses the result and candidates',
        () async {
      final stub = _StubHttpClient([
        _jsonResponse({
          'value': {
            'electionTitle': '2024 General Election',
            'electionDate': '2024-07-04T00:00:00',
            'result': 'Lab Hold',
            'majority': 7247,
            'turnout': 49006,
            'electorate': 72852,
            'candidates': [
              {
                'name': 'A Winner',
                'party': {'name': 'Labour', 'abbreviation': 'Lab'},
                'votes': 24120,
                'voteShare': 49.2,
                'rankOrder': 1,
              },
            ],
          },
        }),
      ]);
      final service = MembersApiService(client: stub);
      final result = await service.fetchLatestElectionResult(4120);
      expect(result, isNotNull);
      expect(result!.electionTitle, '2024 General Election');
      expect(result.majority, 7247);
      expect(result.candidates.single.name, 'A Winner');
    });

    test('fetchLatestElectionResult returns null on HTTP error', () async {
      final stub = _StubHttpClient([http.Response('nope', 404)]);
      final service = MembersApiService(client: stub);
      expect(await service.fetchLatestElectionResult(4120), isNull);
    });
  });

  // ─── CouncilControlApiService year plumbing ──────────────────────────────

  group('CouncilControlApiService', () {
    const htmlCurrent = '''
      <table>
        <tr><th>Type</th><th>Council</th><th>Control</th><th>Lab</th><th>Total</th></tr>
        <tr><td>District</td><td>Adur</td><td>LAB</td><td>17</td><td>29</td></tr>
      </table>
    ''';

    const html16 = '''
      <table>
        <tr><td>Adur</td><td>29</td><td>
          <div class="stacked-bar-graph">
            <span class="pop con" style="width: 50%"><span class="poptext">17</span></span>
          </div>
        </td></tr>
      </table>
    ''';

    const html73 = '''
      <table>
        <tr><td>Adur</td><td>Con</td><td>29</td><td>
          <div class="stacked-bar-graph">
            <span class="pop con" style="width: 50%"><span class="poptext">20</span></span>
          </div>
        </td></tr>
      </table>
    ''';

    test('fetchCouncils without a year requests the current table and parses', () async {
      final client = _CapturingHttpClient(htmlCurrent);
      final service = CouncilControlApiService(client: client);
      final councils = await service.fetchCouncils();
      expect(client.requests.single.path, '/councils.php');
      expect(client.requests.single.queryParameters['y'], '0');
      expect(councils.single.name, 'Adur');
      expect(councils.single.control, 'LAB');
    });

    test('fetchCouncils with year >= 2016 requests historyYear16 and parses', () async {
      final client = _CapturingHttpClient(html16);
      final service = CouncilControlApiService(client: client);
      final councils = await service.fetchCouncils(year: 2018);
      expect(client.requests.single.path, '/historyYear16.php');
      expect(client.requests.single.queryParameters['y'], '2018');
      expect(councils.single.name, 'Adur');
      expect(councils.single.control, 'CON');
    });

    test('fetchCouncils with year < 2016 requests historyYear73 and parses', () async {
      final client = _CapturingHttpClient(html73);
      final service = CouncilControlApiService(client: client);
      final councils = await service.fetchCouncils(year: 2015);
      expect(client.requests.single.path, '/historyYear73.php');
      expect(client.requests.single.queryParameters['y'], '2015');
      expect(councils.single.name, 'Adur');
      expect(councils.single.control, 'Con');
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

  // ─── WhatsOnApiService tests ────────────────────────────────────────────

  group('WhatsOnApiService', () {
    test('fetchNonSittingPeriods parses events into recess periods', () async {
      final stub = _StubHttpClient([
        _jsonResponse([
          {
            'Description': 'Christmas recess',
            'StartDate': '2024-12-20T00:00:00',
            'EndDate': '2025-01-06T00:00:00',
            'House': 'Commons',
          },
          {
            // No description or house — falls back to "Recess" and the
            // queried house.
            'StartDate': '2024-12-01T00:00:00',
          },
          {
            // Unparsable start date — skipped.
            'Description': 'Broken',
            'StartDate': 'not-a-date',
          },
        ]),
      ]);
      final service = WhatsOnApiService(client: stub);

      final periods = await service.fetchNonSittingPeriods(
        startDate: '2024-12-01',
        endDate: '2024-12-31',
        house: 'Commons',
      );

      expect(periods, hasLength(2));
      expect(periods[0].description, 'Christmas recess');
      expect(periods[0].startDate, DateTime(2024, 12, 20));
      expect(periods[0].endDate, DateTime(2025, 1, 6));
      expect(periods[0].house, 'Commons');
      expect(periods[1].description, 'Recess');
      expect(periods[1].startDate, DateTime(2024, 12, 1));
      expect(periods[1].endDate, DateTime(2024, 12, 1));
      expect(periods[1].house, 'Commons');
    });

    test('fetchNonSittingPeriods sends the date range and house', () async {
      final capturing = _CapturingHttpClient('[]');
      final service = WhatsOnApiService(client: capturing);

      await service.fetchNonSittingPeriods(
        startDate: '2024-12-01',
        endDate: '2024-12-31',
        house: 'Lords',
      );

      final uri = capturing.requests.single;
      expect(uri.host, 'whatson-api.parliament.uk');
      expect(uri.path, '/calendar/events/nonsitting.json');
      expect(uri.queryParameters['startDate'], '2024-12-01');
      expect(uri.queryParameters['endDate'], '2024-12-31');
      expect(uri.queryParameters['house'], 'Lords');
    });

    test('fetchNonSittingPeriods returns empty list on HTTP error', () async {
      final stub = _StubHttpClient([http.Response('', 500)]);
      final service = WhatsOnApiService(client: stub);

      final periods = await service.fetchNonSittingPeriods(
        startDate: '2024-12-01',
        endDate: '2024-12-31',
        house: 'Commons',
      );

      expect(periods, isEmpty);
    });

    test('fetchNonSittingPeriods returns empty list on malformed body',
        () async {
      final stub = _StubHttpClient([http.Response('not json', 200)]);
      final service = WhatsOnApiService(client: stub);

      final periods = await service.fetchNonSittingPeriods(
        startDate: '2024-12-01',
        endDate: '2024-12-31',
        house: 'Commons',
      );

      expect(periods, isEmpty);
    });
  });
}
