import 'package:flutter/material.dart';

import '../models/member.dart';
import '../models/speech.dart';
import '../utils/committee_roster.dart';
import '../utils/party_colors.dart' as party_util;
import '../utils/speaker_identity.dart';
import 'speech_block/committee_roster_card.dart';
import 'speech_block/division_result_card.dart';
import 'speech_block/highlighted_text.dart';
import 'speech_block/in_chair_banner.dart';
import 'speech_block/speaker_contribution_card.dart';

/// A transcript block that adapts style to Hansard item structure:
/// - Named speaker contributions: avatar + party tint.
/// - Interpolated time shown inline after the speaker name.
/// - Unattributed/procedural rows: italic text with no avatar.
///
/// This is a dispatcher: it inspects flags on [Speech] to pick the right
/// sub-widget under `lib/widgets/speech_block/`. The variants in this file
/// (prayers, event tags, collective speakers, procedural text, actions,
/// procedure outcomes) are small enough that inlining keeps them findable.
class SpeechBlock extends StatelessWidget {
  final Speech speech;
  final Member? member;
  final String? timeLabel;
  final VoidCallback? onMemberTap;

  /// Active find-in-transcript search term; matches are highlighted inline.
  /// Empty when not searching.
  final String searchQuery;

  const SpeechBlock({
    super.key,
    required this.speech,
    this.member,
    this.timeLabel,
    this.onMemberTap,
    this.searchQuery = '',
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (speech.isDivision) {
      return DivisionResultCard(rawSpeechText: speech.speechText);
    }
    if (speech.isPrayers) {
      return _buildPrayersBanner(theme);
    }
    if (speech.isEventTag) {
      return _buildEventTag(theme);
    }
    if (speech.isCollectiveSpeaker) {
      return _buildCollectiveSpeaker(theme);
    }
    if (speech.isProceduralText) {
      return _buildProceduralRow(theme);
    }
    if (speech.isProcedureOutcome) {
      return _buildProcedureOutcome(theme);
    }
    if (speech.isAction) {
      return _buildActionRow(theme);
    }
    return SpeakerContributionCard(
      speech: speech,
      member: member,
      timeLabel: timeLabel,
      onMemberTap: onMemberTap,
      searchQuery: searchQuery,
    );
  }

  Widget _buildProceduralRow(ThemeData theme) {
    final chairName = speech.inChairName;
    if (chairName != null) {
      return InChairBanner(
        chairName: chairName,
        member: member,
        onMemberTap: onMemberTap,
      );
    }

    final roster = CommitteeRoster.tryParse(speech.speechText);
    if (roster != null) {
      return CommitteeRosterCard(roster: roster);
    }

    if (speech.isTabledBy) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        child: RichText(
          text: TextSpan(
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            children: [
              const TextSpan(text: 'Moved by '),
              ...highlightedSpans(
                text: speech.speechText,
                query: searchQuery,
                style: const TextStyle(fontWeight: FontWeight.w700),
                highlightStyle: TextStyle(
                  backgroundColor: theme.colorScheme.tertiaryContainer,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: HighlightedText(
        speech.speechText,
        query: searchQuery,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.45,
        ),
        textAlign: TextAlign.justify,
      ),
    );
  }

  /// Centred divider banner for the Prayers entry at the start of a sitting.
  Widget _buildPrayersBanner(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.dividerColor)),
          const SizedBox(width: 12),
          Icon(Icons.self_improvement,
              size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'Prayers',
            style: theme.textTheme.labelMedium?.copyWith(
              fontStyle: FontStyle.italic,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: theme.dividerColor)),
        ],
      ),
    );
  }

  /// Inline tag for procedural events like "Question put and agreed to".
  Widget _buildEventTag(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: HighlightedText(
        speech.speechText.trim(),
        query: searchQuery,
        style: theme.textTheme.bodySmall?.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// Compact row for collective/anonymous entities like "Hon. Members",
  /// "Several hon. Members rose—", "An hon. Member".
  Widget _buildCollectiveSpeaker(ThemeData theme) {
    final text = speech.speechText.trim();
    final entity = speech.attributedTo.trim();

    if (text.isEmpty || speech.isAction) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: HighlightedText(
          text.isNotEmpty ? '$entity $text' : entity,
          query: searchQuery,
          style: theme.textTheme.bodySmall?.copyWith(
            fontStyle: FontStyle.italic,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.groups_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HighlightedText(
                  entity,
                  query: searchQuery,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                HighlightedText(
                  text,
                  query: searchQuery,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Compact italic row for stage-direction actions like "rose—", "resumed—".
  Widget _buildActionRow(ThemeData theme) {
    final speaker = speakerIdentityFor(speech, member);
    final partyKey = member?.partyAbbreviation.isNotEmpty == true
        ? member!.partyAbbreviation
        : (member?.party.isNotEmpty == true
            ? member!.party
            : speaker.partyFromAttribution);
    final partyColor =
        party_util.partyColor(partyKey, fallback: const Color(0xFF6C757D));
    final nameColor =
        isSpeakerRole(speaker) ? theme.colorScheme.onSurface : partyColor;

    // Convert "rose—" → "rose." etc. for display
    final raw = speech.speechText.trim();
    final actionText = raw.endsWith('—')
        ? '${raw.substring(0, raw.length - 1).trim()}.'
        : raw;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          GestureDetector(
            onTap: onMemberTap,
            child: SpeakerPortrait(
              member: member,
              fallbackName: speaker.name,
              partyColor: partyColor,
              size: 32,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onMemberTap,
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  children: [
                    ...highlightedSpans(
                      text: speaker.name,
                      query: searchQuery,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.normal,
                        color: nameColor,
                      ),
                      highlightStyle: TextStyle(
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                    ...highlightedSpans(
                      text: ' $actionText',
                      query: searchQuery,
                      highlightStyle: TextStyle(
                        backgroundColor: theme.colorScheme.tertiaryContainer,
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Outcome line for procedure results like "Motion agreed.", "Bill passed.".
  Widget _buildProcedureOutcome(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 14,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: HighlightedText(
              speech.speechText.trim(),
              query: searchQuery,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
