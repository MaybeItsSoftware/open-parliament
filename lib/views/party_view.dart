import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/party_stats.dart';
import '../services/party_service.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/party_viewmodel.dart';

class PartyView extends StatefulWidget {
  final String partyName;

  const PartyView({super.key, required this.partyName});

  @override
  State<PartyView> createState() => _PartyViewState();
}

class _PartyViewState extends State<PartyView> {
  late PartyViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = PartyViewModel(
      context.read<PartyService>(),
      partyName: widget.partyName,
    );
    _vm.load();
  }

  @override
  Widget build(BuildContext context) {
    final color = party_util.partyColor(widget.partyName);
    final fg = party_util.foregroundForParty(color);

    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<PartyViewModel>(
        builder: (context, vm, _) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: color,
              foregroundColor: fg,
              title: Text(widget.partyName),
              elevation: 0,
            ),
            body: vm.isLoadingCurrent
                ? const Center(child: CircularProgressIndicator())
                : vm.error != null
                    ? _buildError(vm)
                    : _buildContent(context, vm, color),
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, PartyViewModel vm, Color color) {
    final stats = vm.stats;
    if (stats == null) return const SizedBox.shrink();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Strength',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 16),
          _buildStatGrid(stats, color),
          const SizedBox(height: 32),
          Text(
            'Historical Trends',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Seat counts in Parliament and Local Government (May snapshots)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 24),
          if (vm.isLoadingHistorical)
            const Padding(
              padding: EdgeInsets.only(bottom: 16),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Loading historical data...'),
                  ],
                ),
              ),
            ),
          _buildTrendChart(context, stats.mpTrend, color),
          const SizedBox(height: 24),
          _buildTrendChart(context, stats.lordTrend, color),
          const SizedBox(height: 24),
          _buildTrendChart(context, stats.councilsControlledTrend, color),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildStatGrid(PartyStats stats, Color color) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard('MPs', stats.mpCount, color),
        _buildStatCard('Lords', stats.lordCount, color),
        _buildStatCard('Councillors', stats.councillorCount, color),
        _buildStatCard('Councils', stats.councilsControlled, color),
      ],
    );
  }

  Widget _buildStatCard(String label, int value, Color color) {
    return Card(
      elevation: 0,
      color: color.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              value.toString(),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withValues(alpha: 0.8),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendChart(
    BuildContext context,
    HistoricalTrend trend,
    Color color,
  ) {
    if (trend.points.isEmpty) return const SizedBox.shrink();

    final maxVal = trend.points.map((p) => p.value).fold(0, (a, b) => a > b ? a : b);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              trend.label,
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (trend.points.length >= 2)
              _buildChangeBadge(trend.totalChangePercent),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final point in trend.points)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          point.value.toString(),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          height: maxVal == 0 ? 0 : (point.value / maxVal) * 60,
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.7),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          point.year.toString(),
                          style: theme.textTheme.labelSmall?.copyWith(fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChangeBadge(double percent) {
    final isUp = percent > 0;
    final isDown = percent < 0;
    final color = isUp ? Colors.green : (isDown ? Colors.red : Colors.grey);
    final icon = isUp ? Icons.trending_up : (isDown ? Icons.trending_down : Icons.trending_flat);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            '${percent.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(PartyViewModel vm) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(vm.error ?? 'An error occurred'),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => vm.load(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}