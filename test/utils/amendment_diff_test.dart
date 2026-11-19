import 'package:flutter_test/flutter_test.dart';
import 'package:open_parliament/utils/amendment_diff.dart';

/// Text of every segment with [op], across all lines.
List<String> _texts(List<List<DiffSegment>> lines, DiffOp op) => [
      for (final line in lines)
        for (final s in line)
          if (s.op == op) s.text,
    ];

void main() {
  test('leave out X and insert Y', () {
    final segs = segmentAmendment([
      'Clause 22, page 20, line 3, leave out “may” and insert “must”',
    ]);
    expect(_texts(segs, DiffOp.deleted), ['may']);
    expect(_texts(segs, DiffOp.inserted), ['must']);
  });

  test('anchors after / from / to are not treated as changes', () {
    final segs = segmentAmendment([
      'Schedule 2, page 71, line 29, after “activities,” insert “showing '
          'separately the costs”',
    ]);
    expect(_texts(segs, DiffOp.anchor), ['activities,']);
    expect(_texts(segs, DiffOp.inserted), ['showing separately the costs']);

    final range = segmentAmendment([
      'leave out from “without” to “household” and insert “them”',
    ]);
    expect(_texts(range, DiffOp.anchor), ['without', 'household']);
    expect(_texts(range, DiffOp.inserted), ['them']);
  });

  test('for X substitute Y', () {
    final segs = segmentAmendment(['line 4, for “30 days” substitute “60 days”']);
    expect(_texts(segs, DiffOp.deleted), ['30 days']);
    expect(_texts(segs, DiffOp.inserted), ['60 days']);
  });

  test('an insertion spanning several lines stays inserted', () {
    final segs = segmentAmendment([
      'Clause 28, page 26, line 15, leave out from “without” to end of line '
          '7 and insert “them or their household becoming impoverished.',
      '(5A) For the purposes of subsection (5), a person is impoverished.”',
    ]);
    expect(_texts(segs, DiffOp.inserted), [
      'them or their household becoming impoverished.',
      '(5A) For the purposes of subsection (5), a person is impoverished.',
    ]);
  });

  test('new clause: bold heading and body are insertions', () {
    final segs = segmentAmendment(
      [
        'To move the following Clause—',
        '<b>“Protection of existing visa holders</b>',
        'The Secretary of State may not make any change.”',
      ],
      quotesAreInsertions: true,
    );
    final inserted = [
      for (final line in segs)
        for (final s in line)
          if (s.op == DiffOp.inserted) s,
    ];
    expect(inserted.first.text, 'Protection of existing visa holders');
    expect(inserted.first.bold, isTrue);
    expect(inserted.last.text, 'The Secretary of State may not make any change.');
    expect(inserted.last.bold, isFalse);
  });

  test('quotes nested inside inserted text stay inserted', () {
    final segs = segmentAmendment([
      'at end insert—',
      '“Schedule 6 (“the single sex protections provisions”).”',
    ]);
    expect(_texts(segs, DiffOp.inserted), [
      'Schedule 6 (“the single sex protections provisions”).',
    ]);
  });

  test('HTML entities in Lords notes are decoded', () {
    final segs = segmentAmendment([
      'moved amendment 16, after &ldquo;activities,&rdquo; to insert '
          '&ldquo;showing costs&rdquo;. The House divided.',
    ]);
    expect(_texts(segs, DiffOp.anchor), ['activities,']);
    expect(_texts(segs, DiffOp.inserted), ['showing costs']);
  });
}
