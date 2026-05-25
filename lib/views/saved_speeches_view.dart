import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/saved_speech.dart';
import '../services/saved_speeches_service.dart';
import '../widgets/speech_actions_sheet.dart';
import 'transcript_view.dart';

/// Lists the user's bookmarked speeches, newest first. Tap a card to reopen
/// the originating transcript; long-press (or the overflow) for share/remove.
class SavedSpeechesView extends StatelessWidget {
  const SavedSpeechesView({super.key});

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<SavedSpeechesService>();
    final items = saved.saved;

    return Scaffold(
      appBar: AppBar(title: const Text('Saved')),
      body: items.isEmpty
          ? const _EmptyState()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _SavedCard(speech: items[index]),
            ),
    );
  }
}

class _SavedCard extends StatelessWidget {
  final SavedSpeech speech;

  const _SavedCard({required this.speech});

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TranscriptView(
          date: speech.date,
          displayDate: speech.displayDate,
          initialDebateId: speech.debateId.isNotEmpty ? speech.debateId : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saved = context.read<SavedSpeechesService>();

    return Dismissible(
      key: ValueKey(speech.speechId),
      direction: DismissDirection.endToStart,
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      onDismissed: (_) async {
        await saved.remove(speech.speechId);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Removed from saved')),
        );
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        title: Text(
          speech.speakerName.trim().isNotEmpty
              ? speech.speakerName
              : speech.debateTitle,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              speech.speechText.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              [speech.debateTitle.trim(), speech.displayDate.trim()]
                  .where((s) => s.isNotEmpty)
                  .join(' · '),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        onTap: () => _open(context),
        onLongPress: () => showSpeechActionsSheet(context, speech: speech),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bookmark_border,
                size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: 16),
            Text(
              'No saved speeches yet',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Press and hold any speech in a transcript to save or share it.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
