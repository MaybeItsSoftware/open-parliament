import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/models/councillor_profile.dart';

void main() {
  group('CouncillorProfile.fromPersonJson', () {
    // Shape mirrors Democracy Club's next/people/{id} response.
    final json = {
      'id': 1234,
      'name': 'Susan Mary Hall',
      'image': 'https://dc.example/full.jpg',
      'thumbnail': 'https://dc.example/thumb.jpg',
      'email': null,
      'identifiers': [
        {'value': 'susan@example.com', 'value_type': 'email'},
        {'value': 'susanhall', 'value_type': 'twitter_username'},
        {'value': 'https://facebook.com/susan', 'value_type': 'facebook_page_url'},
        {'value': 'https://susanhall.example', 'value_type': 'homepage_url'},
      ],
      'candidacies': [
        {
          'elected': true,
          'ballot': {'ballot_paper_id': 'local.foo.ward.2024-05-02'},
        },
        {
          'elected': true,
          'ballot': {'ballot_paper_id': 'local.foo.ward.2021-05-06'},
        },
        {
          'elected': false,
          'ballot': {'ballot_paper_id': 'local.foo.ward.2018-05-03'},
        },
      ],
    };

    test('extracts photo, email, links and earliest elected year', () {
      final p = CouncillorProfile.fromPersonJson(json);
      expect(p.personId, 1234);
      expect(p.imageUrl, 'https://dc.example/full.jpg');
      expect(p.thumbnailUrl, 'https://dc.example/thumb.jpg');
      expect(p.email, 'susan@example.com');
      expect(p.firstElectedYear, 2021); // ignores the non-elected 2018 row
      expect(p.isEmpty, isFalse);

      final labels = p.links.map((l) => l.label).toList();
      expect(labels, containsAll(['Twitter/X', 'Facebook', 'Website']));
      final twitter = p.links.firstWhere((l) => l.label == 'Twitter/X');
      expect(twitter.url, 'https://twitter.com/susanhall');
    });

    test('survives the JSON cache round-trip', () {
      final p = CouncillorProfile.fromPersonJson(json);
      final round = CouncillorProfile.fromJson(p.toJson());
      expect(round.thumbnailUrl, p.thumbnailUrl);
      expect(round.email, p.email);
      expect(round.firstElectedYear, p.firstElectedYear);
      expect(round.links.length, p.links.length);
    });

    test('is empty when no photo, contact or election history is present', () {
      final p = CouncillorProfile.fromPersonJson({
        'id': 9,
        'name': 'No Data',
        'identifiers': const [],
        'candidacies': const [],
      });
      expect(p.isEmpty, isTrue);
    });
  });
}
