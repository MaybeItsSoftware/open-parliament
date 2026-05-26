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
    // Without a nameKey, polygons carry no name.
    expect(boundaries.first.name, '');
  });

  test('tags polygons with the named property when nameKey is given', () {
    final geojson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'PCON24NM': 'Aldershot'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [0.0, 0.0],
                [1.0, 0.0],
                [1.0, 1.0],
                [0.0, 0.0],
              ],
            ],
          },
        },
      ],
    };

    final boundaries = parseGeoJsonBoundaries(geojson, nameKey: 'PCON24NM');
    expect(boundaries.single.name, 'Aldershot');
  });

  test('drops degenerate rings with fewer than three points', () {
    final geojson = {
      'type': 'FeatureCollection',
      'features': [
        {
          'type': 'Feature',
          'properties': {'name': 'Tiny island'},
          'geometry': {
            'type': 'MultiPolygon',
            'coordinates': [
              // A real triangle…
              [
                [
                  [0.0, 0.0],
                  [1.0, 0.0],
                  [1.0, 1.0],
                  [0.0, 0.0],
                ],
              ],
              // …and a collapsed island of two points, which must be dropped.
              [
                [
                  [5.0, 5.0],
                  [5.0, 5.1],
                ],
              ],
            ],
          },
        },
      ],
    };

    final boundaries = parseGeoJsonBoundaries(geojson);
    expect(boundaries, hasLength(1));
    expect(boundaries.single.outer, hasLength(4));
  });
}
