import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/saved_speech.dart';
import '../services/saved_speeches_service.dart';
import '../utils/speech_share.dart';

/// Bottom sheet shown when a transcript speech is long-pressed. Offers
/// bookmarking, copy-to-clipboard, and the native share sheet (WhatsApp,
/// Messages, Mail, …).
Future<void> showSpeechActionsSheet(
  BuildContext context, {
  required SavedSpeech speech,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => _SpeechActionsSheet(speech: speech),
  );
}

class _SpeechActionsSheet extends StatelessWidget {
  final SavedSpeech speech;

  const _SpeechActionsSheet({required this.speech});

  String get _shareText => buildSpeechShareText(
        speakerName: speech.speakerName,
        speechText: speech.speechText,
        debateTitle: speech.debateTitle,
        displayDate: speech.displayDate,
      );

  @override
  Widget build(BuildContext context) {
    final saved = context.watch<SavedSpeechesService>();
    final isSaved = saved.isSaved(speech.speechId);
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (speech.speakerName.trim().isNotEmpty)
                  Text(
                    speech.speakerName,
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                const SizedBox(height: 2),
                Text(
                  speech.speechText.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(
              isSaved ? Icons.bookmark : Icons.bookmark_border,
              color: isSaved ? theme.colorScheme.primary : null,
            ),
            title: Text(isSaved ? 'Remove bookmark' : 'Save'),
            onTap: () async {
              final nowSaved = await saved.toggle(speech);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(nowSaved ? 'Saved' : 'Removed from saved'),
                ),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('Copy text'),
            onTap: () async {
              await Clipboard.setData(ClipboardData(text: _shareText));
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Copied to clipboard')),
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.share_outlined),
            title: const Text('Share…'),
            subtitle: const Text('WhatsApp, Messages, Mail, and more'),
            onTap: () async {
              // Capture before the async gap so we don't touch the popped tree.
              final box = context.findRenderObject() as RenderBox?;
              Navigator.of(context).pop();
              await Share.share(
                _shareText,
                subject: speech.debateTitle.isNotEmpty
                    ? '${speech.debateTitle} — Hansard'
                    : 'Hansard',
                // iPad requires an anchor rect for the share popover.
                sharePositionOrigin: box != null
                    ? box.localToGlobal(Offset.zero) & box.size
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }
}
