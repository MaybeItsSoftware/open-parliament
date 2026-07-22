import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/utils/speech_timecodes.dart';

void main() {
  group('parseTimecodeToSeconds', () {
    test('parses bare HH:MM', () {
      expect(parseTimecodeToSeconds('11:30'), 11 * 3600 + 30 * 60);
    });

    test('parses bare HH:MM:SS', () {
      expect(parseTimecodeToSeconds('12:00:05'), 12 * 3600 + 5);
    });

    test('parses the live Hansard API ISO-8601 datetime shape', () {
      expect(
        parseTimecodeToSeconds('2026-07-15T12:00:00'),
        12 * 3600,
      );
    });

    test('parses an ISO-8601 datetime with non-zero seconds', () {
      expect(
        parseTimecodeToSeconds('2026-07-15T11:35:55'),
        11 * 3600 + 35 * 60 + 55,
      );
    });

    test('returns null for malformed input', () {
      expect(parseTimecodeToSeconds('not a time'), isNull);
      expect(parseTimecodeToSeconds(''), isNull);
    });

    test('returns null for out-of-range bare values', () {
      expect(parseTimecodeToSeconds('25:00'), isNull);
      expect(parseTimecodeToSeconds('12:60'), isNull);
    });

    test('returns null for the .NET default-DateTime sentinel', () {
      // The live Hansard API serializes an unset Timecode as
      // "0001-01-01T00:00:00" rather than omitting the field — this must
      // read as "no timecode", not a real midnight sitting.
      expect(parseTimecodeToSeconds('0001-01-01T00:00:00'), isNull);
    });

    test('still parses a genuine modern midnight timecode', () {
      expect(parseTimecodeToSeconds('2026-07-15T00:00:00'), 0);
    });
  });
}
