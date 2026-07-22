import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/utils/day_timeline_layout.dart';

TimelineItem _item(
  String id, {
  required int order,
  int? startSeconds,
  int fallbackDurationMinutes = 10,
}) {
  return TimelineItem(
    id: id,
    order: order,
    startSeconds: startSeconds,
    fallbackDurationMinutes: fallbackDurationMinutes,
  );
}

void main() {
  group('resolveVenueTimelineSpans', () {
    test('single item with no next falls back to word-count duration', () {
      final spans = resolveVenueTimelineSpans([
        _item('a', order: 0, startSeconds: 1000, fallbackDurationMinutes: 5),
      ]);
      expect(spans, hasLength(1));
      expect(spans.single.startSeconds, 1000);
      expect(spans.single.endSeconds, 1000 + 5 * 60);
    });

    test('first item end snaps to second item start', () {
      final spans = resolveVenueTimelineSpans([
        _item('a', order: 0, startSeconds: 1000, fallbackDurationMinutes: 5),
        _item('b', order: 1, startSeconds: 5000, fallbackDurationMinutes: 5),
      ]);
      expect(spans[0].endSeconds, 5000);
      expect(spans[1].startSeconds, 5000);
      expect(spans[1].endSeconds, 5000 + 5 * 60);
    });

    test('middle item with no start inherits previous end, then corrects', () {
      final spans = resolveVenueTimelineSpans([
        _item('a', order: 0, startSeconds: 1000, fallbackDurationMinutes: 5),
        _item('b', order: 1, fallbackDurationMinutes: 5),
        _item('c', order: 2, startSeconds: 9000, fallbackDurationMinutes: 5),
      ]);
      expect(spans, hasLength(3));
      const aEnd = 1000 + 5 * 60;
      expect(spans[0].endSeconds, aEnd);
      expect(spans[1].startSeconds, aEnd);
      // b's provisional end (aEnd + 5*60) gets snapped to c's real start.
      expect(spans[1].endSeconds, 9000);
      expect(spans[2].startSeconds, 9000);
    });

    test('leading item with no start and no session seed is dropped', () {
      final spans = resolveVenueTimelineSpans([
        _item('a', order: 0),
        _item('b', order: 1, startSeconds: 5000, fallbackDurationMinutes: 5),
      ]);
      expect(spans.map((s) => s.id), ['b']);
    });

    test('leading item inherits the session start seed', () {
      final spans = resolveVenueTimelineSpans(
        [_item('a', order: 0, fallbackDurationMinutes: 5)],
        sessionStartSeconds: 3600,
      );
      expect(spans.single.startSeconds, 3600);
      expect(spans.single.endSeconds, 3600 + 5 * 60);
    });

    test('out-of-order next start keeps the fallback end', () {
      final spans = resolveVenueTimelineSpans([
        _item('a', order: 0, startSeconds: 5000, fallbackDurationMinutes: 5),
        _item('b', order: 1, startSeconds: 1000, fallbackDurationMinutes: 5),
      ]);
      expect(spans[0].startSeconds, 5000);
      expect(spans[0].endSeconds, 5000 + 5 * 60);
      expect(spans[1].startSeconds, 1000);
    });

    test('maxDurationMinutes clamps an implausibly large gap', () {
      final spans = resolveVenueTimelineSpans(
        [
          _item('a', order: 0, startSeconds: 0, fallbackDurationMinutes: 5),
          _item('b', order: 1, startSeconds: 100000, fallbackDurationMinutes: 5),
        ],
        maxDurationMinutes: 60,
      );
      expect(spans[0].endSeconds, 60 * 60);
    });

    test('empty input returns empty output', () {
      expect(resolveVenueTimelineSpans(const []), isEmpty);
    });
  });

  group('layoutOverlappingSpans', () {
    TimelineSpan span(String id, int start, int end) =>
        TimelineSpan(id: id, startSeconds: start, endSeconds: end);

    test('no overlaps gives every span full width', () {
      final slots = layoutOverlappingSpans([
        span('a', 0, 100),
        span('b', 100, 200),
      ]);
      for (final slot in slots) {
        expect(slot.left, 0);
        expect(slot.width, 1);
      }
    });

    test('two overlapping spans split the row in half', () {
      final slots = layoutOverlappingSpans([
        span('a', 0, 200),
        span('b', 100, 300),
      ]);
      final byId = {for (final s in slots) s.id: s};
      expect(byId['a']!.width, 0.5);
      expect(byId['b']!.width, 0.5);
      expect({byId['a']!.left, byId['b']!.left}, {0.0, 0.5});
    });

    test('three-way overlap gives three equal columns', () {
      final slots = layoutOverlappingSpans([
        span('commons', 0, 300),
        span('westminster-hall', 50, 250),
        span('committee', 100, 200),
      ]);
      for (final slot in slots) {
        expect(slot.width, closeTo(1 / 3, 1e-9));
      }
      expect(slots.map((s) => s.left).toSet(), hasLength(3));
    });

    test('touching-not-overlapping spans are separate, both full width', () {
      final slots = layoutOverlappingSpans([
        span('a', 0, 100),
        span('b', 100, 200),
      ]);
      final byId = {for (final s in slots) s.id: s};
      expect(byId['a']!.width, 1);
      expect(byId['b']!.width, 1);
    });

    test('transitive-not-mutual overlap: A and C share a cluster via B', () {
      // A: 0-150, B: 100-250, C: 200-300. A/C don't directly overlap but
      // both share a cluster with B, so the greedy algorithm still gives
      // every span in the cluster the cluster's peak-concurrency width
      // (2 columns here), even though A and C individually would fit in the
      // same column. Documented, accepted tradeoff.
      final slots = layoutOverlappingSpans([
        span('a', 0, 150),
        span('b', 100, 250),
        span('c', 200, 300),
      ]);
      final byId = {for (final s in slots) s.id: s};
      expect(byId['a']!.width, 0.5);
      expect(byId['b']!.width, 0.5);
      expect(byId['c']!.width, 0.5);
      // a and c can safely share a column (they don't overlap); b takes the
      // other column.
      expect(byId['a']!.left, byId['c']!.left);
      expect(byId['b']!.left, isNot(byId['a']!.left));
    });

    test('empty input returns empty output', () {
      expect(layoutOverlappingSpans(const []), isEmpty);
    });
  });

  group('timelineBounds', () {
    test('rounds outward to hour boundaries and pads', () {
      final bounds = timelineBounds(
        [
          const TimelineSpan(id: 'a', startSeconds: 9 * 3600 + 20 * 60, endSeconds: 10 * 3600 + 40 * 60),
        ],
        paddingMinutes: 15,
      );
      expect(bounds, isNotNull);
      expect(bounds!.originSeconds, 9 * 3600 - 15 * 60);
      expect(bounds.endSeconds, 11 * 3600 + 15 * 60);
    });

    test('empty spans returns null', () {
      expect(timelineBounds(const []), isNull);
    });
  });

  group('timelineVerticalRect', () {
    test('sub-floor duration clamps to minHeight', () {
      final rect = timelineVerticalRect(
        startSeconds: 0,
        endSeconds: 60,
        originSeconds: 0,
        pixelsPerMinute: 1.5,
        minHeight: 92,
      );
      expect(rect.height, 92);
    });

    test('normal duration scales by pixelsPerMinute', () {
      final rect = timelineVerticalRect(
        startSeconds: 0,
        endSeconds: 3600,
        originSeconds: 0,
        pixelsPerMinute: 2,
        minHeight: 92,
      );
      expect(rect.height, 60 * 2);
    });

    test('top is offset relative to originSeconds', () {
      final rect = timelineVerticalRect(
        startSeconds: 3600 + 600,
        endSeconds: 3600 + 1200,
        originSeconds: 3600,
        pixelsPerMinute: 2,
        minHeight: 92,
      );
      expect(rect.top, 10 * 2);
    });
  });
}
