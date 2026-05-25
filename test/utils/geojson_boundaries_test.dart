import 'package:flutter_test/flutter_test.dart';
import 'package:open_hansard/utils/geojson_boundaries.dart';

void main() {
  test('parses polygon and multipolygon boundaries', () {
    final geojson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'name': 'A'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [0.0, 0.0],
                [1.0, 0.0],
                [1.0, 1.0],
                [0.0, 0.0],
              ],
              [
                [0.2, 0.2],
                [0.8, 0.2],
                [0.2, 0.2],
              ],
            ],
          },
        },
        {
          'type': 'Feature',
          'properties': {'name': 'B'},
          'geometry': {
            'type': 'MultiPolygon',
            'coordinates': [
              [
                [
                  [2.0, 2.0],
                  [3.0, 2.0],
                  [2.0, 2.0],
                ],
              ],
              [
                [
                  [4.0, 4.0],
                  [5.0, 4.0],
                  [4.0, 4.0],
                ],
              ],
            ],
          },
        },
      ],
    };

    final boundaries = parseGeoJsonBoundaries(geojson);
    expect(boundaries.length, 3);
    expect(boundaries.first.holes, hasLength(1));
    expect(boundaries.first.outer.first.latitude, 0.0);
    expect(boundaries.first.outer.first.longitude, 0.0);
  });
}
