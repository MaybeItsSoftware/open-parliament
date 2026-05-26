import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/parliamentary_data_service.dart';
import '../utils/house_colors.dart';
import '../viewmodels/bills_list_viewmodel.dart';
import 'app_drawer.dart';
import 'bill_view.dart';
import 'date_selector_view.dart';

/// Main view listing the most recently updated bills before Parliament.
class BillsListView extends StatefulWidget {
  const BillsListView({super.key});

  @override
  State<BillsListView> createState() => _BillsListViewState();
}

class _BillsListViewState extends State<BillsListView> {
  late BillsListViewModel _vm;
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _vm = BillsListViewModel(context.read<ParliamentaryDataService>());
    _scrollController.addListener(_onScroll);
    unawaited(_vm.load());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      unawaited(_vm.loadMore());
    }
  }

  Color _houseColor(String house) => switch (house.toLowerCase()) {
        'lords' => HouseColors.lords,
        'commons' => HouseColors.commons,
        _ => HouseColors.mixed,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.article_outlined),
            SizedBox(width: 8),
            Text("Bills"),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text("Recent"),
                  ),
                ),
                ButtonSegment(
                  value: true,
                  label: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text("Coming Up"),
                  ),
                ),
              ],
              selected: {_vm.showComingUp},
              onSelectionChanged: (val) =>
                  setState(() => _vm.toggleComingUp(val.first)),
              showSelectedIcon: false,
              style: const ButtonStyle(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
      drawer: const AppDrawer(current: AppDestination.bills),
      body: ChangeNotifierProvider.value(
        value: _vm,
        child: Consumer<BillsListViewModel>(
          builder: (context, vm, _) {
            if (vm.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            if (vm.bills.isEmpty) {
              return _buildEmpty(context, vm);
            }
            return RefreshIndicator(
              onRefresh: vm.load,
              child: ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: vm.bills.length + (vm.hasMore ? 1 : 0),
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  if (i == vm.bills.length) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return _buildTile(context, vm, vm.bills[i]);
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTile(BuildContext context, BillsListViewModel vm, BillListItem bill) {
    final theme = Theme.of(context);
    final hColor = _houseColor(bill.house);
    final subtitle = [
      if (bill.house.isNotEmpty) bill.house,
      if (bill.nextSitting != null)
        "Next: ${_formatDate(bill.nextSitting!)}"
      else if (bill.stageDescription?.isNotEmpty == true)
        bill.stageDescription!,
    ].join(" · ");

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: hColor.withValues(alpha: 0.15),
        child: Icon(Icons.article, color: hColor, size: 20),
      ),
      title: Text(
        bill.title,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle.isNotEmpty ? Text(subtitle) : null,
      trailing: (vm.showComingUp ? bill.nextSitting : bill.lastUpdate) != null
          ? Text(
              _formatDate(vm.showComingUp ? bill.nextSitting! : bill.lastUpdate!),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : null,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BillView(billTitle: bill.title, billId: bill.id),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context, BillsListViewModel vm) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.article_outlined, size: 48),
            const SizedBox(height: 12),
            Text(vm.error ?? 'No recent bills found.'),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => unawaited(vm.load()),
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
    return '${date.day} ${months[date.month - 1]}';
  }
}
