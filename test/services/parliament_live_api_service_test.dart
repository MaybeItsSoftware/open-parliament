import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_hansard/services/api_services.dart';

void main() {
  group('ParliamentLiveApiService.parseSearchHtml', () {
    test('extracts (guid, title) pairs from the search page markup', () {
      const html = '''
        <a href="https://parliamentlive.tv/Event/Index/cb8ee89c-cdfc-4cd8-97a0-d6fd304b765f" class="search-thumb-inner">
          <img src="..." alt="Courts and Tribunals Bill" class="img-responsive">
        </a>
        <a href="https://parliamentlive.tv/Event/Index/0c796d74-6cea-4b8a-8013-808ad39d6503" class="search-thumb-inner">
          <img src="..." alt="House of Commons" class="img-responsive">
        </a>
      ''';

      final events = ParliamentLiveApiService.parseSearchHtml(html);
      expect(events, hasLength(2));
      expect(events[0].guid, 'cb8ee89c-cdfc-4cd8-97a0-d6fd304b765f');
      expect(events[0].title, 'Courts and Tribunals Bill');
      expect(events[1].guid, '0c796d74-6cea-4b8a-8013-808ad39d6503');
      expect(events[1].title, 'House of Commons');
    });

    test('decodes HTML entities in titles and dedupes by guid', () {
      const html = '''
        <a href="https://parliamentlive.tv/Event/Index/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa">
          <img alt="House of Commons &amp; Lords" />
        </a>
        <a href="https://parliamentlive.tv/Event/Index/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa">
          <img alt="House of Commons &amp; Lords" />
        </a>
      ''';

      final events = ParliamentLiveApiService.parseSearchHtml(html);
      expect(events, hasLength(1));
      expect(events.first.title, 'House of Commons & Lords');
    });
  });

  group('ParliamentLiveApiService.fetchEventsForDate', () {
    test('formats the date as DD/MM/YYYY and caches the result', () async {
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.host, 'parliamentlive.tv');
        expect(request.url.path, '/Search');
        expect(request.url.queryParameters['Start'], '23/04/2026');
        expect(request.url.queryParameters['End'], '23/04/2026');
        return http.Response(
          '<a href="https://parliamentlive.tv/Event/Index/'
          'cb8ee89c-cdfc-4cd8-97a0-d6fd304b765f">'
          '<img alt="Courts and Tribunals Bill" /></a>',
          200,
        );
      });

      final service = ParliamentLiveApiService(client: client);
      final first = await service.fetchEventsForDate('2026-04-23');
      final second = await service.fetchEventsForDate('2026-04-23');

      expect(first, hasLength(1));
      expect(first.single.guid, 'cb8ee89c-cdfc-4cd8-97a0-d6fd304b765f');
      expect(second, same(first));
      expect(calls, 1);
    });

    test('returns an empty list when the search page returns non-200',
        () async {
      final client =
          MockClient((_) async => http.Response('<html/>', 503));
      final service = ParliamentLiveApiService(client: client);
      final events = await service.fetchEventsForDate('2026-04-23');
      expect(events, isEmpty);
    });

    test('returns an empty list when the date is malformed', () async {
      final client = MockClient((_) async {
        fail('network must not be hit for malformed input');
      });
      final service = ParliamentLiveApiService(client: client);
      final events = await service.fetchEventsForDate('not-a-date');
      expect(events, isEmpty);
    });
  });
}
