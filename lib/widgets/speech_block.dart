import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/member.dart';
import '../models/speech.dart';
import '../utils/party_colors.dart' as party_util;

/// A transcript block that adapts style to Hansard item structure:
/// - Named speaker contributions: avatar + party tint.
/// - Interpolated time shown inline after the speaker name.
/// - Unattributed/procedural rows: italic text with no avatar.
class SpeechBlock extends StatelessWidget {
  final Speech speech;
  final Member? member;
  final String? timeLabel;
  final VoidCallback? onMemberTap;

  const SpeechBlock({
    super.key,
    required this.speech,
    this.member,
    this.timeLabel,
    this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (speech.isDivision) {
      return _buildDivisionResult(theme);
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
    return _buildSpeakerContribution(theme);
  }

  Widget _buildProceduralRow(ThemeData theme) {
    final chairName = speech.inChairName;
    if (chairName != null) {
      return _buildInChairBanner(theme, chairName);
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
              TextSpan(
                text: speech.speechText,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      child: Text(
        speech.speechText,
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
      child: Text(
        speech.speechText.trim(),
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

    // "Several hon. Members rose—" is purely a stage direction — no content.
    if (text.isEmpty || speech.isAction) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Text(
          text.isNotEmpty
              ? '$entity $text'
              : entity,
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
              backgroundColor:
                  theme.colorScheme.surfaceContainerHighest,
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
                Text(
                  entity,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  text,
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
    final speaker = _speakerIdentity(speech, member);
    final partyKey = member?.partyAbbreviation.isNotEmpty == true
        ? member!.partyAbbreviation
        : (member?.party.isNotEmpty == true
            ? member!.party
            : speaker.partyFromAttribution);
    final partyColor =
        party_util.partyColor(partyKey, fallback: const Color(0xFF6C757D));

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
            child: _buildPortrait(theme, partyColor),
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
                    TextSpan(
                      text: speaker.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontStyle: FontStyle.normal,
                        color: partyColor,
                      ),
                    ),
                    TextSpan(text: ' $actionText'),
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
            child: Text(
              speech.speechText.trim(),
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

  /// Division (vote) result card.
  ///
  /// API format: `index|time|ayes|noes|description|result||ayes_list|noes_list`
  Widget _buildDivisionResult(ThemeData theme) {
    final parts = speech.speechText.trim().split('|');
    final ayes = parts.length > 2 ? int.tryParse(parts[2]) : null;
    final noes = parts.length > 3 ? int.tryParse(parts[3]) : null;
    final description =
        parts.length > 4 ? parts[4].trim() : 'Division';
    final result = parts.length > 5 ? parts[5].trim() : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant,
            width: 1,
          ),
          color: theme.colorScheme.surfaceContainerLow,
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.how_to_vote_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Division',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: theme.textTheme.bodySmall
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              if (ayes != null && noes != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    _DivisionCount(label: 'Ayes', count: ayes,
                        color: const Color(0xFF006548)),
                    const SizedBox(width: 16),
                    _DivisionCount(label: 'Noes', count: noes,
                        color: const Color(0xFFB50938)),
                  ],
                ),
              ],
              if (result.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  result,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInChairBanner(ThemeData theme, String chairName) {
    final partyKey = member?.partyAbbreviation.isNotEmpty == true
        ? member!.partyAbbreviation
        : (member?.party ?? '');
    final partyColor =
        party_util.partyColor(partyKey, fallback: theme.colorScheme.outline);
    final url = member?.thumbnailUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Expanded(child: Divider(color: theme.dividerColor)),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: onMemberTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: partyColor, width: 2),
                  ),
                  child: ClipOval(
                    child: url != null && url.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: url,
                            width: 36,
                            height: 36,
                            fit: BoxFit.cover,
                            placeholder: (_, __) =>
                                _chairInitialsAvatar(theme, partyColor, chairName),
                            errorWidget: (_, __, ___) =>
                                _chairInitialsAvatar(theme, partyColor, chairName),
                          )
                        : _chairInitialsAvatar(theme, partyColor, chairName),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      chairName,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'in the Chair',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: theme.dividerColor)),
        ],
      ),
    );
  }

  Widget _chairInitialsAvatar(
      ThemeData theme, Color partyColor, String name) {
    final initials = _initials(name);
    return CircleAvatar(
      radius: 18,
      backgroundColor: partyColor.withValues(alpha: 0.2),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: _foregroundFor(partyColor, theme),
        ),
      ),
    );
  }

  Widget _buildSpeakerContribution(ThemeData theme) {
    final speaker = _speakerIdentity(speech, member);
    final textTheme = theme.textTheme;
    final partyKey = member?.partyAbbreviation.isNotEmpty == true
        ? member!.partyAbbreviation
        : (member?.party.isNotEmpty == true
            ? member!.party
            : speaker.partyFromAttribution);
    final partyColor = party_util.partyColor(partyKey, fallback: const Color(0xFF6C757D));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                child: _buildPortrait(theme, partyColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: onMemberTap,
                      child: _buildNameLine(textTheme, partyColor),
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

  Widget _buildPortrait(ThemeData theme, Color partyColor) {
    final url = member?.thumbnailUrl;
    if (url != null && url.isNotEmpty) {
      return Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: partyColor, width: 2),
        ),
        child: ClipOval(
          child: CachedNetworkImage(
            imageUrl: url,
            width: 40,
            height: 40,
            fit: BoxFit.cover,
            placeholder: (_, __) => _initialsAvatar(theme, partyColor),
            errorWidget: (_, __, ___) => _initialsAvatar(theme, partyColor),
          ),
        ),
      );
    }
    return _initialsAvatar(theme, partyColor);
  }

  Widget _initialsAvatar(ThemeData theme, Color partyColor) {
    final fallbackName = _speakerIdentity(speech, member).name;
    final initials = _initials(fallbackName);
    final foregroundColor = _foregroundFor(partyColor, theme);
    return CircleAvatar(
      radius: 20,
      backgroundColor: partyColor.withValues(alpha: 0.2),
      child: Text(
        initials,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: foregroundColor,
        ),
      ),
    );
  }

  Widget _buildNameLine(TextTheme textTheme, Color partyColor) {
    final speaker = _speakerIdentity(speech, member);

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
                  color: partyColor,
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
            style: textTheme.bodySmall?.copyWith(
              color: textTheme.bodySmall?.color,
            ),
          ),
        if (speaker.constituency.isNotEmpty)
          Text(
            'MP for ${speaker.constituency}',
            style: textTheme.bodySmall?.copyWith(
              color: textTheme.bodySmall?.color,
            ),
          ),
      ],
    );
  }

  static String _extractPartyNameFromAttribution(String attribution) {
    final matches = RegExp(r'\(([^)]+)\)').allMatches(attribution);
    String? bestRecognized;
    for (final match in matches) {
      final candidate = (match.group(1) ?? '').trim();
      if (candidate.isEmpty) continue;
      if (party_util.canonicalPartyToken(candidate) != null) {
        bestRecognized = candidate;
      }
    }
    return bestRecognized ?? '';
  }

  static _SpeakerIdentity _speakerIdentity(Speech speech, Member? member) {
    final attribution = speech.attributedTo.trim();
    final preferredName = member?.name.trim().isNotEmpty == true
        ? member!.name.trim()
        : speech.memberName.trim();

    if (attribution.isEmpty) {
      return _SpeakerIdentity(
        name: preferredName.isNotEmpty ? preferredName : 'Unknown speaker',
        title: '',
        constituency: '',
        partyFromAttribution: '',
      );
    }

    final head = attribution.split('(').first.trim();
    final matches = RegExp(r'\(([^)]+)\)').allMatches(attribution).toList();
    final bracketed = matches
        .map((m) => (m.group(1) ?? '').trim())
        .where((value) => value.isNotEmpty)
        .toList();
    final nonParty = bracketed
        .where((value) => party_util.canonicalPartyToken(value) == null)
        .toList();
    final partyFromAttribution = _extractPartyNameFromAttribution(attribution);

    String name = '';
    if (preferredName.isNotEmpty && !_looksLikeRoleTitle(preferredName)) {
      name = preferredName;
    } else {
      final person = nonParty.firstWhere(
        _looksLikePersonName,
        orElse: () => '',
      );
      if (person.isNotEmpty) {
        name = person;
      } else if (!_looksLikeRoleTitle(head) && head.isNotEmpty) {
        name = head;
      } else {
        name = preferredName.isNotEmpty ? preferredName : attribution;
      }
    }

    final title = _looksLikeRoleTitle(head) ? head : '';
    String constituency = '';
    for (final value in nonParty) {
      if (value == name) continue;
      if (_looksLikeRoleTitle(value)) continue;
      constituency = value;
      break;
    }

    return _SpeakerIdentity(
      name: name.replaceAll(RegExp(r'\s{2,}'), ' ').trim(),
      title: title,
      constituency: constituency,
      partyFromAttribution: partyFromAttribution,
    );
  }

  static bool _looksLikeRoleTitle(String value) {
    final v = value.toLowerCase();
    if (v.startsWith('the ')) return true;
    return v.contains('secretary') ||
        v.contains('minister') ||
        v.contains('chancellor') ||
        v.contains('advocate') ||
        v.contains('attorney') ||
        v.contains('spokesperson') ||
        v.contains('commissioner') ||
        v.contains('lord ') ||
        v.contains('baroness ') ||
        v.contains('speaker') ||
        v.contains('whip') ||
        v.contains('captain of') ||
        v.contains('comptroller') ||
        v.contains('adjutant') ||
        v.contains('treasurer of');
  }

  static bool _looksLikePersonName(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return false;
    final personLike = RegExp(r"^[A-Z][a-zA-Z'\-]+$");
    if (!parts.every(personLike.hasMatch)) return false;
    // Reject strings containing function words that appear in titles but not names.
    // Check lowercased so capitalised variants ("The", "Of") are also caught.
    const functionWords = {'the', 'of', 'and', 'at', 'for', 'in', 'to', 'by', 'or'};
    return !parts.any((p) => functionWords.contains(p.toLowerCase()));
  }

  static Color _foregroundFor(Color background, ThemeData theme) {
    final brightness = ThemeData.estimateBrightnessForColor(background);
    return brightness == Brightness.dark
        ? Colors.white
        : theme.colorScheme.onSurface;
  }

  static String _initials(String name) {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[parts.length - 1][0]}'.toUpperCase();
  }
}

class _DivisionCount extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _DivisionCount({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          '$label: $count',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: color,
              ),
        ),
      ],
    );
  }
}

class _SpeakerIdentity {
  final String name;
  final String title;
  final String constituency;
  final String partyFromAttribution;

  const _SpeakerIdentity({
    required this.name,
    required this.title,
    required this.constituency,
    required this.partyFromAttribution,
  });
}
