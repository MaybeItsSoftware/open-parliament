import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/parliamentary_data_service.dart';
import '../services/startup_prefetch_service.dart';
import '../services/theme_service.dart';
import '../viewmodels/settings_viewmodel.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();
    final startupPrefetch = context.watch<StartupPrefetchService>();
    final isDark = theme.themeMode == ThemeMode.dark;
    final isSystem = theme.themeMode == ThemeMode.system;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Appearance'),
          SwitchListTile(
            title: const Text('Dark mode'),
            subtitle: isSystem ? const Text('Following system setting') : null,
            value: isDark,
            onChanged: (on) => theme.setThemeMode(
              on ? ThemeMode.dark : ThemeMode.light,
            ),
          ),
          ListTile(
            title: const Text('Use system setting'),
            trailing: isSystem
                ? Icon(Icons.check,
                    color: Theme.of(context).colorScheme.primary)
                : null,
            onTap: () => theme.setThemeMode(ThemeMode.system),
          ),
          const Divider(),
          const _SectionHeader('Data'),
          ExpansionTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear cached data'),
            subtitle: const Text('Free up space or force fresh downloads.'),
            childrenPadding: const EdgeInsets.only(left: 16),
            children: [
              for (final option in _cacheOptions)
                ListTile(
                  leading: Icon(option.icon),
                  title: Text(option.title),
                  subtitle: Text(option.subtitle),
                  onTap: () => _confirmClear(context, option),
                ),
            ],
          ),
          SwitchListTile(
            title: const Text('Preload latest bills and debates'),
            subtitle: const Text(
              'Fetches the most recent sitting and bill updates at launch.',
            ),
            value: startupPrefetch.prefetchOnStartup,
            onChanged: (value) =>
                startupPrefetch.setPrefetchOnStartup(value),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmClear(BuildContext context, _CacheOption option) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${option.title}?'),
        content: Text(option.confirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final vm = SettingsViewModel(context.read<ParliamentaryDataService>());
    final count = await option.clear(vm);

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(option.resultMessage(count))),
    );
  }
}

/// One clearable cache, describing how it appears in the submenu, what its
/// confirmation says, the action that clears it, and how to report the result.
class _CacheOption {
  final IconData icon;
  final String title;
  final String subtitle;
  final String confirmBody;
  final Future<int> Function(SettingsViewModel) clear;
  final String Function(int count) resultMessage;

  const _CacheOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.confirmBody,
    required this.clear,
    required this.resultMessage,
  });
}

const List<_CacheOption> _cacheOptions = [
  _CacheOption(
    icon: Icons.forum_outlined,
    title: 'Clear cached debates',
    subtitle: 'Downloaded transcripts, re-fetched when next viewed.',
    confirmBody: 'All downloaded transcripts will be deleted from this device. '
        'They can be re-fetched from the internet.',
    clear: _clearDebates,
    resultMessage: _debatesResult,
  ),
  _CacheOption(
    icon: Icons.map_outlined,
    title: 'Clear cached maps',
    subtitle: 'Constituency and council boundary shapes.',
    confirmBody: 'Stored map boundaries will be deleted. They will be '
        're-downloaded the next time you open the map.',
    clear: _clearMaps,
    resultMessage: _mapsResult,
  ),
  _CacheOption(
    icon: Icons.groups_outlined,
    title: 'Clear cached councillors',
    subtitle: 'Councillor lists and council control data.',
    confirmBody: 'Stored councillor and council control data will be deleted, '
        'then re-downloaded when next needed.',
    clear: _clearCouncils,
    resultMessage: _councilsResult,
  ),
  _CacheOption(
    icon: Icons.person_outline,
    title: 'Clear cached MPs',
    subtitle: 'Member profiles, re-fetched on next use.',
    confirmBody: 'Stored MP profiles will be deleted, then re-downloaded the '
        'next time members are shown.',
    clear: _clearMembers,
    resultMessage: _membersResult,
  ),
];

// Top-level tear-offs so the option list can stay `const`.
Future<int> _clearDebates(SettingsViewModel vm) => vm.clearCachedDebates();
Future<int> _clearMaps(SettingsViewModel vm) => vm.clearMapBoundaries();
Future<int> _clearCouncils(SettingsViewModel vm) => vm.clearCouncilData();
Future<int> _clearMembers(SettingsViewModel vm) => vm.clearCachedMembers();

String _debatesResult(int count) => count == 0
    ? 'No cached debates found.'
    : 'Cleared $count cached debate${count == 1 ? '' : 's'}.';
String _mapsResult(int count) =>
    count == 0 ? 'No cached maps found.' : 'Cleared cached maps.';
String _councilsResult(int count) => count == 0
    ? 'No cached councillor data found.'
    : 'Cleared cached councillor data.';
String _membersResult(int count) => count == 0
    ? 'No cached MPs found.'
    : 'Cleared $count cached MP profile${count == 1 ? '' : 's'}.';

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
