import 'package:flutter_test/flutter_test.dart';
import 'package:open_parliament/models/member_contribution.dart';

void main() {
  test('fromJson reads the Spoken contributions search shape', () {
    final c = MemberContribution.fromJson(const {
      'ItemId': 51057832,
      'ContributionExtId': '97796962-F521-445F-9E72-45A632E24408',
      'ContributionText': ' There has been a lot of talk',
      'ContributionTextFull': 'There has been a lot of talk &amp; <i>more</i>',
      'DebateSection': 'Engagements',
      'DebateSectionExtId': '1528B846-974F-4135-BFDF-0A20C979E680',
      'SittingDate': '2026-11-11T00:00:00',
      'Section': 'Commons Chamber',
      'House': 'Commons',
    });
    expect(c.speechId, '51057832');
    expect(c.debateTitle, 'Engagements');
    expect(c.debateSectionId, '1528B846-974F-4135-BFDF-0A20C979E680');
    expect(c.sittingDate, DateTime(2026, 11, 11));
    expect(c.venue, 'Commons Chamber');
    expect(c.text, 'There has been a lot of talk & more');
  });

  test('falls back to the short text and the House', () {
    final c = MemberContribution.fromJson(const {
      'ContributionText': ' Short ',
      'DebateSection': 'X',
      'House': 'Lords',
    });
    expect(c.text, 'Short');
    expect(c.venue, 'Lords');
  });

  test('parseMemberContributions drops untitled rows', () {
    final list = parseMemberContributions(const [
      {'DebateSection': 'A', 'ItemId': 1},
      {'DebateSection': '', 'ItemId': 2},
      {'ItemId': 3},
    ]);
    expect(list.map((c) => c.speechId), ['1']);
  });
}
