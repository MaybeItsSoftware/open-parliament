import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
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

  group('simplifyRing', () {
    // A closed square with a redundant midpoint on each edge.
    final square = [
      const LatLng(0, 0),
      const LatLng(0, 0.5),
      const LatLng(0, 1),
      const LatLng(0.5, 1),
      const LatLng(1, 1),
      const LatLng(1, 0.5),
      const LatLng(1, 0),
      const LatLng(0.5, 0),
      const LatLng(0, 0),
    ];

    test('drops points within tolerance but keeps corners', () {
      final simplified = simplifyRing(square, 0.01);
      expect(simplified, [
        const LatLng(0, 0),
        const LatLng(0, 1),
        const LatLng(1, 1),
        const LatLng(1, 0),
        const LatLng(0, 0),
      ]);
    });

    test('keeps points that deviate more than the tolerance', () {
      final ring = [
        const LatLng(0, 0),
        const LatLng(0.05, 0.5), // 0.05° off the 0→1 edge: beyond tolerance
        const LatLng(0, 1),
        const LatLng(1, 1),
        const LatLng(1, 0),
        const LatLng(0, 0),
      ];
      final simplified = simplifyRing(ring, 0.01);
      expect(simplified, contains(const LatLng(0.05, 0.5)));
    });

    test('tolerance 0 returns the ring untouched', () {
      expect(simplifyRing(square, 0), same(square));
    });

    test('stays closed: first and last points are always kept', () {
      final simplified = simplifyRing(square, 0.01);
      expect(simplified.first, simplified.last);
    });

    test('collapses sub-tolerance rings so the parser drops them', () {
      final geojson = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'name': 'Speck'},
            'geometry': {
              'type': 'MultiPolygon',
              'coordinates': [
                // A real square, 1° across…
                [
                  [
                    [0.0, 0.0],
                    [1.0, 0.0],
                    [1.0, 1.0],
                    [0.0, 1.0],
                    [0.0, 0.0],
                  ],
                ],
                // …and an island smaller than the tolerance, which must go.
                [
                  [
                    [5.0, 5.0],
                    [5.001, 5.0],
                    [5.001, 5.001],
                    [5.0, 5.001],
                    [5.0, 5.0],
                  ],
                ],
              ],
            },
          },
        ],
      };

      final boundaries = parseGeoJsonBoundaries(geojson, simplifyTolerance: 0.01);
      expect(boundaries, hasLength(1));
      expect(boundaries.single.outer, hasLength(5));
    });

    test('simplifies holes as well as the outer ring', () {
      final geojson = {
        'type': 'FeatureCollection',
        'features': [
          {
            'type': 'Feature',
            'properties': {'name': 'Doughnut'},
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [0.0, 0.0],
                  [3.0, 0.0],
                  [3.0, 3.0],
                  [0.0, 3.0],
                  [0.0, 0.0],
                ],
                [
                  [1.0, 1.0],
                  [1.5, 1.0], // redundant midpoint on the hole's edge
                  [2.0, 1.0],
                  [2.0, 2.0],
                  [1.0, 2.0],
                  [1.0, 1.0],
                ],
              ],
            },
          },
        ],
      };

      final boundaries = parseGeoJsonBoundaries(geojson, simplifyTolerance: 0.01);
      expect(boundaries.single.holes.single, hasLength(5));
    });
  });
}
