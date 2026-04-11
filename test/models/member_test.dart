import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/member.dart';

void main() {
  group('Member', () {
    const testJson = {
      'value': {
        'id': 172,
        'nameDisplayAs': 'Adam Smith',
        'thumbnailUrl': 'https://example.com/portrait.jpg',
        'latestParty': {
          'name': 'Labour',
          'abbreviation': 'Lab',
        },
      },
    };

    test('fromApiJson parses wrapped value object', () {
      final member = Member.fromApiJson(testJson);

      expect(member.id, 172);
      expect(member.name, 'Adam Smith');
      expect(member.party, 'Labour');
      expect(member.partyAbbreviation, 'Lab');
      expect(member.thumbnailUrl, 'https://example.com/portrait.jpg');
    });

    test('fromApiJson parses flat (unwrapped) json', () {
      const flat = {
        'id': 172,
        'nameDisplayAs': 'Adam Smith',
        'thumbnailUrl': null,
        'latestParty': {'name': 'Labour', 'abbreviation': 'Lab'},
      };
      final member = Member.fromApiJson(flat);
      expect(member.id, 172);
      expect(member.thumbnailUrl, isNull);
    });

    test('fromApiJson handles missing party gracefully', () {
      final member = Member.fromApiJson({
        'value': {
          'id': 1,
          'nameDisplayAs': 'Unknown MP',
        },
      });
      expect(member.party, isEmpty);
      expect(member.partyAbbreviation, isEmpty);
    });

    test('toDb / fromDb round-trip', () {
      const member = Member(
        id: 42,
        name: 'Jane Doe',
        party: 'Conservative',
        partyAbbreviation: 'Con',
        thumbnailUrl: 'https://example.com/img.jpg',
      );

      final row = member.toDb();
      final restored = Member.fromDb(row);

      expect(restored.id, member.id);
      expect(restored.name, member.name);
      expect(restored.party, member.party);
      expect(restored.partyAbbreviation, member.partyAbbreviation);
      expect(restored.thumbnailUrl, member.thumbnailUrl);
    });

    test('equality is based on id', () {
      const a = Member(
        id: 1,
        name: 'A',
        party: 'X',
        partyAbbreviation: 'X',
      );
      const b = Member(
        id: 1,
        name: 'B',
        party: 'Y',
        partyAbbreviation: 'Y',
      );
      expect(a, equals(b));
    });

    test('toString includes id and party', () {
      const member = Member(
        id: 99,
        name: 'Test MP',
        party: 'Labour',
        partyAbbreviation: 'Lab',
      );
      expect(member.toString(), contains('99'));
      expect(member.toString(), contains('Labour'));
    });
  });
}
