import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../models/boundary.dart';

/// A GeoJSON string paired with the property key to read area names from,
/// bundled so it can cross an isolate boundary as `compute`'s single message.
class GeoJsonParseRequest {
  final String json;
  final String? nameKey;
  const GeoJsonParseRequest(this.json, this.nameKey);
}

/// Decodes and parses a GeoJSON string into boundary polygons.
///
/// Top-level so it can run in a background isolate via `compute`: the source
/// files are several megabytes, and decoding/parsing them on the UI isolate
/// freezes the map while it loads.
List<BoundaryPolygon> parseGeoJsonString(GeoJsonParseRequest request) {
  final decoded = jsonDecode(request.json) as Map<String, dynamic>;
  return parseGeoJsonBoundaries(decoded, nameKey: request.nameKey);
}

/// Parses GeoJSON FeatureCollections containing Polygon/MultiPolygon geometry.
///
/// When [nameKey] is given, each polygon is tagged with
/// `feature['properties'][nameKey]` so the map can join it to political
/// control; otherwise [BoundaryPolygon.name] is left empty.
List<BoundaryPolygon> parseGeoJsonBoundaries(
  Map<String, dynamic> json, {
  String? nameKey,
}) {
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
    final name = nameKey == null
        ? ''
        : ((feature['properties'] as Map<String, dynamic>?)?[nameKey]
                as String?) ??
            '';
    final type = geometry['type'];
    final coordinates = geometry['coordinates'];
    if (type == 'Polygon') {
      boundaries.addAll(_parsePolygonCoordinates(coordinates, name));
    } else if (type == 'MultiPolygon') {
      if (coordinates is! List) {
        throw const FormatException('MultiPolygon coordinates are invalid.');
      }
      for (final polygonCoords in coordinates) {
        boundaries.addAll(_parsePolygonCoordinates(polygonCoords, name));
      }
    } else {
      throw FormatException('Unsupported geometry type: $type');
    }
  }

  return boundaries;
}

List<BoundaryPolygon> _parsePolygonCoordinates(
  dynamic coordinates,
  String name,
) {
  if (coordinates is! List) {
    throw const FormatException('Polygon coordinates are invalid.');
  }
  if (coordinates.isEmpty) return const [];

  final outer = _parseRing(coordinates.first);
  // Generalised boundaries can collapse tiny islands to one or two points;
  // such degenerate rings aren't renderable polygons and trip flutter_map's
  // hit-test assertion ("not a polygon"), so drop them.
  if (outer.length < 3) return const [];
  final holes = <List<LatLng>>[];
  for (final ring in coordinates.skip(1)) {
    final hole = _parseRing(ring);
    if (hole.length >= 3) holes.add(hole);
  }
  return [BoundaryPolygon(outer: outer, holes: holes, name: name)];
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
