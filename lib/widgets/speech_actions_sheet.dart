import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/saved_speech.dart';
import '../services/saved_speeches_service.dart';
import '../utils/speech_share.dart';

/// Bottom sheet shown when a transcript speech is long-pressed. Offers
/// bookmarking, copy-to-clipboard, the native share sheet (WhatsApp,
/// Messages, Mail, …) and, when [onWatchFromHere] is supplied, a
/// "Watch from here" deep-link into the parliamentlive.tv recording.
///
/// The sheet stays decoupled from services: the caller decides whether a
/// timecode exists and owns resolving/opening the video. [watchFromHereLabel]
/// is shown as the action's subtitle (e.g. the estimated clock time).
Future<void> showSpeechActionsSheet(
  BuildContext context, {
  required SavedSpeech speech,
  VoidCallback? onWatchFromHere,
  String? watchFromHereLabel,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder:
        (sheetContext) => SpeechActionsSheet(
          speech: speech,
          onWatchFromHere: onWatchFromHere,
          watchFromHereLabel: watchFromHereLabel,
        ),
  );
}

/// Content of [showSpeechActionsSheet]. Public so it can be pumped directly
/// in widget tests.
class SpeechActionsSheet extends StatelessWidget {
  final SavedSpeech speech;

  /// Invoked (after the sheet is dismissed) when "Watch from here" is tapped.
  /// The action is hidden when null.
  final VoidCallback? onWatchFromHere;

  /// Optional subtitle for the "Watch from here" action.
  final String? watchFromHereLabel;

  const SpeechActionsSheet({
    super.key,
    required this.speech,
    this.onWatchFromHere,
    this.watchFromHereLabel,
  });

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
      // Scrollable so the action list never overflows the sheet's height cap
      // on short (e.g. landscape) viewports.
      child: SingleChildScrollView(
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
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  const SizedBox(height: 2),
                  Text(
                    speech.speechText.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (onWatchFromHere != null)
              ListTile(
                leading: const Icon(Icons.smart_display_outlined),
                title: const Text('Watch from here'),
                subtitle:
                    watchFromHereLabel == null
                        ? null
                        : Text(watchFromHereLabel!),
                onTap: () {
                  Navigator.of(context).pop();
                  onWatchFromHere!();
                },
              ),
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
                  subject:
                      speech.debateTitle.isNotEmpty
                          ? '${speech.debateTitle} — Hansard'
                          : 'Hansard',
                  // iPad requires an anchor rect for the share popover.
                  sharePositionOrigin:
                      box != null
                          ? box.localToGlobal(Offset.zero) & box.size
                          : null,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
