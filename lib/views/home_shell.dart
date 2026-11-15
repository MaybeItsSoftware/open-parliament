import 'package:flutter/material.dart';

import 'bills_list_view.dart';
import 'bills_timeline_view.dart';
import 'constituency_map_view.dart';
import 'date_selector_view.dart';
import 'house_seating_view.dart';
import 'saved_speeches_view.dart';
import 'search_view.dart';
import 'settings_view.dart';
import 'standing_orders_view.dart';

/// The app's root: a bottom navigation bar over the four main sections, with
/// a "More" tab that lists the rest as pushed (back-button) screens.
///
/// Tabs are kept alive in an [IndexedStack] so switching away from, say, a
/// half-scrolled debates feed or a zoomed map doesn't lose its place. Each
/// tab is built only on first visit — the map in particular is expensive.
/// System back on any tab other than Debates returns to Debates rather than
/// closing the app.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  /// Tab to open on (0 Debates, 1 Search, 2 Bills, 3 Map). Used by the store
  /// screenshot generator; the app always starts on Debates.
  final int initialIndex;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static const int _debatesIndex = 0;
  static const int _moreIndex = 4;

  late int _index = widget.initialIndex.clamp(0, _moreIndex - 1);
  late final Set<int> _visited = {_index};

  static Widget _tabBody(int index) {
    switch (index) {
      case 1:
        return const SearchView();
      case 2:
        return const BillsListView();
      case 3:
        return const ConstituencyMapView();
      default:
        return const DateSelectorView();
    }
  }

  void _onDestinationSelected(int index) {
    if (index == _moreIndex) {
      _showMoreSheet();
      return;
    }
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  Future<void> _showMoreSheet() async {
    final route = await showModalBottomSheet<Widget Function()>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _MoreSheet(),
    );
    if (route == null || !mounted) return;
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => route()));
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _index == _debatesIndex,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = _debatesIndex);
      },
      child: Scaffold(
        // Each tab is its own Scaffold and handles the keyboard itself;
        // resizing here too would lift the navigation bar over the keyboard.
        resizeToAvoidBottomInset: false,
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _moreIndex; i++)
              _visited.contains(i) ? _tabBody(i) : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: _onDestinationSelected,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.forum_outlined),
              selectedIcon: Icon(Icons.forum),
              label: 'Debates',
            ),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(
              icon: Icon(Icons.article_outlined),
              selectedIcon: Icon(Icons.article),
              label: 'Bills',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'Map',
            ),
            NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
          ],
        ),
      ),
    );
  }
}

/// Lists the secondary sections. Pops with a builder for the chosen screen,
/// which the shell then pushes.
class _MoreSheet extends StatelessWidget {
  const _MoreSheet();

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData icon, String label, Widget Function() builder) {
      return ListTile(
        leading: Icon(icon),
        title: Text(label),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).pop(builder),
      );
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          tile(
            Icons.gavel_outlined,
            'Acts of Parliament',
            () => const BillsTimelineView(),
          ),
          tile(
            Icons.event_seat_outlined,
            'Chamber Seating',
            () => const HouseSeatingView(),
          ),
          tile(
            Icons.menu_book_outlined,
            'Standing Orders',
            () => const StandingOrdersView(),
          ),
          tile(
            Icons.bookmark_outline,
            'Saved',
            () => const SavedSpeechesView(),
          ),
          const Divider(height: 1),
          tile(Icons.settings_outlined, 'Settings', () => const SettingsView()),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
