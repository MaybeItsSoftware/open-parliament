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
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _vm = HouseSeatingViewModel(context.read<ParliamentaryDataService>());
    unawaited(_vm.load(HouseType.commons));
  }

  @override
  void dispose() {
    _vm.dispose();
    _scrollController.dispose();
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
          SizedBox(
            height: 350,
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: SizedBox(
                      width: 1200,
                      child: _SeatMap(
                        seats: vm.seats,
                        house: vm.house,
                        onSeatTap: (seat) => _showSeatDetails(context, seat.member),
                      ),
                    ),
                  ),
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
  final HouseType house;
  final ValueChanged<SeatingSeat> onSeatTap;

  const _SeatMap({
    required this.seats,
    required this.house,
    required this.onSeatTap,
  });

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
              house: widget.house,
              dotRadius: radius,
              selectedId: _selectedId,
              colorScheme: Theme.of(context).colorScheme,
            ),
          ),
        );
      },
    );
  }

  double _dotRadius(Size size, int seatCount) {
    if (seatCount == 0) return 0;
    // We adjust the dot size calculation slightly to fit the dense grid lines.
    final base = size.shortestSide / (math.sqrt(seatCount) * 2.8);
    return base.clamp(2.0, 5.5);
  }

  SeatingSeat? _hitTest(Offset tap, Size size, double radius) {
    SeatingSeat? closest;
    var closestDistance = double.infinity;
    // Keep target threshold reasonably sized for tap target accuracy on mobile.
    final threshold = radius * 2.2;
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
  final HouseType house;
  final double dotRadius;
  final int? selectedId;
  final ColorScheme colorScheme;

  _SeatMapPainter({
    required this.seats,
    required this.house,
    required this.dotRadius,
    required this.selectedId,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Draw Carpet/Aisle
    final carpetPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = house == HouseType.commons
          ? const Color(0x0C006548)
          : const Color(0x0CB50938);

    // Main floor carpet
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0.12 * w, 0.40 * h, 0.96 * w, 0.60 * h),
        const Radius.circular(4),
      ),
      carpetPaint,
    );

    // Gangway carpet
    if (house == HouseType.commons) {
      canvas.drawRect(
        Rect.fromLTRB(0.52 * w, 0.04 * h, 0.58 * w, 0.96 * h),
        carpetPaint,
      );
    } else {
      canvas.drawRect(
        Rect.fromLTRB(0.46 * w, 0.04 * h, 0.52 * w, 0.96 * h),
        carpetPaint,
      );
    }

    // 2. Draw Bench Lines
    final benchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dotRadius * 2.2
      ..strokeCap = StrokeCap.round
      ..color = house == HouseType.commons
          ? const Color(0x1F006548)
          : const Color(0x1FB50938);

    // Government side (top)
    for (final y in [0.08, 0.15, 0.22, 0.29, 0.36]) {
      final leftStart = Offset(0.16 * w, y * h);
      final leftEnd = Offset((house == HouseType.commons ? 0.52 : 0.46) * w, y * h);
      canvas.drawLine(leftStart, leftEnd, benchPaint);

      final rightStart = Offset((house == HouseType.commons ? 0.58 : 0.52) * w, y * h);
      final rightEnd = Offset((house == HouseType.commons ? 0.94 : 0.80) * w, y * h);
      canvas.drawLine(rightStart, rightEnd, benchPaint);
    }

    // Opposition side (bottom)
    for (final y in [0.64, 0.71, 0.78, 0.85, 0.92]) {
      final leftStart = Offset(0.16 * w, y * h);
      final leftEnd = Offset((house == HouseType.commons ? 0.52 : 0.46) * w, y * h);
      canvas.drawLine(leftStart, leftEnd, benchPaint);

      final rightStart = Offset((house == HouseType.commons ? 0.58 : 0.52) * w, y * h);
      final rightEnd = Offset((house == HouseType.commons ? 0.94 : 0.80) * w, y * h);
      canvas.drawLine(rightStart, rightEnd, benchPaint);
    }

    // Crossbenches (Lords only)
    if (house == HouseType.lords) {
      for (final x in [0.82, 0.85, 0.88, 0.91, 0.94]) {
        canvas.drawLine(Offset(x * w, 0.20 * h), Offset(x * w, 0.80 * h), benchPaint);
      }
    }

    // 3. Draw Speaker's Chair / Throne
    const woodColor = Color(0xFF8D6E63);
    const goldColor = Color(0xFFFFB300);
    const crimsonColor = Color(0xFFC62828);

    if (house == HouseType.commons) {
      // Speaker's Chair canopy / outline
      final chairPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = woodColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0.03 * w, 0.42 * h, 0.09 * w, 0.58 * h),
          const Radius.circular(4),
        ),
        chairPaint,
      );
      // Chair seat cushion (green)
      final cushionPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF006548);
      canvas.drawRect(
        Rect.fromLTRB(0.045 * w, 0.45 * h, 0.075 * w, 0.55 * h),
        cushionPaint,
      );
    } else {
      // Lords Throne (gold and crimson)
      final thronePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = goldColor;
      canvas.drawRect(
        Rect.fromLTRB(0.03 * w, 0.42 * h, 0.08 * w, 0.58 * h),
        thronePaint,
      );
      final throneFill = Paint()
        ..style = PaintingStyle.fill
        ..color = crimsonColor.withValues(alpha: 0.4);
      canvas.drawRect(
        Rect.fromLTRB(0.04 * w, 0.44 * h, 0.07 * w, 0.56 * h),
        throneFill,
      );
      
      // Woolsack (red cushion in the center)
      final woolsackPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = crimsonColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0.10 * w, 0.47 * h, 0.13 * w, 0.53 * h),
          const Radius.circular(3),
        ),
        woolsackPaint,
      );
    }

    // 4. Draw Clerk's Table
    final tablePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = woodColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0.15 * w, 0.45 * h, 0.24 * w, 0.55 * h),
        const Radius.circular(2),
      ),
      tablePaint,
    );
    // The Mace
    final macePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = goldColor;
    canvas.drawLine(
      Offset(0.17 * w, 0.50 * h),
      Offset(0.22 * w, 0.50 * h),
      macePaint,
    );

    // 5. Draw Seats/Dots
    final paint = Paint()..style = PaintingStyle.fill;
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = colorScheme.onSurface;

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
        oldDelegate.house != house ||
        oldDelegate.dotRadius != dotRadius ||
        oldDelegate.selectedId != selectedId;
  }
}
