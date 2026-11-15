import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/parliamentary_data_service.dart';
import '../utils/house_colors.dart';
import '../viewmodels/bills_timeline_viewmodel.dart';
import 'bill_view.dart';

/// Screen displaying UK Acts of Parliament (Royal Assent) on a date-proportional timeline.
class BillsTimelineView extends StatefulWidget {
  const BillsTimelineView({super.key});

  @override
  State<BillsTimelineView> createState() => _BillsTimelineViewState();
}

class _BillsTimelineViewState extends State<BillsTimelineView> {
  late BillsTimelineViewModel _vm;
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  bool _isSearchOpen = false;

  @override
  void initState() {
    super.initState();
    _vm = BillsTimelineViewModel(context.read<ParliamentaryDataService>());
    _scrollController.addListener(_onScroll);
    unawaited(_vm.load());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    _debounceTimer?.cancel();
    _vm.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    // Load older historical Acts when scrolling near the bottom of the list
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 300 &&
        !_vm.isLoadingMore &&
        _vm.hasMore) {
      unawaited(_vm.loadMore());
    }
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _vm.setSearchQuery(value);
    });
  }

  Color _houseColor(String house) => switch (house.toLowerCase()) {
        'lords' => HouseColors.lords,
        'commons' => HouseColors.commons,
        _ => HouseColors.mixed,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: _isSearchOpen
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: theme.colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: 'Search Acts of Parliament…',
                  hintStyle: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.7,
                    ),
                  ),
                  border: InputBorder.none,
                ),
                onChanged: _onSearchChanged,
              )
            : const Text('Acts of Parliament'),
        actions: [
          IconButton(
            icon: Icon(_isSearchOpen ? Icons.close : Icons.search),
            tooltip: _isSearchOpen ? 'Close search' : 'Search Acts',
            onPressed: () {
              setState(() {
                if (_isSearchOpen) {
                  _searchController.clear();
                  _vm.setSearchQuery('');
                  _isSearchOpen = false;
                } else {
                  _isSearchOpen = true;
                }
              });
            },
          ),
        ],
      ),
      body: ChangeNotifierProvider.value(
        value: _vm,
        child: Consumer<BillsTimelineViewModel>(
          builder: (context, vm, _) {
            return Column(
              children: [
                _buildFilterBar(context, vm, theme),
                Expanded(
                  child: vm.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : vm.bills.isEmpty
                          ? _buildEmpty(context, vm)
                          : RefreshIndicator(
                              onRefresh: vm.load,
                              child: _buildTimelineList(context, vm, theme),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    BillsTimelineViewModel vm,
    ThemeData theme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.surfaceContainerLow,
      child: Row(
        children: [
          Text(
            'Chamber:',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 10),
          for (final h in ['All', 'Commons', 'Lords']) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                label: Text(h),
                selected: vm.houseFilter == h,
                onSelected: (sel) {
                  if (sel) vm.setHouseFilter(h);
                },
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
          const Spacer(),
          Text(
            '${vm.bills.length} Acts',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the timeline list with date-proportional vertical spacing.
  Widget _buildTimelineList(
    BuildContext context,
    BillsTimelineViewModel vm,
    ThemeData theme,
  ) {
    final totalCount = vm.bills.length + (vm.hasMore ? 1 : 0);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: totalCount,
      itemBuilder: (context, i) {
        if (i == vm.bills.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Loading older Acts of Parliament…',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          );
        }

        final bill = vm.bills[i];
        final nextBill = (i + 1 < vm.bills.length) ? vm.bills[i + 1] : null;

        final bDate = bill.lastUpdate;
        final nDate = nextBill?.lastUpdate;
        final currentYear = bDate?.year;
        final nextYear = nDate?.year;
        final showYearDividerBelow =
            currentYear != null && nextYear != null && currentYear != nextYear;

        int? daysDiff;
        if (bDate != null && nDate != null) {
          daysDiff = bDate.difference(nDate).inDays.abs();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Year Divider header for the first item
            if (i == 0 && currentYear != null)
              _buildYearDivider(context, currentYear, theme),
            // Act Card on timeline
            _buildTimelineItem(context, bill, theme),
            // Date-proportional timeline gap
            if (daysDiff != null)
              _buildSpineGap(context, daysDiff, theme)
            else
              const SizedBox(height: 12),
            // Year Divider when moving into an older year
            if (showYearDividerBelow)
              _buildYearDivider(context, nextYear, theme),
          ],
        );
      },
    );
  }

  /// Calculates proportional vertical gap height (in pixels) based on elapsed days.
  double _calculateProportionalGap(int daysDiff) {
    if (daysDiff <= 0) return 8.0;
    final raw = 8.0 + (daysDiff * 0.2);
    return raw.clamp(8.0, 36.0);
  }

  Widget _buildSpineGap(BuildContext context, int daysDiff, ThemeData theme) {
    final gapHeight = _calculateProportionalGap(daysDiff);

    return SizedBox(
      height: gapHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 48,
            child: Center(
              child: Container(
                width: 3.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.amber.shade700,
                      Colors.amber.shade600,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearDivider(BuildContext context, int year, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.shade800,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.amber.shade900.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.history, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  '$year',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.amber.shade800,
                    theme.colorScheme.outlineVariant.withValues(alpha: 0.2),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(
    BuildContext context,
    BillTimelineItem bill,
    ThemeData theme,
  ) {
    final hColor = _houseColor(bill.house);
    final dateStr =
        bill.lastUpdate != null ? _formatDate(bill.lastUpdate!) : null;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline Spine Node
          SizedBox(
            width: 48,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                Positioned(
                  top: 0,
                  bottom: 0,
                  child: Container(
                    width: 3.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.amber.shade700,
                          Colors.amber.shade600,
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 14),
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: Colors.amber.shade800,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.amber.shade200, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.amber.shade900.withValues(alpha: 0.3),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.gavel, size: 13, color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Act Card
          Expanded(
            child: Card(
              elevation: 1.5,
              shadowColor: Colors.amber.shade900.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: Colors.amber.shade700.withValues(alpha: 0.3),
                  width: 1.0,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        BillView(billTitle: bill.title, billId: bill.id),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.amber.shade100,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Colors.amber.shade600,
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.verified,
                                  size: 13,
                                  color: Colors.amber.shade900,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'ROYAL ASSENT',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                    color: Colors.amber.shade900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          if (bill.house.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: hColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                bill.house.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: hColor,
                                ),
                              ),
                            ),
                          ],
                          const Spacer(),
                          if (dateStr != null)
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_today_outlined,
                                  size: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  dateStr,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        bill.title,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            'Act of Parliament',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Colors.amber.shade900,
                              fontWeight: FontWeight.w500,
                              fontSize: 11,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.arrow_forward_ios,
                            size: 12,
                            color: theme.colorScheme.outline,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, BillsTimelineViewModel vm) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.history_edu, size: 48),
            const SizedBox(height: 12),
            Text(
              vm.error ?? 'No Acts of Parliament found.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: vm.load,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}
