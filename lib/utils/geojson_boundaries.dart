import 'dart:convert';

import 'package:latlong2/latlong.dart';

import '../models/boundary.dart';

/// A GeoJSON string paired with the property key to read area names from,
/// bundled so it can cross an isolate boundary as `compute`'s single message.
class GeoJsonParseRequest {
  final String json;
  final String? nameKey;

  /// Douglas–Peucker tolerance in coordinate degrees applied to every ring
  /// after parsing; 0 keeps the source geometry untouched. This guards against
  /// sources that return far more detail than the map can usefully render
  /// (the ArcGIS gateway sometimes ignores server-side simplification).
  final double simplifyTolerance;

  const GeoJsonParseRequest(this.json, this.nameKey,
      {this.simplifyTolerance = 0});
}

/// Decodes and parses a GeoJSON string into boundary polygons.
///
/// Top-level so it can run in a background isolate via `compute`: the source
/// files are several megabytes, and decoding/parsing them on the UI isolate
/// freezes the map while it loads.
List<BoundaryPolygon> parseGeoJsonString(GeoJsonParseRequest request) {
  final decoded = jsonDecode(request.json) as Map<String, dynamic>;
  return parseGeoJsonBoundaries(
    decoded,
    nameKey: request.nameKey,
    simplifyTolerance: request.simplifyTolerance,
  );
}

/// Parses GeoJSON FeatureCollections containing Polygon/MultiPolygon geometry.
///
/// When [nameKey] is given, each polygon is tagged with
/// `feature['properties'][nameKey]` so the map can join it to political
/// control; otherwise [BoundaryPolygon.name] is left empty.
///
/// A non-zero [simplifyTolerance] (coordinate degrees) runs Douglas–Peucker
/// over every ring; see [simplifyRing].
List<BoundaryPolygon> parseGeoJsonBoundaries(
  Map<String, dynamic> json, {
  String? nameKey,
  double simplifyTolerance = 0,
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
      boundaries
          .addAll(_parsePolygonCoordinates(coordinates, name, simplifyTolerance));
    } else if (type == 'MultiPolygon') {
      if (coordinates is! List) {
        throw const FormatException('MultiPolygon coordinates are invalid.');
      }
      for (final polygonCoords in coordinates) {
        boundaries
            .addAll(_parsePolygonCoordinates(polygonCoords, name, simplifyTolerance));
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
  double simplifyTolerance,
) {
  if (coordinates is! List) {
    throw const FormatException('Polygon coordinates are invalid.');
  }
  if (coordinates.isEmpty) return const [];

  final outer = simplifyRing(_parseRing(coordinates.first), simplifyTolerance);
  // Generalised boundaries can collapse tiny islands to one or two points;
  // such degenerate rings aren't renderable polygons and trip flutter_map's
  // hit-test assertion ("not a polygon"), so drop them.
  if (outer.length < 3) return const [];
  final holes = <List<LatLng>>[];
  for (final ring in coordinates.skip(1)) {
    final hole = simplifyRing(_parseRing(ring), simplifyTolerance);
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

/// Simplifies [ring] with Douglas–Peucker: points closer than [tolerance]
/// (in coordinate degrees) to the simplified outline are dropped; the first
/// and last points are always kept, so closed rings stay closed.
///
/// A [tolerance] of 0 (or a ring already at minimal size) returns [ring]
/// unchanged. A ring whose interior detail all falls within [tolerance]
/// collapses to its endpoints, letting the caller drop it as degenerate.
List<LatLng> simplifyRing(List<LatLng> ring, double tolerance) {
  if (tolerance <= 0 || ring.length <= 4) return ring;
  final toleranceSq = tolerance * tolerance;
  final keep = List<bool>.filled(ring.length, false);
  keep[0] = true;
  keep[ring.length - 1] = true;
  // Explicit work stack of (start, end) ranges: coastline rings run to
  // 100k+ points, deeper than recursion comfortably allows.
  final ranges = <(int, int)>[(0, ring.length - 1)];
  while (ranges.isNotEmpty) {
    final (start, end) = ranges.removeLast();
    var maxDistanceSq = 0.0;
    var farthest = -1;
    for (var i = start + 1; i < end; i++) {
      final d = _segmentDistanceSq(ring[i], ring[start], ring[end]);
      if (d > maxDistanceSq) {
        maxDistanceSq = d;
        farthest = i;
      }
    }
    if (farthest >= 0 && maxDistanceSq > toleranceSq) {
      keep[farthest] = true;
      ranges
        ..add((start, farthest))
        ..add((farthest, end));
    }
  }
  return [
    for (var i = 0; i < ring.length; i++)
      if (keep[i]) ring[i],
  ];
}

/// Squared distance in degree space from [p] to the segment [a]–[b].
double _segmentDistanceSq(LatLng p, LatLng a, LatLng b) {
  var x = a.longitude;
  var y = a.latitude;
  var dx = b.longitude - x;
  var dy = b.latitude - y;
  if (dx != 0 || dy != 0) {
    final t =
        ((p.longitude - x) * dx + (p.latitude - y) * dy) / (dx * dx + dy * dy);
    if (t > 1) {
      x = b.longitude;
      y = b.latitude;
    } else if (t > 0) {
      x += dx * t;
      y += dy * t;
    }
  }
  dx = p.longitude - x;
  dy = p.latitude - y;
  return dx * dx + dy * dy;
}
