import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/member.dart';
import '../models/speech.dart';

/// A transcript block that adapts style to Hansard item structure:
/// - Named speaker contributions: avatar + party tint.
/// - Interpolated time shown inline after the speaker name.
/// - Unattributed/procedural rows: italic text with no avatar.
class SpeechBlock extends StatelessWidget {
  final Speech speech;
  final Member? member;
  final String? timeLabel;

  const SpeechBlock({
    super.key,
    required this.speech,
    this.member,
    this.timeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (speech.isProceduralText) {
      return _buildProceduralRow(theme);
    }
    return _buildSpeakerContribution(theme);
  }

  Widget _buildProceduralRow(ThemeData theme) {
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

  Widget _buildSpeakerContribution(ThemeData theme) {
    final speaker = _speakerIdentity(speech, member);
    final textTheme = theme.textTheme;
    final partyKey = member?.partyAbbreviation.isNotEmpty == true
        ? member!.partyAbbreviation
        : (member?.party.isNotEmpty == true
            ? member!.party
            : speaker.partyFromAttribution);
    final partyColor = _partyColorFor(partyKey, theme);

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
              _buildPortrait(theme, partyColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildNameLine(textTheme, partyColor),
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
    final name = speaker.name;
    final partyText = member?.party.isNotEmpty == true
        ? member!.party
        : speaker.partyFromAttribution;
    final partyLabel = partyText.isNotEmpty ? ' ($partyText)' : '';
    final titleAndConstituency = [
      if (speaker.title.isNotEmpty) speaker.title,
      if (speaker.constituency.isNotEmpty) 'MP for ${speaker.constituency}',
    ].join(' • ');

    return RichText(
      text: TextSpan(
        style: textTheme.bodyMedium,
        children: [
          TextSpan(
            text: name,
            style: TextStyle(fontWeight: FontWeight.bold, color: partyColor),
          ),
          if (partyLabel.isNotEmpty)
            TextSpan(
              text: partyLabel,
              style: TextStyle(color: textTheme.bodyMedium?.color),
            ),
          if (titleAndConstituency.isNotEmpty)
            TextSpan(
              text: '  —  $titleAndConstituency',
              style: TextStyle(color: textTheme.bodySmall?.color),
            ),
          if (timeLabel != null && timeLabel!.isNotEmpty)
            TextSpan(
              text: '  •  $timeLabel',
              style: TextStyle(
                color: textTheme.bodySmall?.color,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  static String _extractPartyNameFromAttribution(String attribution) {
    final matches = RegExp(r'\(([^)]+)\)').allMatches(attribution);
    String? bestRecognized;
    for (final match in matches) {
      final candidate = (match.group(1) ?? '').trim();
      if (candidate.isEmpty) continue;
      if (_canonicalPartyToken(candidate) != null) {
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
        .where((value) => _canonicalPartyToken(value) == null)
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
        v.contains('speaker');
  }

  static bool _looksLikePersonName(String value) {
    final parts = value.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return false;
    final personLike = RegExp(r"^[A-Z][a-zA-Z'\-]+$");
    return parts.every(personLike.hasMatch);
  }

  static String _normalisePartyToken(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '').trim();
  }

  static Color _partyColorFor(String partyName, ThemeData theme) {
    final token = _canonicalPartyToken(partyName);
    if (token == 'labour') {
      return const Color(0xFFE4003B);
    }
    if (token == 'conservative') return const Color(0xFF0087DC);
    if (token == 'libdem') {
      return const Color(0xFFFDBB30);
    }
    if (token == 'snp') {
      return const Color(0xFFEACB00);
    }
    if (token == 'green') return const Color(0xFF6AB023);
    if (token == 'plaidcymru') return const Color(0xFF008142);
    if (token == 'sinnfein') return const Color(0xFF326760);
    if (token == 'dup') {
      return const Color(0xFFD46A4C);
    }
    if (token == 'uup') return const Color(0xFF48A9E6);
    if (token == 'alliance') return const Color(0xFFFFD447);
    if (token == 'crossbench' || token == 'independent') {
      return const Color(0xFF6C757D);
    }
    if (token == 'reform') return const Color(0xFF12B6CF);
    return const Color(0xFF6C757D);
  }

  static String? _canonicalPartyToken(String value) {
    final raw = value.toLowerCase().trim();
    final norm = _normalisePartyToken(value);
    if (norm.isEmpty) return null;

    if (norm == 'lab' ||
        norm == 'labour' ||
        norm == 'labourparty' ||
        norm == 'labourandcooperative' ||
        norm == 'labourcooperative' ||
        norm == 'labcoop' ||
        raw.contains('lab co-op')) {
      return 'labour';
    }

    if (norm == 'con' ||
        norm == 'conservative' ||
        norm == 'conservativeparty' ||
        norm == 'conservativeandunionistparty') {
      return 'conservative';
    }

    if (norm == 'ld' ||
        norm == 'libdem' ||
        norm == 'liberaldemocrat' ||
        norm == 'liberaldemocrats' ||
        raw.contains('lib dem')) {
      return 'libdem';
    }

    if (norm == 'snp' || norm == 'scottishnationalparty') return 'snp';
    if (norm == 'green' || raw.contains('green party')) return 'green';
    if (norm == 'plaidcymru') return 'plaidcymru';
    if (norm == 'sinnfein') return 'sinnfein';
    if (norm == 'dup' || norm == 'democraticunionistparty') return 'dup';
    if (norm == 'uup' || norm == 'ulsterunionistparty') return 'uup';
    if (norm == 'alliance' || norm == 'allianceparty') return 'alliance';
    if (norm == 'cb' || norm == 'crossbench' || raw.contains('crossbench')) {
      return 'crossbench';
    }
    if (norm == 'nonaffiliated' ||
        norm == 'unpartied' ||
        norm == 'independent') {
      return 'independent';
    }
    if (norm == 'reform' || norm == 'reformuk') return 'reform';
    return null;
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
