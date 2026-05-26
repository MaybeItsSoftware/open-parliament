import 'package:latlong2/latlong.dart';

/// A single polygon boundary, optionally with interior holes.
///
/// [name] is the area's official name (e.g. the constituency or local-authority
/// name) when it could be read from the source feature; empty otherwise. It is
/// what lets the map join a polygon to its political control.
class BoundaryPolygon {
  final List<LatLng> outer;
  final List<List<LatLng>> holes;
  final String name;

  const BoundaryPolygon({
    required this.outer,
    this.holes = const [],
    this.name = '',
  });
}
