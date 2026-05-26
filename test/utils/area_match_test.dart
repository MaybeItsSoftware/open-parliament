import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:open_hansard/models/boundary.dart';
import 'package:open_hansard/utils/area_match.dart';

void main() {
  group('normaliseName', () {
    test('lowercases, expands & and strips punctuation', () {
      expect(normaliseName('Cities of London & Westminster'),
          'cities of london and westminster');
      expect(normaliseName("Ynys Môn"), isNot(contains('ô')));
    });
  });

  group('normaliseCouncilName', () {
    test('drops generic descriptor words so ONS and OCD names align', () {
      // ONS form vs OpenCouncilData form should normalise identically.
      expect(normaliseCouncilName('Bristol, City of'),
          normaliseCouncilName('Bristol'));
      expect(normaliseCouncilName('Kingston upon Hull, City of'),
          normaliseCouncilName('Kingston upon Hull'));
      expect(normaliseCouncilName('Aberdeen City'), 'aberdeen');
    });
  });

  group('isCityOfLondonCouncil', () {
    test('matches City of London Corporation variations', () {
      expect(isCityOfLondonCouncil('City of London'), isTrue);
      expect(isCityOfLondonCouncil('City of London Corporation'), isTrue);
      expect(isCityOfLondonCouncil('London Borough of Camden'), isFalse);
    });
  });

  group('boundaryContainsPoint', () {
    const square = BoundaryPolygon(
      outer: [
        LatLng(0, 0),
        LatLng(0, 10),
        LatLng(10, 10),
        LatLng(10, 0),
      ],
      holes: [
        [
          LatLng(4, 4),
          LatLng(4, 6),
          LatLng(6, 6),
          LatLng(6, 4),
        ],
      ],
    );

    test('true inside the outer ring', () {
      expect(boundaryContainsPoint(square, const LatLng(2, 2)), isTrue);
    });

    test('false outside the outer ring', () {
      expect(boundaryContainsPoint(square, const LatLng(20, 20)), isFalse);
    });

    test('false inside a hole', () {
      expect(boundaryContainsPoint(square, const LatLng(5, 5)), isFalse);
    });
  });
}
