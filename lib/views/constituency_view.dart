import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

import '../models/boundary.dart';
import '../models/election_result.dart';
import '../models/member.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/map_tiles.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/constituency_viewmodel.dart';
import '../widgets/control_split_bar.dart';
import 'member_view.dart';

/// Detail page for a Westminster constituency: the sitting MP, a boundary map,
/// and the latest general-election result with the full vote split.
class ConstituencyView extends StatefulWidget {
  final String constituencyName;
  final Member? member;
  final List<BoundaryPolygon> boundaries;

  const ConstituencyView({
    super.key,
    required this.constituencyName,
    this.member,
    this.boundaries = const [],
  });

  @override
  State<ConstituencyView> createState() => _ConstituencyViewState();
}

class _ConstituencyViewState extends State<ConstituencyView> {
  late final ConstituencyViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = ConstituencyViewModel(
      context.read<ParliamentaryDataService>(),
      constituencyName: widget.constituencyName,
      member: widget.member,
    );
    unawaited(_vm.load());
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  /// Header colour: the winning party once loaded, else the sitting MP's party,
  /// else a neutral grey.
  Color _headerColor(ConstituencyViewModel vm) {
    final winner = vm.result?.candidates.firstOrNull;
    if (winner != null) return party_util.partyColor(winner.party);
    final member = vm.member;
    if (member != null) {
      return party_util.partyColor(
        member.partyAbbreviation.isNotEmpty
            ? member.partyAbbreviation
            : member.party,
      );
    }
    return party_util.noControlColor;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<ConstituencyViewModel>(
        builder: (context, vm, _) {
          final color = _headerColor(vm);
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
                    titlePadding: const EdgeInsetsDirectional.only(
                        start: 56, bottom: 14, end: 16),
                    title: Text(
                      widget.constituencyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: fg, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                if (widget.member != null)
                  SliverToBoxAdapter(child: _memberHeader(context, color)),
                if (widget.boundaries.isNotEmpty)
                  SliverToBoxAdapter(child: _map(context, color)),
                if (vm.isLoading)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                else if (vm.result != null)
                  SliverToBoxAdapter(child: _result(context, vm.result!))
                else
                  SliverToBoxAdapter(child: _empty(context, vm)),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ─── Sitting MP ─────────────────────────────────────────────────────────

  Widget _memberHeader(BuildContext context, Color color) {
    final member = widget.member!;
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MemberView(member: member)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Row(
          children: [
            Icon(Icons.person_outline,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.name,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (member.party.isNotEmpty)
                    Text(
                      'MP · ${member.party}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: color, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ─── Boundary map ─────────────────────────────────────────────────────────

  Widget _map(BuildContext context, Color color) {
    final points = [for (final b in widget.boundaries) ...b.outer];
    if (points.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          height: 200,
          child: FlutterMap(
            options: MapOptions(
              initialCameraFit: CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(24),
              ),
              interactionOptions:
                  const InteractionOptions(flags: InteractiveFlag.none),
            ),
            children: [
              buildCartoLightTileLayer(context),
              PolygonLayer(
                simplificationTolerance: 0.5,
                polygons: [
                  for (final b in widget.boundaries)
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

  // ─── Latest result ──────────────────────────────────────────────────────

  Widget _result(BuildContext context, ConstituencyElectionResult result) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.electionTitle.isNotEmpty
                ? result.electionTitle
                : 'Latest result',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (result.result.isNotEmpty) ...[
            const SizedBox(height: 8),
            _resultBadge(theme, result),
          ],
          const SizedBox(height: 14),
          if (result.candidates.isNotEmpty) ...[
            ControlSplitBar(
              segments: [
                for (final c in result.candidates)
                  (label: c.party, value: c.votes),
              ],
            ),
            const SizedBox(height: 12),
          ],
          _stats(theme, result),
          const SizedBox(height: 12),
          ...result.candidates.map((c) => _candidateRow(theme, c)),
          const SizedBox(height: 8),
          Text(
            'Source: UK Parliament Members API',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _resultBadge(ThemeData theme, ConstituencyElectionResult result) {
    final winner = result.candidates.firstOrNull;
    final color = winner != null
        ? party_util.partyColor(winner.party)
        : party_util.noControlColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        result.result,
        style: theme.textTheme.titleSmall
            ?.copyWith(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _stats(ThemeData theme, ConstituencyElectionResult result) {
    final style = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final turnoutPct = result.electorate > 0
        ? (result.turnout / result.electorate * 100).toStringAsFixed(1)
        : null;
    return Wrap(
      spacing: 16,
      runSpacing: 4,
      children: [
        if (result.majority > 0)
          Text('Majority ${_formatInt(result.majority)}', style: style),
        if (result.turnout > 0)
          Text(
            'Turnout ${_formatInt(result.turnout)}'
            '${turnoutPct != null ? ' ($turnoutPct%)' : ''}',
            style: style,
          ),
        if (result.electorate > 0)
          Text('Electorate ${_formatInt(result.electorate)}', style: style),
      ],
    );
  }

  Widget _candidateRow(ThemeData theme, ElectionCandidate c) {
    final color = party_util.partyColor(c.party);
    // The winner is the sitting MP, so their row links through to the member
    // profile (when we know which member that is). Losing candidates aren't
    // current members and have no profile to open.
    final member = widget.member;
    final tappable = c.isWinner && member != null;

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                Text(
                  c.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: c.isWinner ? FontWeight.w700 : FontWeight.normal,
                  ),
                ),
                if (c.party.isNotEmpty)
                  Text(
                    c.party,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatInt(c.votes),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              Text(
                '${c.voteShare.toStringAsFixed(1)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (tappable) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ],
      ),
    );

    if (!tappable) return row;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => MemberView(member: member)),
      ),
      child: row,
    );
  }

  Widget _empty(BuildContext context, ConstituencyViewModel vm) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Text(
          vm.error ?? 'No election result available for this constituency.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  /// Formats an integer with thousands separators (e.g. 24120 → "24,120").
  static String _formatInt(int value) {
    final digits = value.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }
}
