import '../models/speech.dart';
import 'speech_timecodes.dart';

/// Output of [normaliseSpeeches]: the display-ready list of speeches and the
/// time anchors harvested while normalising (used by the view-model to
/// interpolate clock-times for the minimap and Parliament Live deep-links).
class NormalisedTranscript {
  final List<Speech> speeches;
  final List<TimeAnchor> anchors;

  const NormalisedTranscript({
    required this.speeches,
    required this.anchors,
  });
}

/// Walks the raw Hansard speech list and produces the display-ready transcript
/// along with the [TimeAnchor]s found in the process.
///
/// Rules applied:
///  - Timestamp rows are stripped; their clock value becomes an anchor.
///  - A contribution's own Hansard `Timecode` also becomes an anchor at its
///    position. These are noisy (stale repeats, values from earlier in the
///    day), so the anchors are cleaned by [cleanTimeAnchors] before use.
///  - Date-heading rows are dropped.
///  - Repeated procedural headings (back-to-back duplicates) are collapsed.
///  - "Date phrases" matching the sitting [date] are dropped as redundant.
///  - "The House met at HH.MM am" announcements drop, but their time becomes
///    a free anchor.
///  - Committee-membership preambles ("The Committee consisted of the following
///    Members:") are merged with their roster lines into a single synthetic
///    procedural speech for the `SpeechBlock` renderer to format.
///
/// Pure: no I/O, no Flutter, no state outside the returned [NormalisedTranscript].
NormalisedTranscript normaliseSpeeches({
  required List<Speech> raw,
  required String date,
}) {
  final anchors = <TimeAnchor>[];
  final result = <Speech>[];
  int displayIndex = 0;
  String? lastProceduralNormalized;
  final redundantDatePhrases = _redundantDatePhrases(date);

  int i = 0;
  while (i < raw.length) {
    final speech = raw[i];
    if (speech.isTimestamp) {
      final seconds =
          parseTimecodeToSeconds(speech.timecode ?? speech.speechText);
      if (seconds != null) {
        if (anchors.isNotEmpty && anchors.last.index == displayIndex) {
          anchors[anchors.length - 1] = TimeAnchor(
            index: displayIndex.toDouble(),
            secondsSinceMidnight: seconds,
          );
        } else {
          anchors.add(
            TimeAnchor(
              index: displayIndex.toDouble(),
              secondsSinceMidnight: seconds,
            ),
          );
        }
      }
      i++;
      continue;
    }

    if (speech.isDateHeading) {
      i++;
      continue;
    }

    if (speech.isProceduralText) {
      final normalized = speech.speechText.trim().toLowerCase();
      if (normalized.isEmpty) {
        i++;
        continue;
      }
      if (redundantDatePhrases.contains(_normalizeForCompare(normalized))) {
        i++;
        continue;
      }
      if (normalized == lastProceduralNormalized) {
        i++;
        continue;
      }
      lastProceduralNormalized = normalized;

      if (speech.isSittingStartAnnouncement) {
        final seconds = speech.sittingStartSeconds;
        if (seconds != null) {
          anchors.add(
            TimeAnchor(
              index: displayIndex.toDouble(),
              secondsSinceMidnight: seconds,
            ),
          );
        }
        i++;
        continue;
      }

      final mergedCommittee = _mergeCommitteeMembershipLines(
        raw: raw,
        startIndex: i,
        redundantDatePhrases: redundantDatePhrases,
      );
      if (mergedCommittee != null) {
        result.add(mergedCommittee.speech);
        displayIndex++;
        i = mergedCommittee.nextIndex;
        continue;
      }
    } else {
      lastProceduralNormalized = null;
    }

    final ownSeconds = speech.timecode == null
        ? null
        : parseTimecodeToSeconds(speech.timecode!);
    if (ownSeconds != null) {
      anchors.add(
        TimeAnchor(
          index: displayIndex.toDouble(),
          secondsSinceMidnight: ownSeconds,
        ),
      );
    }
    result.add(speech);
    displayIndex++;
    i++;
  }

  return NormalisedTranscript(
    speeches: result,
    anchors: cleanTimeAnchors(anchors),
  );
}

/// Reduces raw [anchors] (in transcript order) to a strictly increasing
/// timeline that interpolation can trust.
///
/// Hansard's per-contribution timecodes include stale values — a run of
/// speeches all stamped with a time from an hour earlier, or one placeholder
/// repeated down a whole exchange. Time only moves forward through a sitting,
/// so this keeps the longest run of anchors whose times strictly increase and
/// drops the rest; a repeated time keeps only its first occurrence. Times
/// after midnight in a late sitting are carried past 24h so they still count
/// as later (formatting wraps them back).
List<TimeAnchor> cleanTimeAnchors(List<TimeAnchor> anchors) {
  if (anchors.length < 2) return anchors;

  // One anchor per position: the last one written there wins.
  final byIndex = <TimeAnchor>[];
  for (final a in anchors) {
    if (byIndex.isNotEmpty && byIndex.last.index == a.index) {
      byIndex[byIndex.length - 1] = a;
    } else {
      byIndex.add(a);
    }
  }

  // Carry small-hours times past midnight once the sitting has reached the
  // evening, so a Lords sitting running to 1am stays in order.
  const day = 24 * 3600;
  var sawEvening = false;
  final unwrapped = <TimeAnchor>[];
  for (final a in byIndex) {
    var s = a.secondsSinceMidnight;
    if (s >= 18 * 3600) sawEvening = true;
    if (sawEvening && s < 6 * 3600) s += day;
    unwrapped.add(TimeAnchor(index: a.index, secondsSinceMidnight: s));
  }

  // Longest strictly increasing subsequence by time (patience sorting).
  final n = unwrapped.length;
  final tails = <int>[]; // tails[k]: index of the smallest tail of length k+1
  final prev = List<int>.filled(n, -1);
  for (var i = 0; i < n; i++) {
    final t = unwrapped[i].secondsSinceMidnight;
    var lo = 0, hi = tails.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (unwrapped[tails[mid]].secondsSinceMidnight < t) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    // An equal time already ends a run of this length: keep that earlier
    // occurrence rather than the repeat.
    if (lo < tails.length && unwrapped[tails[lo]].secondsSinceMidnight == t) {
      continue;
    }
    if (lo > 0) prev[i] = tails[lo - 1];
    if (lo == tails.length) {
      tails.add(i);
    } else {
      tails[lo] = i;
    }
  }
  final kept = <TimeAnchor>[];
  for (var k = tails.isEmpty ? -1 : tails.last; k != -1; k = prev[k]) {
    kept.add(unwrapped[k]);
  }
  return kept.reversed.toList();
}

class _MergedProceduralBlock {
  final Speech speech;
  final int nextIndex;

  const _MergedProceduralBlock({
    required this.speech,
    required this.nextIndex,
  });
}

_MergedProceduralBlock? _mergeCommitteeMembershipLines({
  required List<Speech> raw,
  required int startIndex,
  required Set<String> redundantDatePhrases,
}) {
  final head = raw[startIndex];
  if (!_isCommitteeMembershipHeading(head.speechText)) {
    return null;
  }

  final lines = <String>[head.speechText.trim()];
  int i = startIndex + 1;
  while (i < raw.length) {
    final next = raw[i];
    if (next.isTimestamp) break;
    // Roster lines often have attribution set, so check for the † dagger
    // symbol as a reliable marker rather than relying on isProceduralText.
    final isRosterLine = next.speechText.trimLeft().startsWith('†');
    if (!next.isProceduralText && !isRosterLine) break;
    final text = next.speechText.trim();
    if (text.isEmpty) {
      i++;
      continue;
    }

    final normalized = _normalizeForCompare(text);
    if (redundantDatePhrases.contains(normalized)) break;
    if (_isCommitteeMembershipHeading(text)) {
      i++;
      continue;
    }

    lines.add(_formatCommitteeRosterLine(text));
    final lower = text.toLowerCase();
    if (lower.contains('attended the committee')) {
      i++;
      break;
    }

    if (lines.length >= 40) {
      i++;
      break;
    }

    i++;
  }

  if (lines.length == 1) {
    return _MergedProceduralBlock(speech: head, nextIndex: startIndex + 1);
  }

  return _MergedProceduralBlock(
    speech: Speech(
      id: head.id,
      debateId: head.debateId,
      debateTitle: head.debateTitle,
      itemType: head.itemType,
      memberId: head.memberId,
      memberName: head.memberName,
      attributedTo: head.attributedTo,
      speechText: lines.join('\n'),
      timecode: head.timecode,
      orderIndex: head.orderIndex,
    ),
    nextIndex: i,
  );
}

bool _isCommitteeMembershipHeading(String text) {
  return text
      .toLowerCase()
      .contains('the committee consisted of the following members:');
}

String _formatCommitteeRosterLine(String text) {
  return text.replaceFirst(RegExp(r'^\s*†\s*'), '• ');
}

Set<String> _redundantDatePhrases(String date) {
  final parsedDate = DateTime.tryParse(date);
  if (parsedDate == null) return const <String>{};

  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  final withComma =
      '${weekdays[parsedDate.weekday - 1]}, ${parsedDate.day} ${months[parsedDate.month - 1]} ${parsedDate.year}';
  final withoutComma =
      '${weekdays[parsedDate.weekday - 1]} ${parsedDate.day} ${months[parsedDate.month - 1]} ${parsedDate.year}';

  return {
    _normalizeForCompare(withComma),
    _normalizeForCompare(withoutComma),
  };
}

String _normalizeForCompare(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[,]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
