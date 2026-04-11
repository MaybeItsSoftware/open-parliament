import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/member.dart';
import '../models/speech.dart';

/// A single speech contribution block rendered in the transcript list.
///
/// Layout:
/// ```
/// ┌──────────────────────────────────────┐
/// │  [Portrait]  Adam Smith (Labour)     │
/// │              ...speech text...       │
/// └──────────────────────────────────────┘
/// ```
///
/// The portrait is a 40 px circular avatar loaded from a local disk cache via
/// [CachedNetworkImage].  Providing [member] is optional – when absent the
/// initials of [speech.memberName] are shown instead.
class SpeechBlock extends StatelessWidget {
  final Speech speech;
  final Member? member;

  const SpeechBlock({
    super.key,
    required this.speech,
    this.member,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPortrait(theme),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildNameLine(textTheme),
                const SizedBox(height: 4),
                _buildSpeechText(textTheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPortrait(ThemeData theme) {
    final url = member?.thumbnailUrl;

    if (url != null && url.isNotEmpty) {
      return ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: 40,
          height: 40,
          fit: BoxFit.cover,
          placeholder: (_, __) => _initialsAvatar(theme),
          errorWidget: (_, __, ___) => _initialsAvatar(theme),
        ),
      );
    }
    return _initialsAvatar(theme);
  }

  Widget _initialsAvatar(ThemeData theme) {
    final initials = _initials(speech.memberName);
    return CircleAvatar(
      radius: 20,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  Widget _buildNameLine(TextTheme textTheme) {
    final name = speech.memberName.isNotEmpty
        ? speech.memberName
        : speech.attributedTo;

    final partyLabel = member?.party.isNotEmpty == true
        ? ' (${member!.party})'
        : _extractPartyFromAttribution(speech.attributedTo);

    return RichText(
      text: TextSpan(
        style: textTheme.bodyMedium,
        children: [
          TextSpan(
            text: name,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (partyLabel.isNotEmpty)
            TextSpan(
              text: partyLabel,
              style: const TextStyle(fontWeight: FontWeight.normal),
            ),
        ],
      ),
    );
  }

  Widget _buildSpeechText(TextTheme textTheme) {
    return Text(
      speech.speechText,
      style: textTheme.bodyMedium,
    );
  }

  /// Extracts the party label from an attribution string of the form
  /// "Name (Party/Constituency)".
  static String _extractPartyFromAttribution(String attribution) {
    final match = RegExp(r'\(([^)]+)\)').firstMatch(attribution);
    if (match == null) return '';
    return ' (${match.group(1)})';
  }

  /// Returns up to two initials from [name].
  static String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }
}
