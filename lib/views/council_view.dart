import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../models/boundary.dart';
import '../models/council.dart';
import '../models/councillor.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/area_match.dart';
import '../utils/council_control.dart';
import '../utils/map_tiles.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/council_history_viewmodel.dart';
import '../widgets/control_split_bar.dart';
import '../widgets/council_control_history_chart.dart';
import 'councillor_view.dart';

/// Ordered seat segments for a council's composition bar (parties largest
/// first, then any vacant seats).
List<ControlSegment> councilSegments(Council council) {
  final vacant = council.seats.entries
      .where((e) => e.key.toLowerCase() == 'vacant')
      .fold<int>(0, (sum, e) => sum + e.value);
  return [
    for (final e in council.heldSeats) (label: e.key, value: e.value),
    if (vacant > 0) (label: 'Vacant', value: vacant),
  ];
}

/// Profile page for a single local authority: its political control, a boundary
/// map, the seat composition, control history, and elected members.
class CouncilView extends StatefulWidget {
  final Council council;
  final List<BoundaryPolygon> boundaries;

  /// The council's elected members, resolved lazily; null when councillor data
  /// isn't wired up for this entry point.
  final Future<List<Councillor>>? councillors;

  const CouncilView({
    super.key,
    required this.council,
    this.boundaries = const [],
    this.councillors,
  });

  @override
  State<CouncilView> createState() => _CouncilViewState();
}

class _CouncilViewState extends State<CouncilView> {
  late final CouncilHistoryViewModel _history;

  Council get council => widget.council;
  List<BoundaryPolygon> get boundaries => widget.boundaries;
  Future<List<Councillor>>? get councillors => widget.councillors;

  @override
  void initState() {
    super.initState();
    _history = CouncilHistoryViewModel(
      context.read<ParliamentaryDataService>(),
      councilName: council.name,
    );
    unawaited(_history.load());
  }

  @override
  void dispose() {
    _history.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCity = isCityOfLondonCouncil(council.name);
    final color = party_util.controlColor(council.control);
    final fg = party_util.foregroundForParty(color);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: color,
            foregroundColor: fg,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsetsDirectional.only(start: 56, bottom: 14, end: 16),
              title: Text(
                council.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: fg, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _header(theme, color)),
          if (boundaries.isNotEmpty)
            SliverToBoxAdapter(child: _map(context, color)),
          SliverToBoxAdapter(child: _composition(context)),
          SliverToBoxAdapter(
            child: ChangeNotifierProvider.value(
              value: _history,
              child: const _ControlHistory(),
            ),
          ),
          if (councillors != null)
            SliverToBoxAdapter(
              child: _CouncillorList(
                councillors: councillors!,
                isCityOfLondon: isCity,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _header(ThemeData theme, Color color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.4)),
            ),
            child: Text(
              controlDisplayName(council.control),
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.account_balance_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                council.type.isNotEmpty ? council.type : 'Local authority',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(width: 16),
              Icon(Icons.event_seat_outlined,
                  size: 16, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                '${council.total} seats',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _map(BuildContext context, Color color) {
    final points = [
      for (final b in boundaries) ...b.outer,
    ];
    if (points.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 220,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(24),
              ),
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.all),
            ),
            children: [
              buildCartoLightTileLayer(context),
              PolygonLayer(
                polygonCulling: true,
                simplificationTolerance: 0.5,
                
                polygons: [
                  for (final b in boundaries)
                    Polygon(
                      points: b.outer,
                      holePointsList: b.holes.isNotEmpty ? b.holes : null,
                      color: color.withValues(alpha: 0.35),
                      borderColor: color,
                      borderStrokeWidth: 1.5,
                      disableHolesBorder: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composition(BuildContext context) {
    final theme = Theme.of(context);
    final held = council.heldSeats;
    final vacant = council.seats.entries
        .where((e) => e.key.toLowerCase() == 'vacant')
        .fold<int>(0, (sum, e) => sum + e.value);
    final majority = council.total ~/ 2 + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Composition',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (council.total > 0) ...[
            ControlSplitBar(segments: councilSegments(council)),
            const SizedBox(height: 6),
            Text(
              '$majority seats needed for a majority',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
          ],
          ...held.map((e) => _seatRow(theme, e.key, e.value)),
          if (vacant > 0) _seatRow(theme, 'Vacant', vacant),
        ],
      ),
    );
  }

  Widget _seatRow(ThemeData theme, String label, int seats) {
    final color = label.toLowerCase() == 'vacant'
        ? party_util.noControlColor
        : party_util.partyColor(label);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Text(
            '$seats',
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// The council's control over time: a stacked seats-per-year graph
/// ([CouncilControlHistoryChart]) plus the heading and "load earlier years"
/// control, driven by [CouncilHistoryViewModel]. Paged further back on demand.
class _ControlHistory extends StatelessWidget {
  const _ControlHistory();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final vm = context.watch<CouncilHistoryViewModel>();

    // While the first batch loads, stay quiet rather than flashing an empty
    // section; once loaded with nothing to show, omit the section entirely.
    if (vm.isLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(16, 28, 16, 0),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (vm.history.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Control history',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            'Council seats by party, tap a year for the breakdown',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          CouncilControlHistoryChart(history: vm.history),
          const SizedBox(height: 8),
          if (vm.isLoadingOlder)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (vm.canLoadOlder)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: vm.loadOlder,
                icon: const Icon(Icons.history, size: 18),
                label: const Text('Load earlier years'),
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Source: OpenCouncilData (CC BY-SA 4.0)',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The council's elected members grouped by ward, resolved from the national
/// councillor list. Shows a spinner while loading and stays quiet on failure or
/// when no councillors matched (the control/composition view still stands).
class _CouncillorList extends StatelessWidget {
  final Future<List<Councillor>> councillors;
  final bool isCityOfLondon;

  const _CouncillorList({
    required this.councillors,
    required this.isCityOfLondon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<Councillor>>(
      future: councillors,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final councillors = snapshot.data ?? const <Councillor>[];
        if (snapshot.hasError || councillors.isEmpty) {
          return const SizedBox.shrink();
        }

        final byWard = _groupByWard(
          councillors,
          isCityOfLondon: isCityOfLondon,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Councillors',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  Text('${councillors.length}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 12),
              if (isCityOfLondon) ...[
                _cityIntro(theme),
                const SizedBox(height: 12),
              ],
              for (final ward in byWard.entries)
                _ward(context, theme, ward.key, ward.value),
              const SizedBox(height: 4),
              Text(
                'Source: OpenCouncilData (CC BY-SA 4.0)',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (isCityOfLondon) ...[
                const SizedBox(height: 6),
                Text(
                  'City of London electorate includes residents and appointed '
                  'business voters.',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Wards alphabetically; councillors within a ward by name.
  Map<String, List<Councillor>> _groupByWard(
    List<Councillor> councillors, {
    required bool isCityOfLondon,
  }) {
    final map = <String, List<Councillor>>{};
    for (final c in councillors) {
      map.putIfAbsent(c.ward.isEmpty ? 'Unknown ward' : c.ward, () => []).add(c);
    }
    final sorted = map.keys.toList()..sort();
    return {
      for (final ward in sorted)
        ward: (map[ward]!..sort((a, b) {
          if (isCityOfLondon) {
            final rankA = _cityRoleRank(a.role);
            final rankB = _cityRoleRank(b.role);
            if (rankA != rankB) return rankA.compareTo(rankB);
          }
          return a.name.compareTo(b.name);
        })),
    };
  }

  Widget _ward(
      BuildContext context, ThemeData theme, String ward, List<Councillor> members) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ward,
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          ...members.map((c) => _councillor(context, theme, c)),
        ],
      ),
    );
  }

  Widget _councillor(BuildContext context, ThemeData theme, Councillor c) {
    final displayParty =
        c.party.isNotEmpty || !isCityOfLondonCouncil(c.council)
            ? c.party
            : 'Independent';
    final color = party_util.partyColor(displayParty);
    final meta = <String>[];
    if (c.role != CouncillorRole.councillor) meta.add(c.roleLabel);
    if (displayParty.isNotEmpty) meta.add(displayParty);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => CouncillorView(councillor: c)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.name, style: theme.textTheme.bodyMedium),
                  if (meta.isNotEmpty)
                    Text(
                      meta.join(' · '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  int _cityRoleRank(CouncillorRole role) {
    return switch (role) {
      CouncillorRole.alderman => 0,
      CouncillorRole.commonCouncillor => 1,
      CouncillorRole.councillor => 2,
    };
  }

  Widget _cityIntro(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'City of London wards elect one Alderman plus multiple Common '
        'Councillors. Aldermen sit on both the Court of Aldermen and the '
        'Court of Common Council.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
