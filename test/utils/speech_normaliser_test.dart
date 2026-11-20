import 'package:flutter_test/flutter_test.dart';
import 'package:open_parliament/models/speech.dart';
import 'package:open_parliament/utils/speech_normaliser.dart';
import 'package:open_parliament/utils/speech_timecodes.dart';

TimeAnchor _a(double index, String hms) => TimeAnchor(
      index: index,
      secondsSinceMidnight: parseTimecodeToSeconds(hms)!,
    );

List<(double, String)> _shape(List<TimeAnchor> anchors) => [
      for (final a in anchors)
        (a.index, formatSecondsAsTimecode(a.secondsSinceMidnight)),
    ];

Speech _speech(int i, {String? timecode}) => Speech(
      id: 's$i',
      debateId: 'd',
      debateTitle: 'UK-EU Relations',
      memberId: 1,
      memberName: 'A Member',
      attributedTo: 'A Member (Somewhere) (Lab)',
      speechText: 'Speech $i',
      timecode: timecode,
      orderIndex: i,
    );

void main() {
  group('cleanTimeAnchors', () {
    test('drops a run of stale times from earlier in the day', () {
      // Shape of Hansard's 18 Nov 2026 UK-EU Relations debate: correct times,
      // then a run all stamped with 11:49:02 (before the debate began).
      final cleaned = cleanTimeAnchors([
        _a(0, '13:00:41'),
        _a(1, '13:02:13'),
        _a(2, '13:17:42'),
        _a(3, '11:49:02'),
        _a(4, '11:49:02'),
        _a(5, '11:49:02'),
        _a(6, '13:40:00'),
      ]);
      expect(_shape(cleaned), [
        (0.0, '13:00:41'),
        (1.0, '13:02:13'),
        (2.0, '13:17:42'),
        (6.0, '13:40:00'),
      ]);
    });

    test('keeps only the first of a repeated placeholder time', () {
      final cleaned = cleanTimeAnchors([
        _a(0, '12:34:13'),
        _a(1, '12:34:13'),
        _a(2, '12:34:13'),
        _a(3, '12:38:51'),
      ]);
      expect(_shape(cleaned), [(0.0, '12:34:13'), (3.0, '12:38:51')]);
    });

    test('drops a single out-of-order jitter', () {
      final cleaned = cleanTimeAnchors([
        _a(0, '12:21:42'),
        _a(1, '12:24:48'),
        _a(2, '12:23:51'),
        _a(3, '12:26:00'),
      ]);
      // One of the crossing pair goes; the rest still increase.
      expect(cleaned.length, 3);
      for (var i = 1; i < cleaned.length; i++) {
        expect(cleaned[i].secondsSinceMidnight,
            greaterThan(cleaned[i - 1].secondsSinceMidnight));
      }
    });

    test('keeps a late sitting in order past midnight', () {
      final cleaned = cleanTimeAnchors([
        _a(0, '22:10:00'),
        _a(1, '23:55:00'),
        _a(2, '00:20:00'),
        _a(3, '01:05:00'),
      ]);
      expect(cleaned.length, 4);
      // Formatting wraps the carried times back onto the clock.
      expect(_shape(cleaned).last, (3.0, '01:05:00'));
    });
  });

  group('normaliseSpeeches', () {
    test('uses contribution timecodes, ignoring stale ones, for labels', () {
      final transcript = normaliseSpeeches(
        date: '2026-11-18',
        raw: [
          _speech(0, timecode: '2026-11-18T13:00:41'),
          _speech(1, timecode: '2026-11-18T13:10:00'),
          _speech(2, timecode: '2026-11-18T11:49:02'),
          _speech(3, timecode: '2026-11-18T13:30:00'),
        ],
      );
      final at2 = interpolateSecondsAtPosition(transcript.anchors, 2)!;
      // Halfway between 13:10 and 13:30, not the stale 11:49.
      expect(formatSecondsAsClockMinute(at2), '13:20');
    });
  });
}
