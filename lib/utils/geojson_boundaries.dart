import 'package:latlong2/latlong.dart';

import '../models/boundary.dart';

/// Parses GeoJSON FeatureCollections containing Polygon/MultiPolygon geometry.
List<BoundaryPolygon> parseGeoJsonBoundaries(
  Map<String, dynamic> json,
) {
  final features = json['features'];
  if (features is! List) {
    throw const FormatException('GeoJSON is missing feature list.');
  }

  final boundaries = <BoundaryPolygon>[];
  for (final feature in features) {
    if (feature is! Map<String, dynamic>) {
      throw const FormatException('GeoJSON feature is not an object.');
    }
    final geometry = feature['geometry'];
    if (geometry is! Map<String, dynamic>) {
      throw const FormatException('GeoJSON feature is missing geometry.');
    }
    final type = geometry['type'];
    final coordinates = geometry['coordinates'];
    if (type == 'Polygon') {
      boundaries.addAll(_parsePolygonCoordinates(coordinates));
    } else if (type == 'MultiPolygon') {
      if (coordinates is! List) {
        throw const FormatException('MultiPolygon coordinates are invalid.');
      }
      for (final polygonCoords in coordinates) {
        boundaries.addAll(_parsePolygonCoordinates(polygonCoords));
      }
    } else {
      throw FormatException('Unsupported geometry type: $type');
    }
  }

  return boundaries;
}

List<BoundaryPolygon> _parsePolygonCoordinates(dynamic coordinates) {
  if (coordinates is! List) {
    throw const FormatException('Polygon coordinates are invalid.');
  }
  if (coordinates.isEmpty) return const [];

  final outer = _parseRing(coordinates.first);
  final holes = <List<LatLng>>[];
  for (final ring in coordinates.skip(1)) {
    holes.add(_parseRing(ring));
  }
  return [BoundaryPolygon(outer: outer, holes: holes)];
}

List<LatLng> _parseRing(dynamic ring) {
  if (ring is! List) {
    throw const FormatException('Polygon ring is invalid.');
  }
  return [
    for (final point in ring) _parsePoint(point),
  ];
}

LatLng _parsePoint(dynamic point) {
  if (point is! List || point.length < 2) {
    throw const FormatException('Polygon point is invalid.');
  }
  final lon = (point[0] as num?)?.toDouble();
  final lat = (point[1] as num?)?.toDouble();
  if (lat == null || lon == null) {
    throw const FormatException('Polygon point is missing coordinates.');
  }
  return LatLng(lat, lon);
}
