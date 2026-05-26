import 'package:latlong2/latlong.dart';

import '../models/boundary.dart';

/// Normalises an area name for joining boundary polygons to data keyed by name.
///
/// Lowercases, expands `&`, strips punctuation and collapses whitespace. Use
/// this for constituencies, whose names match exactly between the ONS boundary
/// layer and the Members API.
String normaliseName(String name) {
  return name
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// True when [name] refers to the City of London Corporation.
bool isCityOfLondonCouncil(String name) {
  final normalized = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return normalized == 'city of london' ||
      normalized == 'city of london corporation';
}

// Generic words that differ between the ONS local-authority names
// ("Kingston upon Hull, City of") and OpenCouncilData's shorter forms.
const Set<String> _councilStopWords = {
  'council',
  'borough',
  'district',
  'county',
  'city',
  'metropolitan',
  'unitary',
  'of',
  'the',
};

/// Like [normaliseName] but also drops generic council descriptor words so that
/// ONS local-authority names line up with OpenCouncilData council names.
String normaliseCouncilName(String name) {
  final words = normaliseName(name)
      .split(' ')
      .where((w) => w.isNotEmpty && !_councilStopWords.contains(w));
  return words.join(' ');
}

/// True when [point] lies inside the boundary (inside the outer ring and not
/// inside any hole). Used to identify the area under a map tap.
bool boundaryContainsPoint(BoundaryPolygon boundary, LatLng point) {
  if (!_ringContains(boundary.outer, point)) return false;
  for (final hole in boundary.holes) {
    if (_ringContains(hole, point)) return false;
  }
  return true;
}

/// Standard ray-casting point-in-polygon test.
bool _ringContains(List<LatLng> ring, LatLng point) {
  if (ring.length < 3) return false;
  final x = point.longitude;
  final y = point.latitude;
  var inside = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final xi = ring[i].longitude, yi = ring[i].latitude;
    final xj = ring[j].longitude, yj = ring[j].latitude;
    final intersects = ((yi > y) != (yj > y)) &&
        (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
    if (intersects) inside = !inside;
  }
  return inside;
}
