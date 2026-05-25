import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/parliament_live_event.dart';
import 'package:open_hansard/utils/parliament_live.dart';

void main() {
  group('parliamentLiveSearchUrl', () {
    test('builds Day + House for Commons sittings', () {
      final uri = parliamentLiveSearchUrl(date: '2026-04-23', house: 'Commons');
      expect(uri.host, 'parliamentlive.tv');
      expect(uri.path, '/Search');
      expect(uri.queryParameters, {
        'Day': '2026-04-23',
        'House': 'Commons',
      });
    });

    test('maps Westminster Hall to Commons', () {
      final uri = parliamentLiveSearchUrl(
        date: '2026-04-23',
        house: 'Westminster Hall',
      );
      expect(uri.queryParameters['House'], 'Commons');
    });

    test('maps Grand Committee to Lords', () {
      final uri = parliamentLiveSearchUrl(
        date: '2026-04-23',
        house: 'Grand Committee',
      );
      expect(uri.queryParameters['House'], 'Lords');
    });

    test('omits House when both chambers sat', () {
      final uri = parliamentLiveSearchUrl(
        date: '2026-04-23',
        house: 'Commons & Lords',
      );
      expect(uri.queryParameters.containsKey('House'), isFalse);
      expect(uri.queryParameters['Day'], '2026-04-23');
    });

    test('omits House when null', () {
      final uri = parliamentLiveSearchUrl(date: '2026-04-23');
      expect(uri.queryParameters.containsKey('House'), isFalse);
    });
  });

  group('parliamentLiveSectionHasVideo', () {
    test('returns false for written-only sections', () {
      expect(parliamentLiveSectionHasVideo('WMS'), isFalse);
      expect(parliamentLiveSectionHasVideo('Correction'), isFalse);
      expect(parliamentLiveSectionHasVideo('Written Statements'), isFalse);
    });

    test('returns true for debate sections or unknown', () {
      expect(parliamentLiveSectionHasVideo('Debate'), isTrue);
      expect(parliamentLiveSectionHasVideo(null), isTrue);
      expect(parliamentLiveSectionHasVideo(''), isTrue);
    });
  });

  group('parliamentLiveSectionUnavailableMessage', () {
    test('explains written statements vs corrections', () {
      expect(
        parliamentLiveSectionUnavailableMessage('WMS'),
        contains('Written statements'),
      );
      expect(
        parliamentLiveSectionUnavailableMessage('Written Corrections'),
        contains('Written corrections'),
      );
    });
  });

  group('parliamentLiveEventUrl', () {
    const guid = 'cb8ee89c-cdfc-4cd8-97a0-d6fd304b765f';

    test('builds the canonical /event/index/{guid} url', () {
      final uri = parliamentLiveEventUrl(guid);
      expect(uri.host, 'parliamentlive.tv');
      expect(uri.path, '/event/index/$guid');
      expect(uri.queryParameters, isEmpty);
    });

    test('appends ?in= when a timecode is supplied', () {
      final uri = parliamentLiveEventUrl(guid, timecode: '14:32:05');
      expect(uri.queryParameters['in'], '14:32:05');
    });
  });

  group('parliamentLivePlayerUrl', () {
    const guid = 'cb8ee89c-cdfc-4cd8-97a0-d6fd304b765f';

    test('builds the standalone player URL with autoplay params', () {
      final uri = parliamentLivePlayerUrl(guid);
      expect(uri.host, 'videoplayback.parliamentlive.tv');
      expect(uri.path, '/Player/Index/$guid');
      expect(uri.queryParameters, const {
        'audioOnly': 'False',
        'autoStart': 'True',
        'script': 'True',
      });
      expect(uri.fragment, isEmpty);
    });

    test('adds an encoded parent event URL fragment when provided', () {
      final parent = parliamentLiveEventUrl(guid);
      final uri = parliamentLivePlayerUrl(guid, parentUrl: parent);
      expect(uri.fragment, Uri.encodeComponent(parent.toString()));
    });
  });

  group('bestParliamentLiveMatch', () {
    final events = [
      const ParliamentLiveEvent(
        guid: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        title: 'Courts and Tribunals Bill',
      ),
      const ParliamentLiveEvent(
        guid: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        title: 'Westminster Hall',
      ),
      const ParliamentLiveEvent(
        guid: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        title: 'Foreign Affairs Committee',
      ),
      const ParliamentLiveEvent(
        guid: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
        title: 'BSL - House of Commons',
      ),
    ];

    test('matches Hansard sitting-suffix titles to bare event titles', () {
      final match = bestParliamentLiveMatch(
        'Courts and Tribunals Bill (Ninth sitting)',
        events,
      );
      expect(match?.guid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    });

    test('strips the BSL prefix when matching the chamber title', () {
      final match = bestParliamentLiveMatch('House of Commons', events);
      expect(match?.guid, 'dddddddd-dddd-dddd-dddd-dddddddddddd');
    });

    test('returns null when nothing comes close', () {
      final match = bestParliamentLiveMatch('Cabinet Office', events);
      expect(match, isNull);
    });

    test('returns null on empty event list', () {
      final match = bestParliamentLiveMatch('anything', const []);
      expect(match, isNull);
    });
  });

  group('fallbackParliamentLiveMatchForHouse', () {
    final events = [
      const ParliamentLiveEvent(
        guid: 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        title: 'House of Commons',
      ),
      const ParliamentLiveEvent(
        guid: 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',
        title: 'Westminster Hall',
      ),
      const ParliamentLiveEvent(
        guid: 'cccccccc-cccc-cccc-cccc-cccccccccccc',
        title: 'House of Lords',
      ),
    ];

    test('returns commons chamber stream for Commons debates', () {
      final match = fallbackParliamentLiveMatchForHouse(
        events: events,
        house: 'Commons',
      );
      expect(match?.guid, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
    });

    test('prefers Westminster Hall when house is Westminster Hall', () {
      final match = fallbackParliamentLiveMatchForHouse(
        events: events,
        house: 'Westminster Hall',
      );
      expect(match?.guid, 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
    });

    test('returns lords chamber stream for Lords debates', () {
      final match = fallbackParliamentLiveMatchForHouse(
        events: events,
        house: 'Lords',
      );
      expect(match?.guid, 'cccccccc-cccc-cccc-cccc-cccccccccccc');
    });

    test('returns null when no matching chamber stream is present', () {
      final match = fallbackParliamentLiveMatchForHouse(
        events: const [
          ParliamentLiveEvent(
            guid: 'dddddddd-dddd-dddd-dddd-dddddddddddd',
            title: 'Foreign Affairs Committee',
          ),
        ],
        house: 'Commons',
      );
      expect(match, isNull);
    });
  });
}
