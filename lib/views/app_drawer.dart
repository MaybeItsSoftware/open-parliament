import 'package:flutter/material.dart';

import 'bills_list_view.dart';
import 'constituency_map_view.dart';
import 'date_selector_view.dart';
import 'house_seating_view.dart';
import 'saved_speeches_view.dart';
import 'search_view.dart';
import 'settings_view.dart';

/// The top-level sections reachable from the navigation drawer.
enum AppDestination { debates, search, bills, map, seating, saved }

/// Shared navigation drawer for the app's main views.
///
/// [current] marks the active destination (highlighted, non-navigating).
/// Switching between main views replaces the current route so the back stack
/// holds a single main view at a time; leaf screens (Saved, Settings) are
/// pushed normally.
class AppDrawer extends StatelessWidget {
  final AppDestination current;

  const AppDrawer({super.key, required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.account_balance,
                      color: theme.colorScheme.primary, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'Open Hansard',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'UK Parliament, verbatim',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _tile(
              context,
              icon: Icons.forum_outlined,
              label: 'Debates',
              destination: AppDestination.debates,
            ),
            _tile(
              context,
              icon: Icons.search,
              label: 'Search',
              destination: AppDestination.search,
            ),
            _tile(
              context,
              icon: Icons.article_outlined,
              label: 'Recent Bills',
              destination: AppDestination.bills,
            ),
            _tile(
              context,
              icon: Icons.map_outlined,
              label: 'Constituency Map',
              destination: AppDestination.map,
            ),
            _tile(
              context,
              icon: Icons.event_seat_outlined,
              label: 'Chamber Seating',
              destination: AppDestination.seating,
            ),
            _tile(
              context,
              icon: Icons.bookmark_outline,
              label: 'Saved',
              destination: AppDestination.saved,
            ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SettingsView()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    required AppDestination destination,
  }) {
    final theme = Theme.of(context);
    final selected = destination == current;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? theme.colorScheme.primary : null,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? theme.colorScheme.primary : null,
          fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.08),
      onTap: () => _navigate(context, destination),
    );
  }

  void _navigate(BuildContext context, AppDestination destination) {
    Navigator.of(context).pop(); // close the drawer
    if (destination == current) return;

    switch (destination) {
      case AppDestination.debates:
        _replaceWith(context, const DateSelectorView());
      case AppDestination.search:
        _replaceWith(context, const SearchView());
      case AppDestination.bills:
        _replaceWith(context, const BillsListView());
      case AppDestination.map:
        _replaceWith(context, const ConstituencyMapView());
      case AppDestination.seating:
        _replaceWith(context, const HouseSeatingView());
      case AppDestination.saved:
        // Saved is a leaf screen with its own back button.
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SavedSpeechesView()),
        );
    }
  }

  void _replaceWith(BuildContext context, Widget view) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => view),
    );
  }
}
