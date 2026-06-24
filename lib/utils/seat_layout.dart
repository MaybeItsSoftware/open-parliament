import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Computes normalized (0–1) seat positions for a hemicycle layout.
List<Offset> buildHemicycleLayout(int seatCount) {
  if (seatCount <= 0) return const [];

  final rows = _rowCountForSeats(seatCount);
  final weights = [for (var i = 0; i < rows; i++) i + 1];
  final totalWeight = weights.fold<int>(0, (sum, w) => sum + w);

  final seatsPerRow = [
    for (final w in weights) (seatCount * w / totalWeight).floor(),
  ];
  final allocated = seatsPerRow.fold<int>(0, (sum, v) => sum + v);
  var remaining = seatCount - allocated;

  for (var i = rows - 1; i >= 0 && remaining > 0; i--) {
    seatsPerRow[i]++;
    remaining--;
  }

  for (var i = 0; i < rows; i++) {
    if (seatsPerRow[i] == 0) {
      seatsPerRow[i] = 1;
      remaining--;
    }
  }
  if (remaining < 0) {
    for (var i = rows - 1; i >= 0 && remaining < 0; i--) {
      if (seatsPerRow[i] > 1) {
        seatsPerRow[i]--;
        remaining++;
      }
    }
  }

  final positions = <Offset>[];
  const center = Offset(0.5, 0.95);
  // Elliptical radii: the horizontal radius stays within the unit box's
  // half-width (0.5) so seats never overflow the sides, while the vertical
  // radius can fill nearly the full height up from the bottom-centre.
  const rxInner = 0.14, rxOuter = 0.48;
  const ryInner = 0.26, ryOuter = 0.90;

  for (var row = 0; row < rows; row++) {
    final frac = (row + 1) / rows;
    final rx = rxInner + (rxOuter - rxInner) * frac;
    final ry = ryInner + (ryOuter - ryInner) * frac;
    final rowSeats = seatsPerRow[row];
    for (var i = 0; i < rowSeats; i++) {
      final t = (i + 1) / (rowSeats + 1);
      final angle = math.pi - (t * math.pi);
      final x = center.dx + rx * math.cos(angle);
      final y = center.dy - ry * math.sin(angle);
      positions.add(Offset(x, y));
    }
  }

  return positions;
}

int _rowCountForSeats(int seatCount) {
  final estimate = (seatCount / 50).ceil();
  return math.min(estimate.clamp(6, 18), seatCount);
}
