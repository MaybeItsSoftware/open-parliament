import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/standing_order.dart';
import '../utils/house_colors.dart';
import '../utils/standing_order_helpers.dart';
import '../utils/standing_orders_data.dart';

/// Full directory and search view for UK Parliamentary Standing Orders.
class StandingOrdersView extends StatefulWidget {
  final String? initialSelectedId;

  const StandingOrdersView({super.key, this.initialSelectedId});

  @override
  State<StandingOrdersView> createState() => _StandingOrdersViewState();
}

class _StandingOrdersViewState extends State<StandingOrdersView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedHouse = 'All'; // 'All', 'Commons', 'Lords'
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedId != null) {
      final initial = StandingOrdersData.allOrders.firstWhere(
        (o) => o.id == widget.initialSelectedId,
        orElse: () => StandingOrdersData.allOrders.first,
      );
      _selectedHouse = initial.house;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> get _categories {
    final set = <String>{'All'};
    for (final order in StandingOrdersData.allOrders) {
      if (_selectedHouse == 'All' || order.house == _selectedHouse) {
        set.add(order.category);
      }
    }
    return set.toList();
  }

  List<StandingOrder> get _filteredOrders {
    final query = _searchQuery.trim().toLowerCase();
    return StandingOrdersData.allOrders.where((order) {
      if (_selectedHouse != 'All' && order.house != _selectedHouse) {
        return false;
      }
      if (_selectedCategory != 'All' && order.category != _selectedCategory) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchesNum = order.number.toLowerCase().contains(query);
        final matchesTitle = order.title.toLowerCase().contains(query);
        final matchesSummary = order.summary.toLowerCase().contains(query);
        final matchesCat = order.category.toLowerCase().contains(query);
        return matchesNum || matchesTitle || matchesSummary || matchesCat;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orders = _filteredOrders;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Standing Orders'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search by number, rule, or topic (e.g. 24, closure)',
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
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // House & Category Filter Bar
          Container(
            color: theme.colorScheme.surfaceContainerLow,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      const Text('House: ',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'All', label: Text('All')),
                            ButtonSegment(
                              value: 'Commons',
                              label: Text('Commons'),
                              icon: Icon(Icons.shield_outlined, size: 14),
                            ),
                            ButtonSegment(
                              value: 'Lords',
                              label: Text('Lords'),
                              icon: Icon(Icons.account_balance_outlined,
                                  size: 14),
                            ),
                          ],
                          selected: {_selectedHouse},
                          onSelectionChanged: (set) {
                            setState(() {
                              _selectedHouse = set.first;
                              _selectedCategory = 'All';
                            });
                          },
                          showSelectedIcon: false,
                          style: SegmentedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final cat in _categories) ...[
                        FilterChip(
                          label: Text(cat),
                          selected: _selectedCategory == cat,
                          onSelected: (selected) {
                            setState(() {
                              _selectedCategory = selected ? cat : 'All';
                            });
                          },
                          visualDensity: VisualDensity.compact,
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Results Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Text(
                  '${orders.length} ${orders.length == 1 ? 'Standing Order' : 'Standing Orders'}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (_searchQuery.isNotEmpty ||
                    _selectedHouse != 'All' ||
                    _selectedCategory != 'All')
                  GestureDetector(
                    onTap: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                        _selectedHouse = 'All';
                        _selectedCategory = 'All';
                      });
                    },
                    child: Text(
                      'Reset filters',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          // List
          Expanded(
            child: orders.isEmpty
                ? _buildEmptyState(context)
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: orders.length,
                    itemBuilder: (context, index) {
                      final order = orders[index];
                      final isInitial = order.id == widget.initialSelectedId;
                      return _buildOrderCard(context, order,
                          highlight: isInitial);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_outlined, size: 48, color: muted),
            const SizedBox(height: 12),
            Text(
              'No Standing Orders match your filter.',
              style: TextStyle(color: muted, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Try adjusting your search query or topic filter.',
              style: TextStyle(color: muted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(
    BuildContext context,
    StandingOrder order, {
    bool highlight = false,
  }) {
    final theme = Theme.of(context);
    final houseColor = order.house == 'Commons'
        ? HouseColors.commons
        : HouseColors.lords;

    return Card(
      elevation: highlight ? 3 : 0.5,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: highlight
              ? theme.colorScheme.primary
              : theme.dividerColor.withValues(alpha: 0.5),
          width: highlight ? 2 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => StandingOrderHelpers.showStandingOrderSheet(context, order),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: houseColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: houseColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      'SO No. ${order.number}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: houseColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      order.house,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                order.title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                order.summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Chip(
                    label: Text(
                      order.category,
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                  ),
                  const Spacer(),
                  if (order.officialUrl != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => launchUrl(
                        Uri.parse(order.officialUrl!),
                        mode: LaunchMode.externalApplication,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('Erskine May',
                          style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
