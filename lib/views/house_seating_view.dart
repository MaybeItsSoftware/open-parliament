import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/house_seating_viewmodel.dart';
import 'app_drawer.dart';
import 'member_view.dart';

class HouseSeatingView extends StatefulWidget {
  const HouseSeatingView({super.key});

  @override
  State<HouseSeatingView> createState() => _HouseSeatingViewState();
}

class _HouseSeatingViewState extends State<HouseSeatingView> {
  late HouseSeatingViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = HouseSeatingViewModel(context.read<ParliamentaryDataService>());
    unawaited(_vm.load(HouseType.commons));
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<HouseSeatingViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('House Seating'),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SegmentedButton<HouseType>(
                    segments: const [
                      ButtonSegment(
                        value: HouseType.commons,
                        label: Text('Commons'),
                        icon: Icon(Icons.how_to_vote_outlined),
                      ),
                      ButtonSegment(
                        value: HouseType.lords,
                        label: Text('Lords'),
                        icon: Icon(Icons.local_library_outlined),
                      ),
                    ],
                    selected: {vm.house},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      unawaited(_vm.load(selection.first));
                    },
                  ),
                ),
              ),
            ),
            drawer: const AppDrawer(current: AppDestination.seating),
            body: vm.isLoading && vm.seats.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : vm.error != null
                    ? _buildError(context, vm.error!)
                    : _buildContent(context, vm),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, HouseSeatingViewModel vm) {
    return RefreshIndicator(
      onRefresh: vm.refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSummary(context, vm),
          const SizedBox(height: 16),
          AspectRatio(
            aspectRatio: 1.4,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _SeatMap(
                  seats: vm.seats,
                  onSeatTap: (seat) => _showSeatDetails(context, seat.member),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Party Breakdown',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in vm.breakdown)
                _BreakdownChip(
                  label: item.label,
                  count: item.count,
                  color: item.color,
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildSummary(BuildContext context, HouseSeatingViewModel vm) {
    final houseLabel = vm.house == HouseType.commons ? 'House of Commons' : 'House of Lords';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          houseLabel,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          '${vm.totalMembers} members • grouped by party',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tap a dot to see who they represent.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 32),
            const SizedBox(height: 12),
            Text(
              'Unable to load seating data.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSeatDetails(BuildContext context, Member member) {
    final represents =
        member.constituency.isNotEmpty ? member.constituency : 'House of Lords';
    final partyLabel = member.party.isNotEmpty
        ? member.party
        : member.partyAbbreviation.isNotEmpty
            ? member.partyAbbreviation
            : 'Independent';

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (partyLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    partyLabel,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant,
                        ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  'Represents',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                Text(
                  represents,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MemberView(member: member),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_outline),
                    label: const Text('View profile'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BreakdownChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _BreakdownChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color.withValues(alpha: 0.14);
    final fg = party_util.foregroundForParty(bg);
    return Chip(
      backgroundColor: bg,
      label: Text(
        '$label $count',
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
      side: BorderSide(color: color.withValues(alpha: 0.2)),
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 6,
      ),
    );
  }
}

class _SeatMap extends StatefulWidget {
  final List<SeatingSeat> seats;
  final ValueChanged<SeatingSeat> onSeatTap;

  const _SeatMap({required this.seats, required this.onSeatTap});

  @override
  State<_SeatMap> createState() => _SeatMapState();
}

class _SeatMapState extends State<_SeatMap> {
  int? _selectedId;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final radius = _dotRadius(size, widget.seats.length);
        return GestureDetector(
          onTapUp: (details) {
            final hit = _hitTest(details.localPosition, size, radius);
            if (hit == null) return;
            setState(() => _selectedId = hit.member.id);
            widget.onSeatTap(hit);
          },
          child: CustomPaint(
            size: size,
            painter: _SeatMapPainter(
              seats: widget.seats,
              dotRadius: radius,
              selectedId: _selectedId,
            ),
          ),
        );
      },
    );
  }

  double _dotRadius(Size size, int seatCount) {
    if (seatCount == 0) return 0;
    final base = size.shortestSide / (math.sqrt(seatCount) * 3.2);
    return base.clamp(2.0, 6.0);
  }

  SeatingSeat? _hitTest(Offset tap, Size size, double radius) {
    SeatingSeat? closest;
    var closestDistance = double.infinity;
    final threshold = radius * 1.7;
    for (final seat in widget.seats) {
      final pos = Offset(
        seat.position.dx * size.width,
        seat.position.dy * size.height,
      );
      final distance = (tap - pos).distance;
      if (distance <= threshold && distance < closestDistance) {
        closest = seat;
        closestDistance = distance;
      }
    }
    return closest;
  }
}

class _SeatMapPainter extends CustomPainter {
  final List<SeatingSeat> seats;
  final double dotRadius;
  final int? selectedId;

  _SeatMapPainter({
    required this.seats,
    required this.dotRadius,
    required this.selectedId,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.black.withValues(alpha: 0.65);

    for (final seat in seats) {
      final pos = Offset(
        seat.position.dx * size.width,
        seat.position.dy * size.height,
      );
      paint.color = seat.color;
      canvas.drawCircle(pos, dotRadius, paint);
      if (selectedId == seat.member.id) {
        canvas.drawCircle(pos, dotRadius + 1.5, highlightPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SeatMapPainter oldDelegate) {
    return oldDelegate.seats != seats ||
        oldDelegate.dotRadius != dotRadius ||
        oldDelegate.selectedId != selectedId;
  }
}
