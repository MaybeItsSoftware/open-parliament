import 'package:latlong2/latlong.dart';

/// A single polygon boundary, optionally with interior holes.
class BoundaryPolygon {
  final List<LatLng> outer;
  final List<List<LatLng>> holes;

  const BoundaryPolygon({
    required this.outer,
    this.holes = const [],
  });
}
