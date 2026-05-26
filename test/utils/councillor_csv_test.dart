import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/councillor.dart';
import 'package:open_hansard/utils/councillor_csv.dart';

void main() {
  group('parseCouncillors', () {
    const csv = '''
Council,"Ward Name","Councillor Name","Next Election","Party Name","Electoral Commission Party Code"
Cambridgeshire,Trumpington,"David Levien",2029-05-03,"Liberal Democrats",PP90
Cambridgeshire,"The Hemingfords & Fenstanton","David Keane",2029-05-03,"Conservative and Unionist",PP52
Cambridgeshire,Littleport,"John Wells",2029-05-03,"Reform UK",PP7931
''';

    test('parses each councillor with ward, party and election date', () {
      final councillors = parseCouncillors(csv);
      expect(councillors.length, 3);

      final levien = councillors.first;
      expect(levien.council, 'Cambridgeshire');
      expect(levien.ward, 'Trumpington');
      expect(levien.name, 'David Levien');
      expect(levien.party, 'Liberal Democrats');
      expect(levien.partyCode, 'PP90');
      expect(levien.nextElection, DateTime.parse('2029-05-03'));
    });

    test('handles quoted fields containing commas and ampersands', () {
      final councillors = parseCouncillors(csv);
      final keane = councillors.firstWhere((c) => c.name == 'David Keane');
      expect(keane.ward, 'The Hemingfords & Fenstanton');
      expect(keane.party, 'Conservative and Unionist');
    });

    test('maps columns by header name, not position', () {
      const reordered = '''
"Councillor Name",Council,"Party Name","Ward Name"
"Jane Doe","Test Council","Green",Central
''';
      final councillors = parseCouncillors(reordered);
      expect(councillors.single.name, 'Jane Doe');
      expect(councillors.single.ward, 'Central');
      expect(councillors.single.party, 'Green');
      expect(councillors.single.nextElection, isNull);
    });

    test('returns empty on blank or headerless input', () {
      expect(parseCouncillors(''), isEmpty);
      expect(parseCouncillors('just,some,values\n1,2,3'), isEmpty);
    });

    test('skips rows missing a name or council', () {
      const withGaps = '''
Council,"Ward Name","Councillor Name"
Cambridgeshire,Trumpington,
,Trumpington,"No Council"
Cambridgeshire,Linton,"Henry Batchelor"
''';
      final councillors = parseCouncillors(withGaps);
      expect(councillors.single.name, 'Henry Batchelor');
    });

    test('flags City of London roles and defaults to Independent', () {
      const cityCsv = '''
Council,"Ward Name","Councillor Name","Next Election","Party Name"
City of London,Aldgate,"Alderman Jane Smith",2029-03-01,
City of London,Aldgate,"Chris Doe",2028-05-02,
''';
      final councillors = parseCouncillors(cityCsv);
      expect(councillors.length, 2);

      final alderman =
          councillors.firstWhere((c) => c.name.contains('Jane Smith'));
      expect(alderman.role, CouncillorRole.alderman);
      expect(alderman.memberships,
          ['Court of Common Council', 'Court of Aldermen']);
      expect(alderman.party, 'Independent');
      expect(alderman.termYears, 6);
      expect(alderman.isPaid, isFalse);

      final common =
          councillors.firstWhere((c) => c.name.contains('Chris Doe'));
      expect(common.role, CouncillorRole.commonCouncillor);
      expect(common.memberships, ['Court of Common Council']);
      expect(common.termYears, 4);
      expect(common.isPaid, isFalse);
    });
  });
}
