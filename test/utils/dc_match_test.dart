import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/utils/dc_match.dart';

void main() {
  group('dcCouncilSlug', () {
    test('slugifies council names to Democracy Club form', () {
      expect(dcCouncilSlug('Amber Valley'), 'amber-valley');
      expect(dcCouncilSlug('Cambridgeshire'), 'cambridgeshire');
      expect(dcCouncilSlug('City of London'), 'city-of-london');
      expect(dcCouncilSlug('Kingston upon Hull, City of'),
          'kingston-upon-hull-city-of');
      expect(dcCouncilSlug('Stockton-on-Tees'), 'stockton-on-tees');
    });
  });

  group('namesMatch', () {
    test('matches identical names', () {
      expect(namesMatch('John Smith', 'John Smith'), isTrue);
    });

    test('tolerates DC middle names and honorifics', () {
      expect(namesMatch('Susan Mary Hall', 'Susan Hall'), isTrue);
      expect(namesMatch('Cllr John Smith', 'John Smith'), isTrue);
      expect(namesMatch('Alderman Jane Doe', 'Jane Doe'), isTrue);
    });

    test('matches a first initial against a full first name', () {
      expect(namesMatch('J Smith', 'John Smith'), isTrue);
    });

    test('rejects different surnames', () {
      expect(namesMatch('John Smith', 'John Jones'), isFalse);
    });

    test('rejects different first names with the same surname', () {
      expect(namesMatch('John Smith', 'Peter Smith'), isFalse);
    });

    test('matches a genuine first-name prefix of 3+ chars', () {
      expect(namesMatch('Cath Brown', 'Catherine Brown'), isTrue);
    });

    test('does not fuzzy-match nicknames that are not prefixes', () {
      // "Cathy" is not a prefix of "Catherine"; we stay conservative.
      expect(namesMatch('Cathy Brown', 'Catherine Brown'), isFalse);
    });

    test('is empty-safe', () {
      expect(namesMatch('', 'John Smith'), isFalse);
      expect(namesMatch('Cllr', 'John Smith'), isFalse);
    });
  });
}
