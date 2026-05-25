import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/speech.dart';
import '../../utils/party_colors.dart' as party_util;
import '../../utils/speaker_identity.dart';

/// The standard named-contribution card: party-tinted left border, avatar,
/// speaker name + title + constituency, and the speech body.
class SpeakerContributionCard extends StatelessWidget {
  final Speech speech;
  final Member? member;
  final String? timeLabel;
  final VoidCallback? onMemberTap;

  const SpeakerContributionCard({
    super.key,
    required this.speech,
    required this.member,
    this.timeLabel,
    this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final speaker = speakerIdentityFor(speech, member);
    final partyKey = member?.partyAbbreviation.isNotEmpty == true
        ? member!.partyAbbreviation
        : (member?.party.isNotEmpty == true
            ? member!.party
            : speaker.partyFromAttribution);
    final partyColor =
        party_util.partyColor(partyKey, fallback: const Color(0xFF6C757D));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: partyColor, width: 4)),
          color: partyColor.withValues(alpha: 0.06),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                onTap: onMemberTap,
                child: SpeakerPortrait(
                  member: member,
                  fallbackName: speaker.name,
                  partyColor: partyColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onMemberTap,
                      child: _NameLine(
                        speaker: speaker,
                        partyColor: partyColor,
                        timeLabel: timeLabel,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      speech.speechText,
                      style: speech.isQuote
                          ? textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                            )
                          : textTheme.bodyMedium,
                      textAlign: TextAlign.justify,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Circular portrait for a speaker. Falls back to initials when no
/// [Member.thumbnailUrl] is available or the network image fails to load.
class SpeakerPortrait extends StatelessWidget {
  final Member? member;
  final String fallbackName;
  final Color partyColor;
  final double size;

  const SpeakerPortrait({
    super.key,
    required this.member,
    required this.fallbackName,
    required this.partyColor,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = member?.thumbnailUrl;
    if (url != null && url.isNotEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: partyColor, width: 2),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            placeholder: (_, __) =>
                _initialsAvatar(theme, partyColor, fallbackName, size),
            errorWidget: (_, __, ___) =>
                _initialsAvatar(theme, partyColor, fallbackName, size),
          ),
        ),
      );
    }
    return _initialsAvatar(theme, partyColor, fallbackName, size);
  }
}

class _NameLine extends StatelessWidget {
  final SpeakerIdentity speaker;
  final Color partyColor;
  final String? timeLabel;

  const _NameLine({
    required this.speaker,
    required this.partyColor,
    required this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final nameColor =
        isSpeakerRole(speaker) ? theme.colorScheme.onSurface : partyColor;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                speaker.name,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: nameColor,
                ),
              ),
            ),
            if (timeLabel != null && timeLabel!.isNotEmpty)
              Text(
                timeLabel!,
                style: textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
        if (speaker.title.isNotEmpty)
          Text(
            speaker.title,
            style: textTheme.bodySmall,
          ),
        if (speaker.constituency.isNotEmpty)
          Text(
            'MP for ${speaker.constituency}',
            style: textTheme.bodySmall,
          ),
      ],
    );
  }
}

Widget _initialsAvatar(
  ThemeData theme,
  Color partyColor,
  String name,
  double diameter,
) {
  final initials = _initials(name);
  return CircleAvatar(
    radius: diameter / 2,
    backgroundColor: partyColor.withValues(alpha: 0.2),
    child: Text(
      initials,
      style: TextStyle(
        fontSize: diameter * 0.35,
        fontWeight: FontWeight.bold,
        color: _foregroundFor(partyColor, theme),
      ),
    ),
  );
}

String _initials(String name) {
  if (name.isEmpty) return '?';
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.length == 1) return parts[0][0].toUpperCase();
  return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
}

Color _foregroundFor(Color background, ThemeData theme) {
  final brightness = ThemeData.estimateBrightnessForColor(background);
  return brightness == Brightness.dark
      ? Colors.white
      : theme.colorScheme.onSurface;
}
