import 'package:flutter/material.dart';

import '../../models/member.dart';
import '../../models/speech.dart';
import '../../utils/party_colors.dart' as party_util;
import '../../utils/speaker_identity.dart';
import '../person_avatar.dart';
import 'highlighted_text.dart';

/// The standard named-contribution card: party-tinted left border, avatar,
/// speaker name + title + constituency, and the speech body.
class SpeakerContributionCard extends StatelessWidget {
  final Speech speech;
  final Member? member;
  final String? timeLabel;
  final VoidCallback? onMemberTap;

  /// Active find-in-transcript search term; matches are highlighted inline
  /// within the speaker name and speech body. Empty when not searching.
  final String searchQuery;

  const SpeakerContributionCard({
    super.key,
    required this.speech,
    required this.member,
    this.timeLabel,
    this.onMemberTap,
    this.searchQuery = '',
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
                        searchQuery: searchQuery,
                      ),
                    ),
                    const SizedBox(height: 4),
                    HighlightedText(
                      speech.speechText,
                      query: searchQuery,
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
    return PersonAvatar(
      imageUrl: member?.thumbnailUrl,
      name: fallbackName,
      color: partyColor,
      size: size,
    );
  }
}

class _NameLine extends StatelessWidget {
  final SpeakerIdentity speaker;
  final Color partyColor;
  final String? timeLabel;
  final String searchQuery;

  const _NameLine({
    required this.speaker,
    required this.partyColor,
    required this.timeLabel,
    this.searchQuery = '',
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
              child: HighlightedText(
                speaker.name,
                query: searchQuery,
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
