/// Pure layout math for the Google Calendar-style day timeline: resolving
/// each debate's real `[start, end)` on the clock, and — when debates from
/// different venues overlap — assigning them side-by-side columns the same
/// way a calendar app lays out concurrent events. No Flutter dependency, so
/// this is fully testable without pumping a widget tree.
library;

/// A thin, presentation-agnostic view of one debate for timeline layout.
class TimelineItem {
  final String id;
  final int order;
  final int? startSeconds;

  /// The word-count-based duration estimate (`DebateFeedItem.durationMinutes`),
  /// used as a fallback when no later item's start time can bound this
  /// item's end. Always treated as at least 1 minute.
  final int fallbackDurationMinutes;

  const TimelineItem({
    required this.id,
    required this.order,
    this.startSeconds,
    required this.fallbackDurationMinutes,
  });
}

/// One item's resolved `[start, end)` on the wall-clock timeline.
class TimelineSpan {
  final String id;
  final int startSeconds;
  final int endSeconds;

  const TimelineSpan({
    required this.id,
    required this.startSeconds,
    required this.endSeconds,
  });

  int get durationSeconds => endSeconds - startSeconds;
}

/// Column-and-width assignment for one span within its overlap cluster.
/// [left]/[width] are 0..1 fractions of the row's horizontal space (same
/// normalized convention as `buildChamberLayout`'s `Offset`s in
/// `seat_layout.dart`) — the caller multiplies by the actual available width
/// at build time.
class TimelineSlot {
  final String id;
  final int startSeconds;
  final int endSeconds;
  final double left;
  final double width;

  const TimelineSlot({
    required this.id,
    required this.startSeconds,
    required this.endSeconds,
    required this.left,
    required this.width,
  });
}

/// Resolves each item's `[start, end)` span within one venue's running
/// order. A venue can't run two debates at once, so a debate's end is
/// inferred — in priority order — from (1) the next debate's known start,
/// falling back to (2) this debate's own word-count-based duration estimate.
///
/// [orderedVenueItems] should already be filtered to a single venue; this
/// function sorts a defensive copy by [TimelineItem.order], so callers don't
/// need to pre-sort. [sessionStartSeconds] (typically that venue's
/// `SittingSession.startSeconds`) seeds the first item's start when it has
/// no timecode of its own.
///
/// An item that ends up with neither its own start, a carried-forward start,
/// nor the session seed can't be placed on the timeline and is omitted from
/// the result — the caller should diff returned ids against the input to
/// find these and render them separately (e.g. an "Unscheduled" section).
///
/// [maxDurationMinutes] clamps how long any single inferred span can be, so
/// one anomalous/out-of-order timecode can't blow up the whole day's scale.
List<TimelineSpan> resolveVenueTimelineSpans(
  List<TimelineItem> orderedVenueItems, {
  int? sessionStartSeconds,
  int maxDurationMinutes = 360,
}) {
  final sorted = List<TimelineItem>.from(orderedVenueItems)
    ..sort((a, b) => a.order.compareTo(b.order));
  final maxDurationSeconds = maxDurationMinutes * 60;

  final spans = <TimelineSpan>[];
  int? cursor;
  for (final item in sorted) {
    final start = item.startSeconds ?? cursor ?? sessionStartSeconds;
    if (start == null) {
      // Unplaceable — leave cursor untouched so a later item's own
      // timecode still anchors correctly instead of inheriting this gap.
      continue;
    }
    final fallbackMinutes = item.fallbackDurationMinutes < 1
        ? 1
        : item.fallbackDurationMinutes;
    final provisionalEnd =
        start + (fallbackMinutes * 60).clamp(0, maxDurationSeconds);
    spans.add(TimelineSpan(id: item.id, startSeconds: start, endSeconds: provisionalEnd));
    cursor = provisionalEnd;
  }

  // Snap each span's end to the next span's start, when known — real
  // elapsed duration including any gap, rather than the word-count guess.
  for (var i = 0; i < spans.length - 1; i++) {
    final span = spans[i];
    final nextStart = spans[i + 1].startSeconds;
    if (nextStart <= span.startSeconds) {
      // Anomalous/out-of-order source timecode — keep the provisional
      // (word-count) end rather than producing a zero/negative duration.
      continue;
    }
    final clampedEnd =
        nextStart < span.startSeconds + maxDurationSeconds
            ? nextStart
            : span.startSeconds + maxDurationSeconds;
    spans[i] = TimelineSpan(
      id: span.id,
      startSeconds: span.startSeconds,
      endSeconds: clampedEnd,
    );
  }

  return spans;
}

/// Assigns horizontal columns to a set of possibly-overlapping timeline
/// spans, using the same technique calendar day views use for concurrent
/// events:
///
/// 1. Sort spans by start time (then end time, then id, for determinism).
/// 2. Sweep to find maximal clusters of transitively-overlapping spans: a
///    new cluster starts whenever a span's start is at or after the running
///    max end seen so far in the current cluster.
/// 3. Within a cluster, greedily assign columns left-to-right: place each
///    span in the first column whose last-placed span already ended by this
///    span's start; otherwise open a new column.
/// 4. Every span in a cluster gets `left = column / clusterColumnCount` and
///    `width = 1 / clusterColumnCount`. Spans outside any multi-span cluster
///    get `left: 0, width: 1` (full row width).
///
/// Note: like a calendar app's own layout, this greedy column count is the
/// cluster's peak concurrency, not a perfectly minimal per-item width — a
/// span that only transitively shares a cluster with others it doesn't
/// directly overlap (A–B overlap, B–C overlap, A–C don't) can end up
/// narrower than its true free space allows. This is intentional and matches
/// the reference model.
List<TimelineSlot> layoutOverlappingSpans(List<TimelineSpan> spans) {
  if (spans.isEmpty) return const [];

  final sorted = List<TimelineSpan>.from(spans)
    ..sort((a, b) {
      final byStart = a.startSeconds.compareTo(b.startSeconds);
      if (byStart != 0) return byStart;
      final byEnd = a.endSeconds.compareTo(b.endSeconds);
      if (byEnd != 0) return byEnd;
      return a.id.compareTo(b.id);
    });

  final slots = <TimelineSlot>[];
  var clusterStart = 0;
  var clusterMaxEnd = sorted.first.endSeconds;

  void flushCluster(int clusterEndIndexExclusive) {
    final clusterSpans = sorted.sublist(clusterStart, clusterEndIndexExclusive);
    if (clusterSpans.length == 1) {
      final span = clusterSpans.first;
      slots.add(TimelineSlot(
        id: span.id,
        startSeconds: span.startSeconds,
        endSeconds: span.endSeconds,
        left: 0,
        width: 1,
      ));
      return;
    }

    // Greedy column assignment: each column remembers the end time of the
    // last span placed in it.
    final columnEnds = <int>[];
    final columnBySpanIndex = <int>[];
    for (final span in clusterSpans) {
      var placedColumn = -1;
      for (var c = 0; c < columnEnds.length; c++) {
        if (columnEnds[c] <= span.startSeconds) {
          placedColumn = c;
          break;
        }
      }
      if (placedColumn == -1) {
        placedColumn = columnEnds.length;
        columnEnds.add(span.endSeconds);
      } else {
        columnEnds[placedColumn] = span.endSeconds;
      }
      columnBySpanIndex.add(placedColumn);
    }

    final columnCount = columnEnds.length;
    for (var i = 0; i < clusterSpans.length; i++) {
      final span = clusterSpans[i];
      final column = columnBySpanIndex[i];
      slots.add(TimelineSlot(
        id: span.id,
        startSeconds: span.startSeconds,
        endSeconds: span.endSeconds,
        left: column / columnCount,
        width: 1 / columnCount,
      ));
    }
  }

  for (var i = 1; i < sorted.length; i++) {
    final span = sorted[i];
    if (span.startSeconds >= clusterMaxEnd) {
      flushCluster(i);
      clusterStart = i;
      clusterMaxEnd = span.endSeconds;
    } else if (span.endSeconds > clusterMaxEnd) {
      clusterMaxEnd = span.endSeconds;
    }
  }
  flushCluster(sorted.length);

  return slots;
}

/// The visible time span covering [spans]: earliest start / latest end,
/// expanded outward to the nearest hour (floor start, ceil end) and padded
/// by [paddingMinutes] on each side so the first/last card isn't flush
/// against the ruler edge. Returns `null` for empty [spans] — the caller
/// must fall back to a non-timeline rendering in that case.
({int originSeconds, int endSeconds})? timelineBounds(
  List<TimelineSpan> spans, {
  int paddingMinutes = 15,
}) {
  if (spans.isEmpty) return null;

  var earliestStart = spans.first.startSeconds;
  var latestEnd = spans.first.endSeconds;
  for (final span in spans.skip(1)) {
    if (span.startSeconds < earliestStart) earliestStart = span.startSeconds;
    if (span.endSeconds > latestEnd) latestEnd = span.endSeconds;
  }

  const secondsPerHour = 3600;
  final flooredStart = (earliestStart ~/ secondsPerHour) * secondsPerHour;
  final ceiledEnd = ((latestEnd + secondsPerHour - 1) ~/ secondsPerHour) * secondsPerHour;

  final paddingSeconds = paddingMinutes * 60;
  final origin = flooredStart - paddingSeconds < 0 ? 0 : flooredStart - paddingSeconds;
  return (originSeconds: origin, endSeconds: ceiledEnd + paddingSeconds);
}

/// Vertical pixel rect for one span, given the timeline's visible origin and
/// vertical scale. Applies the minimum-card-height floor in one place so
/// every rendering mode shares identical clamping behaviour.
({double top, double height}) timelineVerticalRect({
  required int startSeconds,
  required int endSeconds,
  required int originSeconds,
  required double pixelsPerMinute,
  required double minHeight,
}) {
  final top = (startSeconds - originSeconds) / 60 * pixelsPerMinute;
  final rawHeight = (endSeconds - startSeconds) / 60 * pixelsPerMinute;
  return (top: top, height: rawHeight < minHeight ? minHeight : rawHeight);
}
