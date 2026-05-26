import 'package:flutter/foundation.dart';

/// A single data point in a historical trend (e.g., seat count in a specific year).
class HistoricalDataPoint {
  final int year;
  final int value;

  const HistoricalDataPoint({required this.year, required this.value});

  @override
  String toString() => '$year: $value';
}

/// A list of historical data points, typically covering several years.
class HistoricalTrend {
  final String label;
  final List<HistoricalDataPoint> points;

  const HistoricalTrend({required this.label, required this.points});

  /// The most recent value in the trend, or 0 if empty.
  int get latestValue => points.isNotEmpty ? points.last.value : 0;

  /// The percentage change from the first point to the last point.
  double get totalChangePercent {
    if (points.length < 2 || points.first.value == 0) return 0.0;
    return (points.last.value - points.first.value) / points.first.value * 100;
  }
}

/// Aggregate statistics for a political party.
@immutable
class PartyStats {
  final String partyName;
  final String partyToken;

  // Current counts
  final int mpCount;
  final int lordCount;
  final int councillorCount;
  final int councilsControlled;

  // Historical trends (Year -> Count)
  final HistoricalTrend mpTrend;
  final HistoricalTrend lordTrend;
  final HistoricalTrend councillorTrend;
  final HistoricalTrend councilsControlledTrend;

  const PartyStats({
    required this.partyName,
    required this.partyToken,
    this.mpCount = 0,
    this.lordCount = 0,
    this.councillorCount = 0,
    this.councilsControlled = 0,
    this.mpTrend = const HistoricalTrend(label: 'MPs', points: []),
    this.lordTrend = const HistoricalTrend(label: 'Lords', points: []),
    this.councillorTrend = const HistoricalTrend(label: 'Councillors', points: []),
    this.councilsControlledTrend = const HistoricalTrend(label: 'Councils', points: []),
  });

  PartyStats copyWith({
    int? mpCount,
    int? lordCount,
    int? councillorCount,
    int? councilsControlled,
    HistoricalTrend? mpTrend,
    HistoricalTrend? lordTrend,
    HistoricalTrend? councillorTrend,
    HistoricalTrend? councilsControlledTrend,
  }) {
    return PartyStats(
      partyName: partyName,
      partyToken: partyToken,
      mpCount: mpCount ?? this.mpCount,
      lordCount: lordCount ?? this.lordCount,
      councillorCount: councillorCount ?? this.councillorCount,
      councilsControlled: councilsControlled ?? this.councilsControlled,
      mpTrend: mpTrend ?? this.mpTrend,
      lordTrend: lordTrend ?? this.lordTrend,
      councillorTrend: councillorTrend ?? this.councillorTrend,
      councilsControlledTrend: councilsControlledTrend ?? this.councilsControlledTrend,
    );
  }
}
