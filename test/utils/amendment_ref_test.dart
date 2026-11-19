import 'package:flutter_test/flutter_test.dart';
import 'package:open_parliament/utils/amendment_ref.dart';

void main() {
  group('parseCommonsDivisionTitle', () {
    test('report stage new clause', () {
      final r = parseCommonsDivisionTitle(
        'Immigration and Asylum Bill Report Stage: New Clause 62',
      )!;
      expect(r.billTitle, 'Immigration and Asylum Bill');
      expect(r.number, 'NC62');
      expect(r.stageHint, 'report');
      expect(r.isLordsAmendment, isFalse);
    });

    test('bracketed origin and short "Report" suffix', () {
      final r = parseCommonsDivisionTitle(
        'Sporting Events Bill [Lords] Report: Amendment 8',
      )!;
      expect(r.billTitle, 'Sporting Events Bill [Lords]');
      expect(r.number, '8');
      expect(r.stageHint, 'report');
    });

    test('committee new schedule', () {
      final r = parseCommonsDivisionTitle(
        'Finance Bill Committee: New Schedule 3',
      )!;
      expect(r.number, 'NS3');
      expect(r.stageHint, 'committee');
    });

    test('Lords Amendment mid-sentence', () {
      final r = parseCommonsDivisionTitle(
        "Children's Wellbeing and Schools Bill: motion to disagree with "
        'Lords Amendment 106',
      )!;
      expect(r.billTitle, "Children's Wellbeing and Schools Bill");
      expect(r.number, '106');
      expect(r.isLordsAmendment, isTrue);
      expect(r.stageHint, 'lords amendments');
    });

    test('non-amendment divisions return null', () {
      for (final t in [
        'Immigration and Asylum Bill: Third Reading',
        'Visitor Levy (England) Bill Second Reading',
        'Opposition Day: Rosebank oilfield: Opposition motion',
        'Budget Resolution No. 86: High value council tax surcharge',
        'Draft Private Rented Sector Database Regulations 2026',
        'Courts and Tribunals Bill: Reasoned Amendment to Second Reading',
      ]) {
        expect(parseCommonsDivisionTitle(t), isNull, reason: t);
      }
    });
  });

  test('parseLordsAmendmentNumber', () {
    expect(
      parseLordsAmendmentNumber(
        'Baroness Harding of Winscombe moved amendment 16, Schedule 2, page 71',
      ),
      '16',
    );
    expect(parseLordsAmendmentNumber('Lord X moved amendment 88a, after'), '88A');
    expect(
      parseLordsAmendmentNumber('Lord Farmer moved that this House regrets'),
      isNull,
    );
  });

  test('normaliseBillTitle matches across origin tags, Acts and quotes', () {
    expect(
      normaliseBillTitle('Sporting Events Bill [Lords]'),
      normaliseBillTitle('Sporting Events Bill [HL]'),
    );
    expect(
      normaliseBillTitle('Industry and Exports (Financial Assistance) Bill'),
      normaliseBillTitle('Industry and Exports (Financial Assistance) Act 2026'),
    );
    expect(
      normaliseBillTitle("Children's Wellbeing and Schools Bill"),
      normaliseBillTitle('Children’s Wellbeing and Schools Act 2026'),
    );
    expect(
      normaliseBillTitle('Railways Bill'),
      isNot(normaliseBillTitle('Railways Act 1993 (Amendment) Bill')),
    );
  });

  group('candidateStages', () {
    final stages = [
      {
        'id': 1,
        'description': '3rd reading',
        'house': 'Commons',
        'stageSittings': [
          {'date': '2026-11-17T00:00:00'},
        ],
      },
      {
        'id': 2,
        'description': 'Report stage',
        'house': 'Commons',
        'stageSittings': [
          {'date': '2026-11-17T00:00:00'},
        ],
      },
      {
        'id': 3,
        'description': 'Report stage',
        'house': 'Lords',
        'stageSittings': [
          {'date': '2026-11-17T00:00:00'},
        ],
      },
      {
        'id': 4,
        'description': 'Committee stage',
        'house': 'Commons',
        'stageSittings': [
          {'date': '2026-10-01T00:00:00'},
        ],
      },
    ];

    test('filters by house and sitting date, hint first', () {
      final hits = candidateStages(
        stages,
        house: 'Commons',
        date: DateTime(2026, 11, 17),
        stageHint: 'report',
      );
      expect(hits.map((h) => h.$1), [2, 1]);
    });

    test('no sitting on that day yields nothing', () {
      expect(
        candidateStages(stages, house: 'Commons', date: DateTime(2026, 1, 1)),
        isEmpty,
      );
    });
  });
}
