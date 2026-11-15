import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/member.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/house_seating_viewmodel.dart';
import 'member_view.dart';

/// Chamber seating view for the House of Commons and House of Lords.
///
/// Features:
/// - Responsive, zoomable chamber layout powered by [InteractiveViewer].
/// - Interactive MP search with live seat highlight and glow.
/// - Chamber annotations (Speaker's Chair, Despatch Boxes, Red Carpet Lines, Treasury Benches, Opposition Benches).
class HouseSeatingView extends StatefulWidget {
  const HouseSeatingView({super.key});

  @override
  State<HouseSeatingView> createState() => _HouseSeatingViewState();
}

class _HouseSeatingViewState extends State<HouseSeatingView> {
  late HouseSeatingViewModel _vm;
  final TextEditingController _searchController = TextEditingController();
  final TransformationController _transformationController =
      TransformationController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _vm = HouseSeatingViewModel(context.read<ParliamentaryDataService>());
    unawaited(_vm.load(HouseType.commons));
  }

  @override
  void dispose() {
    _searchController.dispose();
    _transformationController.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _resetZoom() {
    _transformationController.value = Matrix4.identity();
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
              actions: [
                IconButton(
                  icon: const Icon(Icons.zoom_out_map),
                  tooltip: 'Reset view',
                  onPressed: _resetZoom,
                ),
              ],
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
                      _resetZoom();
                      unawaited(_vm.load(selection.first));
                    },
                  ),
                ),
              ),
            ),
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
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: vm.refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildHeader(context, vm),
          const SizedBox(height: 12),
          // Search box
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search MP or party (e.g. Starmer, Labour, Reform)...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (val) => setState(() => _searchQuery = val.trim()),
          ),
          const SizedBox(height: 14),
          // Chamber Map Viewer Container
          Card(
            elevation: 1,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Container(
              color: theme.colorScheme.surfaceContainerLowest,
              child: Column(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    color: theme.colorScheme.surfaceContainerLow,
                    child: Row(
                      children: [
                        Icon(
                          Icons.touch_app_outlined,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Pinch or scroll to zoom • Tap seat for MP details',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        if (_searchQuery.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'Search active',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  AspectRatio(
                    aspectRatio: 1.65,
                    child: InteractiveViewer(
                      transformationController: _transformationController,
                      minScale: 1.0,
                      maxScale: 4.5,
                      boundaryMargin: const EdgeInsets.all(40),
                      child: _SeatMap(
                        seats: vm.seats,
                        house: vm.house,
                        searchQuery: _searchQuery,
                        onSeatTap: (seat) =>
                            _showSeatDetails(context, seat.member),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Chamber Legend
          _buildChamberLegend(context, vm.house),
          const SizedBox(height: 20),
          Text(
            'Party Composition',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in vm.breakdown)
                _BreakdownChip(
                  label: item.label,
                  count: item.count,
                  color: item.color,
                  onTap: () {
                    _searchController.text = item.label;
                    setState(() => _searchQuery = item.label.toLowerCase());
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, HouseSeatingViewModel vm) {
    final houseLabel = vm.house == HouseType.commons
        ? 'House of Commons Chamber'
        : 'House of Lords Chamber';
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
        const SizedBox(height: 4),
        Text(
          '${vm.totalMembers} members • Government & Opposition facing benches',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }

  Widget _buildChamberLegend(BuildContext context, HouseType house) {
    final theme = Theme.of(context);
    final isCommons = house == HouseType.commons;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _legendItem(
          theme,
          isCommons ? 'Speaker\'s Chair' : 'Throne & Woolsack',
          const Color(0xFF8D6E63),
        ),
        _legendItem(theme, 'Government (Top)', party_util.partyColor('labour')),
        _legendItem(
            theme, 'Opposition (Bottom)', party_util.partyColor('conservative')),
        if (!isCommons)
          _legendItem(theme, 'Crossbenches (Right)',
              party_util.partyColor('crossbench')),
      ],
    );
  }

  Widget _legendItem(ThemeData theme, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
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
    final partyColor = party_util.partyColor(partyLabel);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: partyColor.withValues(alpha: 0.2),
                      foregroundImage: member.thumbnailUrl != null
                          ? NetworkImage(member.thumbnailUrl!)
                          : null,
                      child: Text(
                        member.name.characters.first,
                        style: TextStyle(
                            color: partyColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            member.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: partyColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                partyLabel,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .surfaceContainerLow,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Constituency / Position',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        represents,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MemberView(member: member),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: const Text('View Member Profile'),
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
  final VoidCallback onTap;

  const _BreakdownChip({
    required this.label,
    required this.count,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = color.withValues(alpha: 0.14);
    final fg = party_util.foregroundForParty(bg);
    return ActionChip(
      backgroundColor: bg,
      label: Text(
        '$label $count',
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 6,
      ),
      onPressed: onTap,
    );
  }
}

class _SeatMap extends StatefulWidget {
  final List<SeatingSeat> seats;
  final HouseType house;
  final String searchQuery;
  final ValueChanged<SeatingSeat> onSeatTap;

  const _SeatMap({
    required this.seats,
    required this.house,
    required this.searchQuery,
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
              searchQuery: widget.searchQuery,
              colorScheme: Theme.of(context).colorScheme,
            ),
          ),
        );
      },
    );
  }

  double _dotRadius(Size size, int seatCount) {
    if (seatCount == 0) return 0;
    final base = size.shortestSide / (math.sqrt(seatCount) * 2.2);
    return base.clamp(3.5, 7.5);
  }

  SeatingSeat? _hitTest(Offset tap, Size size, double radius) {
    SeatingSeat? closest;
    var closestDistance = double.infinity;
    final threshold = radius * 2.5;
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
  final String searchQuery;
  final ColorScheme colorScheme;

  _SeatMapPainter({
    required this.seats,
    required this.house,
    required this.dotRadius,
    required this.selectedId,
    required this.searchQuery,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 1. Draw Carpet & Red Sword Lines
    final isCommons = house == HouseType.commons;
    final houseColor = isCommons ? const Color(0xFF006548) : const Color(0xFFB50938);
    final carpetPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = houseColor.withValues(alpha: 0.08);

    // Central aisle floor carpet
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0.18 * w, 0.40 * h, 0.95 * w, 0.60 * h),
        const Radius.circular(4),
      ),
      carpetPaint,
    );

    // Two Red Carpet Lines (the traditional two sword-lengths rule!)
    final redLinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFD32F2F).withValues(alpha: 0.5);

    final lineXStart = 0.22 * w;
    final lineXEnd = (isCommons ? 0.92 : 0.80) * w;
    canvas.drawLine(Offset(lineXStart, 0.41 * h), Offset(lineXEnd, 0.41 * h), redLinePaint);
    canvas.drawLine(Offset(lineXStart, 0.59 * h), Offset(lineXEnd, 0.59 * h), redLinePaint);

    // Gangway carpet gap
    final gangwayX = (isCommons ? 0.57 : 0.51) * w;
    final gangwayPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = houseColor.withValues(alpha: 0.05);
    canvas.drawRect(
      Rect.fromLTRB(gangwayX - 12, 0.05 * h, gangwayX + 12, 0.95 * h),
      gangwayPaint,
    );

    // 2. Bench Lines
    final benchPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = dotRadius * 2.2
      ..strokeCap = StrokeCap.round
      ..color = houseColor.withValues(alpha: 0.15);

    // Government benches (top)
    for (final y in [0.38, 0.31, 0.24, 0.17, 0.10]) {
      final leftStart = Offset(0.22 * w, y * h);
      final leftEnd = Offset((isCommons ? 0.54 : 0.48) * w, y * h);
      canvas.drawLine(leftStart, leftEnd, benchPaint);

      final rightStart = Offset((isCommons ? 0.60 : 0.54) * w, y * h);
      final rightEnd = Offset((isCommons ? 0.92 : 0.80) * w, y * h);
      canvas.drawLine(rightStart, rightEnd, benchPaint);
    }

    // Opposition benches (bottom)
    for (final y in [0.62, 0.69, 0.76, 0.83, 0.90]) {
      final leftStart = Offset(0.22 * w, y * h);
      final leftEnd = Offset((isCommons ? 0.54 : 0.48) * w, y * h);
      canvas.drawLine(leftStart, leftEnd, benchPaint);

      final rightStart = Offset((isCommons ? 0.60 : 0.54) * w, y * h);
      final rightEnd = Offset((isCommons ? 0.92 : 0.80) * w, y * h);
      canvas.drawLine(rightStart, rightEnd, benchPaint);
    }

    // Crossbenches (Lords)
    if (!isCommons) {
      for (final x in [0.83, 0.86, 0.89, 0.92]) {
        canvas.drawLine(
            Offset(x * w, 0.22 * h), Offset(x * w, 0.78 * h), benchPaint);
      }
    }

    // 3. Speaker's Chair / Woolsack & Despatch Boxes
    const woodColor = Color(0xFF8D6E63);
    const goldColor = Color(0xFFFFB300);

    if (isCommons) {
      // Speaker's Canopy Chair
      final chairPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = woodColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0.04 * w, 0.42 * h, 0.11 * w, 0.58 * h),
          const Radius.circular(6),
        ),
        chairPaint,
      );
      final cushionPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFF006548);
      canvas.drawRect(
        Rect.fromLTRB(0.055 * w, 0.44 * h, 0.095 * w, 0.56 * h),
        cushionPaint,
      );
    } else {
      // Woolsack
      final woolsackPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = const Color(0xFFC62828);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(0.05 * w, 0.44 * h, 0.12 * w, 0.56 * h),
          const Radius.circular(4),
        ),
        woolsackPaint,
      );
    }

    // Clerk's Table
    final tablePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = woodColor;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(0.14 * w, 0.44 * h, 0.22 * w, 0.56 * h),
        const Radius.circular(2),
      ),
      tablePaint,
    );

    // Despatch Boxes (standing on the Table)
    final despatchPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFF5D4037);
    canvas.drawRect(
      Rect.fromLTRB(0.18 * w, 0.445 * h, 0.20 * w, 0.47 * h),
      despatchPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(0.18 * w, 0.53 * h, 0.20 * w, 0.555 * h),
      despatchPaint,
    );

    // Mace
    final macePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = goldColor;
    canvas.drawLine(
      Offset(0.15 * w, 0.50 * h),
      Offset(0.21 * w, 0.50 * h),
      macePaint,
    );

    // 4. Draw Seat Dots
    final paint = Paint()..style = PaintingStyle.fill;
    final highlightPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = colorScheme.onSurface;

    final query = searchQuery.toLowerCase();

    for (final seat in seats) {
      final pos = Offset(
        seat.position.dx * size.width,
        seat.position.dy * size.height,
      );

      final matchesQuery = query.isEmpty ||
          seat.member.name.toLowerCase().contains(query) ||
          seat.member.party.toLowerCase().contains(query) ||
          seat.member.constituency.toLowerCase().contains(query);

      final alpha = matchesQuery ? 1.0 : 0.2;
      paint.color = seat.color.withValues(alpha: alpha);

      canvas.drawCircle(pos, dotRadius, paint);

      if (selectedId == seat.member.id || (query.isNotEmpty && matchesQuery)) {
        final ringPaint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..color = query.isNotEmpty && matchesQuery
              ? colorScheme.primary
              : highlightPaint.color;
        canvas.drawCircle(pos, dotRadius + 2.0, ringPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SeatMapPainter oldDelegate) {
    return oldDelegate.seats != seats ||
        oldDelegate.house != house ||
        oldDelegate.dotRadius != dotRadius ||
        oldDelegate.selectedId != selectedId ||
        oldDelegate.searchQuery != searchQuery;
  }
}
