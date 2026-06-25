import 'package:flutter/material.dart';

import '../utils/party_colors.dart' as party_util;

/// One labelled, weighted segment of a [ControlSplitBar].
typedef ControlSegment = ({String label, int value});

/// Brand colour for a split segment: the party's colour, or the neutral
/// no-control grey for the "Vacant" bucket. Shared by the bar and any other
/// party-coloured visualisation (e.g. the council control-history chart).
Color controlSegmentColor(String label) =>
    label.toLowerCase() == 'vacant'
        ? party_util.noControlColor
        : party_util.partyColor(label);

/// A horizontal stacked bar showing a split by party — council seats, a
/// council's historical composition, or a constituency's vote share.
///
/// Each segment's width is proportional to its value; colours come from
/// [party_util.partyColor], with the "Vacant" bucket rendered in the neutral
/// no-control grey. Pure presentation — callers supply the ordered segments.
class ControlSplitBar extends StatelessWidget {
  final List<ControlSegment> segments;
  final double height;
  final double radius;

  const ControlSplitBar({
    super.key,
    required this.segments,
    this.height = 16,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    final visible = segments.where((s) => s.value > 0).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final s in visible)
              Expanded(
                flex: s.value,
                child: ColoredBox(color: controlSegmentColor(s.label)),
              ),
          ],
        ),
      ),
    );
  }
}
