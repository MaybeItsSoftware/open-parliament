import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/council.dart';
import '../utils/council_control.dart';
import '../utils/uk_election_dates.dart';
import '../viewmodels/council_history_viewmodel.dart';
import 'control_split_bar.dart';

/// A stacked column-per-year graph of a council's control over time: each
/// column's height tracks the chamber size and its bands show the seat split by
/// party, so both control and the councillor split read across the years.
///
/// Columns stretch to fill the available width when few enough years are shown,
/// and scroll horizontally (newest on the right) once they no longer fit.
class CouncilControlHistoryChart extends StatelessWidget {
  /// Years newest-first (as stored by [CouncilHistoryViewModel.history]).
  final List<CouncilYearControl> history;

  const CouncilControlHistoryChart({super.key, required this.history});

  /// Height of the plotting area for the tallest (most seats) column.
  static const double _chartHeight = 120;
  static const double _columnGap = 6;

  /// Height reserved for the rotated date label under each column — full
  /// dates ("1 May 2024") are much wider than the columns, so the label is
  /// rotated 90° and this is its footprint along the (now vertical) text.
  static const double _labelHeight = 80;

  /// Below this width the columns no longer fit, so the chart scrolls instead
  /// of stretching to fill the row.
  static const double _minColumnWidth = 14;
  static const double _scrollColumnWidth = 20;

  /// A council's seat total, summed from the per-party counts. The source
  /// table's own "total" column is unreliable in the historical snapshots, so
  /// we derive it from the seats we actually parsed.
  static int seatTotal(Council council) =>
      council.seats.values.fold<int>(0, (sum, v) => sum + v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (history.isEmpty) return const SizedBox.shrink();

    // Oldest → newest along the time axis.
    final years = history.reversed.toList();
    final order = _partyOrder(years);
    final maxTotal = years
        .map((y) => seatTotal(y.council))
        .fold<int>(1, (m, t) => math.max(m, t));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _legend(theme, order),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final count = years.length;
            final gaps = _columnGap * (count - 1);
            final perColumn = (constraints.maxWidth - gaps) / count;
            // Few enough years to fit: stretch the columns to fill the width.
            if (perColumn >= _minColumnWidth) {
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: _chartHeight,
                    child: CustomPaint(
                      painter: ControlHistoryRibbonPainter(
                        years: years,
                        order: order,
                        maxTotal: maxTotal,
                        columnWidth: 0, // dynamic width
                        columnGap: _columnGap,
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < years.length; i++) ...[
                        if (i > 0) const SizedBox(width: _columnGap),
                        Expanded(
                          child: _column(theme, years[i], order, maxTotal),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            }
            // Too many to fit: scroll, newest on the right.
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: Stack(
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    height: _chartHeight,
                    child: CustomPaint(
                      painter: ControlHistoryRibbonPainter(
                        years: years,
                        order: order,
                        maxTotal: maxTotal,
                        columnWidth: _scrollColumnWidth,
                        columnGap: _columnGap,
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (final entry in years)
                        Padding(
                          padding: const EdgeInsets.only(right: _columnGap),
                          child: SizedBox(
                            width: _scrollColumnWidth,
                            child: _column(theme, entry, order, maxTotal),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  /// A single year's stacked column: total height tracks the chamber size, and
  /// bands (largest party at the base) show that year's seat split.
  Widget _column(
    ThemeData theme,
    CouncilYearControl entry,
    List<String> order,
    int maxTotal,
  ) {
    final council = entry.council;
    final total = seatTotal(council);
    // Empty space above the bar so column height is proportional to seats; the
    // whole column shares one flex scale (maxTotal) across years.
    final emptyFlex = (maxTotal - total).clamp(0, maxTotal);
    // Largest party at the bottom: a column lays out top→bottom, so render the
    // global order reversed (largest last = lowest).
    final segments = [
      for (final label in order.reversed)
        if ((council.seats[label] ?? 0) > 0)
          (label: label, value: council.seats[label]!),
    ];

    return Tooltip(
      message: _tooltip(entry, order),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: _chartHeight,
            // `stretch` keeps this footprint filling the column width so the
            // Tooltip above still has a real, tappable hit-test area — the
            // actual colour bands are painted by [ControlHistoryRibbonPainter]
            // underneath, so these boxes stay transparent.
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (emptyFlex > 0)
                  Expanded(flex: emptyFlex, child: const SizedBox()),
                Expanded(
                  flex: total > 0 ? total : 1,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final s in segments)
                        Expanded(
                          flex: s.value,
                          child: const ColoredBox(color: Colors.transparent),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: _labelHeight,
            child: Align(
              alignment: Alignment.topCenter,
              child: RotatedBox(
                quarterTurns: 3,
                child: Text(
                  _formatDate(approximateUkLocalElectionDate(entry.year)),
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Formats a date as e.g. "1 May 2024", matching the convention already
  /// used elsewhere in the app (see `bill_view.dart`/`member_view.dart`).
  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Widget _legend(ThemeData theme, List<String> order) {
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: [
        for (final label in order)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: controlSegmentColor(label),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(label, style: theme.textTheme.labelSmall),
            ],
          ),
      ],
    );
  }

  /// Long-press detail for a year: control label + each party's seat count.
  String _tooltip(CouncilYearControl entry, List<String> order) {
    final council = entry.council;
    final parts = [
      for (final label in order)
        if ((council.seats[label] ?? 0) > 0) '$label ${council.seats[label]}',
    ];
    final date = _formatDate(approximateUkLocalElectionDate(entry.year));
    return '$date · ${controlDisplayName(council.control)}\n'
        '${parts.join(', ')}';
  }

  /// A stable party stacking/legend order across all years: parties by total
  /// seats summed over the range (largest first), with "Vacant" last. Keeping
  /// the order fixed lets each party's band line up from year to year.
  List<String> _partyOrder(List<CouncilYearControl> years) {
    final totals = <String, int>{};
    String? vacantKey;
    for (final y in years) {
      for (final e in y.council.seats.entries) {
        if (e.value <= 0) continue;
        if (e.key.toLowerCase() == 'vacant') {
          vacantKey = e.key;
          continue;
        }
        totals[e.key] = (totals[e.key] ?? 0) + e.value;
      }
    }
    final ordered =
        totals.keys.toList()..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    return [...ordered, if (vacantKey != null) vacantKey];
  }
}

class ControlHistoryRibbonPainter extends CustomPainter {
  final List<CouncilYearControl> years;
  final List<String> order;
  final int maxTotal;
  final double columnWidth;
  final double columnGap;

  /// Bands narrower than this are bumped up to it so a small party's ribbon
  /// stays a visible filled shape rather than a near-invisible sliver — now
  /// that there's no bar behind it to carry the colour.
  static const double _minBandHeight = 2;

  ControlHistoryRibbonPainter({
    required this.years,
    required this.order,
    required this.maxTotal,
    required this.columnWidth,
    required this.columnGap,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (years.isEmpty || maxTotal <= 0) return;

    final count = years.length;
    // Stretched mode vs Scrollable mode:
    // If columnWidth is dynamic (i.e. <= 0), compute it from size.width.
    final colW =
        columnWidth > 0
            ? columnWidth
            : (size.width - columnGap * (count - 1)) / count;
    // The x-coordinate of each year's sample point: the centre of its old
    // column footprint. Ribbons are interpolated between these points, then
    // capped with a flat stub out to the chart edges.
    double nodeX(int i) => i * (colW + columnGap) + colW / 2;
    // Right edge of the last real column footprint (not `size.width`) — in
    // scroll mode the Row has a trailing gap after the newest column that
    // isn't between two years, so ribbons shouldn't bleed into it.
    final rightEdgeX = (count - 1) * (colW + columnGap) + colW;

    // Track each year's per-party vertical band, stacked bottom-up (largest
    // party at the base), matching `_column`'s stacking order.
    final bandY = List.generate(
      count,
      (_) => <String, ({double top, double bottom})>{},
    );

    for (var i = 0; i < count; i++) {
      final council = years[i].council;
      final total = CouncilControlHistoryChart.seatTotal(council);
      final double totalSeatsHeight = (total / maxTotal) * size.height;
      double yCurrent =
          size.height - totalSeatsHeight; // Start below empty space

      for (final label in order.reversed) {
        final seats = council.seats[label] ?? 0;
        if (seats > 0) {
          final double height = math.max(
            (seats / maxTotal) * size.height,
            _minBandHeight,
          );
          final double bottom = yCurrent + height;
          bandY[i][label] = (top: yCurrent, bottom: bottom);
          yCurrent = bottom;
        } else {
          bandY[i][label] = (top: yCurrent, bottom: yCurrent);
        }
      }
    }

    // One continuous filled ribbon per party, spanning the whole chart width
    // — the smooth curve itself is the column, not a flow between columns.
    for (final label in order) {
      final hasSeats = bandY.any(
        (y) => (y[label]?.bottom ?? 0) > (y[label]?.top ?? 0),
      );
      if (!hasSeats) continue;

      final paint =
          Paint()
            ..color = controlSegmentColor(label)
            ..style = PaintingStyle.fill;
      final path = Path();

      if (count == 1) {
        final band = bandY[0][label]!;
        path
          ..moveTo(0, band.top)
          ..lineTo(rightEdgeX, band.top)
          ..lineTo(rightEdgeX, band.bottom)
          ..lineTo(0, band.bottom)
          ..close();
        canvas.drawPath(path, paint);
        continue;
      }

      final tops = [for (var i = 0; i < count; i++) bandY[i][label]!.top];
      final bottoms = [
        for (var i = 0; i < count; i++) bandY[i][label]!.bottom,
      ];

      path
        ..moveTo(0, tops[0])
        ..lineTo(nodeX(0), tops[0]);
      for (var i = 0; i < count - 1; i++) {
        final midX = (nodeX(i) + nodeX(i + 1)) / 2;
        path.cubicTo(
          midX,
          tops[i],
          midX,
          tops[i + 1],
          nodeX(i + 1),
          tops[i + 1],
        );
      }
      path
        ..lineTo(rightEdgeX, tops[count - 1])
        ..lineTo(rightEdgeX, bottoms[count - 1])
        ..lineTo(nodeX(count - 1), bottoms[count - 1]);
      for (var i = count - 1; i > 0; i--) {
        final midX = (nodeX(i) + nodeX(i - 1)) / 2;
        path.cubicTo(
          midX,
          bottoms[i],
          midX,
          bottoms[i - 1],
          nodeX(i - 1),
          bottoms[i - 1],
        );
      }
      path
        ..lineTo(0, bottoms[0])
        ..close();

      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant ControlHistoryRibbonPainter oldDelegate) {
    return !listEquals(oldDelegate.years, years) ||
        !listEquals(oldDelegate.order, order) ||
        oldDelegate.maxTotal != maxTotal ||
        oldDelegate.columnWidth != columnWidth ||
        oldDelegate.columnGap != columnGap;
  }
}
