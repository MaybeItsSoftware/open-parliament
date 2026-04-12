import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/parliamentary_data_service.dart';
import '../services/theme_service.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeService>();
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
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Clear cached debates'),
            subtitle: const Text(
              'Removes locally stored transcripts. '
              'They will be re-downloaded when next viewed.',
            ),
            onTap: () => _confirmWipe(context),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cached debates?'),
        content: const Text(
          'All downloaded transcripts will be deleted from this device. '
          'They can be re-fetched from the internet.',
        ),
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

    final service = context.read<ParliamentaryDataService>();
    final count = await service.wipeDebateCache();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? 'No cached debates found.'
              : 'Cleared $count cached debate${count == 1 ? '' : 's'}.',
        ),
      ),
    );
  }
}

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
