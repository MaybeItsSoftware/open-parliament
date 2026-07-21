/// A known wall-clock time at a specific transcript position. Used by
/// [interpolateSecondsAtPosition] to estimate the time at any other position.
///
/// `index` is a (possibly fractional) speech index — fractional values let the
/// view-model express "between speech 12 and 13" for smooth scrubbing.
class TimeAnchor {
  final double index;
  final int secondsSinceMidnight;

  const TimeAnchor({
    required this.index,
    required this.secondsSinceMidnight,
  });
}

/// Parses an `HH:MM`/`HH:MM:SS` timecode, or a full ISO-8601 datetime (the
/// shape the live Hansard API actually returns in its `Timecode` field, e.g.
/// `"2026-07-15T12:00:00"`), into seconds since midnight. Returns `null` when
/// the string is malformed or out of range.
int? parseTimecodeToSeconds(String raw) {
  final trimmed = raw.trim();
  final isoParsed = DateTime.tryParse(trimmed);
  if (isoParsed != null && trimmed.contains('T')) {
    return (isoParsed.hour * 3600) + (isoParsed.minute * 60) + isoParsed.second;
  }

  final parts = trimmed.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final s = parts.length == 3 ? int.tryParse(parts[2]) : 0;
  if (h == null || m == null || s == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) return null;
  return (h * 3600) + (m * 60) + s;
}

/// Formats [secondsSinceMidnight] as `HH:MM:SS`, wrapping at 24h.
String formatSecondsAsTimecode(int secondsSinceMidnight) {
  final normalized = secondsSinceMidnight % (24 * 60 * 60);
  final h = (normalized ~/ 3600).toString().padLeft(2, '0');
  final m = ((normalized % 3600) ~/ 60).toString().padLeft(2, '0');
  final s = (normalized % 60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// Formats [secondsSinceMidnight] rounded to the nearest minute as `HH:MM`.
String formatSecondsAsClockMinute(int secondsSinceMidnight) {
  final roundedMinutes = ((secondsSinceMidnight + 30) ~/ 60) % (24 * 60);
  final h = (roundedMinutes ~/ 60).toString().padLeft(2, '0');
  final m = (roundedMinutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

/// Returns an interpolated wall-clock time (seconds since midnight) at a
/// given (possibly fractional) speech `position`, using [anchors] as the
/// known reference points. Linear interpolation between the bracketing
/// anchors; clamps to the first/last anchor outside the anchor range.
///
/// Returns `null` when [anchors] is empty.
int? interpolateSecondsAtPosition(List<TimeAnchor> anchors, double position) {
  if (anchors.isEmpty) return null;

  final first = anchors.first;
  final last = anchors.last;

  if (position <= first.index) {
    return first.secondsSinceMidnight;
  }

  if (position >= last.index) {
    return last.secondsSinceMidnight;
  }

  TimeAnchor? previous;
  TimeAnchor? next;
  for (final anchor in anchors) {
    if (anchor.index <= position) previous = anchor;
    if (anchor.index >= position) {
      next = anchor;
      break;
    }
  }

  if (previous == null && next == null) return null;
  if (previous == null) return next!.secondsSinceMidnight;
  if (next == null) return previous.secondsSinceMidnight;
  if (next.index == previous.index) return previous.secondsSinceMidnight;

  final ratio = (position - previous.index) / (next.index - previous.index);
  return previous.secondsSinceMidnight +
      ((next.secondsSinceMidnight - previous.secondsSinceMidnight) * ratio)
          .round();
}
