import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/member.dart';
import '../viewmodels/house_seating_viewmodel.dart' show HouseType;
import 'party_tokens.dart';

/// Computes normalized (0–1) seat positions for a realistic UK Parliament chamber layout.
List<Offset> buildChamberLayout({
  required HouseType house,
  required List<Member> members,
}) {
  if (members.isEmpty) return const [];

  final positions = <int, Offset>{};

  // 1. Classify members
  final speakers = <Member>[];
  final governments = <Member>[];
  final crossbenchers = <Member>[];
  final oppositions = <Member>[];

  for (final m in members) {
    final token = canonicalPartyToken(m.partyAbbreviation.isNotEmpty ? m.partyAbbreviation : m.party) ?? '';
    if (token == 'speaker') {
      speakers.add(m);
    } else if (token == 'labour') {
      governments.add(m);
    } else if (house == HouseType.lords && token == 'crossbench') {
      crossbenchers.add(m);
    } else {
      oppositions.add(m);
    }
  }

  // 2. Position Speaker(s)
  // Speaker sits in the Chair on the left center
  if (speakers.isNotEmpty) {
    positions[speakers[0].id] = const Offset(0.06, 0.5);
    // If there are more speakers (fallback), put them close by
    for (var i = 1; i < speakers.length; i++) {
      positions[speakers[i].id] = Offset(0.06, 0.5 + (i * 0.02));
    }
  }

  // 3. Position Government (Top Benches)
  // 5 rows: outer to inner: 0.08, 0.15, 0.22, 0.29, 0.36
  const govRowsY = [0.08, 0.15, 0.22, 0.29, 0.36];
  const double govXStartLeft = 0.16;
  final double govXEndLeft = house == HouseType.commons ? 0.52 : 0.46;
  final double govXStartRight = house == HouseType.commons ? 0.58 : 0.52;
  final double govXEndRight = house == HouseType.commons ? 0.94 : 0.80;

  final govRowCounts = _distributeSeats(governments.length, 5, [4, 3, 2, 1, 0]);
  var govIndex = 0;
  for (var r = 0; r < 5; r++) {
    final count = govRowCounts[r];
    final y = govRowsY[r];
    if (count <= 0) continue;

    final leftCount = (count / 2).ceil();
    final rightCount = count - leftCount;

    // Left block
    for (var i = 0; i < leftCount; i++) {
      final t = leftCount == 1 ? 0.5 : (i + 0.5) / leftCount;
      final x = govXStartLeft + (govXEndLeft - govXStartLeft) * t;
      positions[governments[govIndex++].id] = Offset(x, y);
    }
    // Right block
    for (var i = 0; i < rightCount; i++) {
      final t = rightCount == 1 ? 0.5 : (i + 0.5) / rightCount;
      final x = govXStartRight + (govXEndRight - govXStartRight) * t;
      positions[governments[govIndex++].id] = Offset(x, y);
    }
  }

  // 4. Position Opposition (Bottom Benches)
  // 5 rows: inner to outer: 0.64, 0.71, 0.78, 0.85, 0.92
  const oppRowsY = [0.64, 0.71, 0.78, 0.85, 0.92];
  const double oppXStartLeft = 0.16;
  final double oppXEndLeft = house == HouseType.commons ? 0.52 : 0.46;
  final double oppXStartRight = house == HouseType.commons ? 0.58 : 0.52;
  final double oppXEndRight = house == HouseType.commons ? 0.94 : 0.80;

  final oppRowCounts = _distributeSeats(oppositions.length, 5, [0, 1, 2, 3, 4]);
  var oppIndex = 0;
  for (var r = 0; r < 5; r++) {
    final count = oppRowCounts[r];
    final y = oppRowsY[r];
    if (count <= 0) continue;

    final leftCount = (count / 2).ceil();
    final rightCount = count - leftCount;

    // Left block
    for (var i = 0; i < leftCount; i++) {
      final t = leftCount == 1 ? 0.5 : (i + 0.5) / leftCount;
      final x = oppXStartLeft + (oppXEndLeft - oppXStartLeft) * t;
      positions[oppositions[oppIndex++].id] = Offset(x, y);
    }
    // Right block
    for (var i = 0; i < rightCount; i++) {
      final t = rightCount == 1 ? 0.5 : (i + 0.5) / rightCount;
      final x = oppXStartRight + (oppXEndRight - oppXStartRight) * t;
      positions[oppositions[oppIndex++].id] = Offset(x, y);
    }
  }

  // 5. Position Crossbenchers (Lords only, Right Side)
  // 5 columns: 0.82, 0.85, 0.88, 0.91, 0.94
  if (house == HouseType.lords && crossbenchers.isNotEmpty) {
    final cbColsX = [0.82, 0.85, 0.88, 0.91, 0.94];
    final cbColCounts = _distributeSeats(crossbenchers.length, 5, [0, 1, 2, 3, 4]);
    var cbIndex = 0;
    for (var c = 0; c < 5; c++) {
      final count = cbColCounts[c];
      final x = cbColsX[c];
      if (count <= 0) continue;

      for (var i = 0; i < count; i++) {
        final t = count == 1 ? 0.5 : (i + 0.5) / count;
        // Spanning vertically from Y = 0.20 to 0.80
        final y = 0.20 + (0.80 - 0.20) * t;
        positions[crossbenchers[cbIndex++].id] = Offset(x, y);
      }
    }
  }

  return [
    for (final m in members) positions[m.id] ?? const Offset(0.5, 0.5),
  ];
}

List<int> _distributeSeats(int total, int parts, List<int> preferredOrder) {
  final base = total ~/ parts;
  final counts = List<int>.filled(parts, base);
  final remainder = total % parts;
  for (var i = 0; i < remainder; i++) {
    counts[preferredOrder[i % preferredOrder.length]]++;
  }
  return counts;
}

/// Kept for compatibility. Computes normalized (0–1) seat positions for a hemicycle layout.
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

