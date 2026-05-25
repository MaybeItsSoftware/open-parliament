import '../models/member.dart';
import '../models/speech.dart';
import 'party_tokens.dart';

/// What `SpeechBlock` needs to render a contribution's header: how to address
/// the speaker, their ministerial title (if any), their constituency (if any),
/// and the party as it appeared in the Hansard attribution string (used when
/// no [Member] profile is available to colour the avatar).
class SpeakerIdentity {
  final String name;
  final String title;
  final String constituency;
  final String partyFromAttribution;

  const SpeakerIdentity({
    required this.name,
    required this.title,
    required this.constituency,
    required this.partyFromAttribution,
  });
}

/// Resolves the best display fields for a speech, preferring a matched
/// [Member]'s name when one is available, otherwise parsing the raw Hansard
/// attribution string ("The Minister of State, FCDO (Andrew Mitchell) (Con)").
SpeakerIdentity speakerIdentityFor(Speech speech, Member? member) {
  final attribution = speech.attributedTo.trim();
  final preferredName = member?.name.trim().isNotEmpty == true
      ? member!.name.trim()
      : speech.memberName.trim();

  if (attribution.isEmpty) {
    return SpeakerIdentity(
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
      .where((value) => canonicalPartyToken(value) == null)
      .toList();
  final partyFromAttribution = _extractPartyNameFromAttribution(attribution);

  String name = '';
  if (preferredName.isNotEmpty && !looksLikeRoleTitle(preferredName)) {
    name = preferredName;
  } else {
    final person = nonParty.firstWhere(
      looksLikePersonName,
      orElse: () => '',
    );
    if (person.isNotEmpty) {
      name = person;
    } else if (!looksLikeRoleTitle(head) && head.isNotEmpty) {
      name = head;
    } else {
      name = preferredName.isNotEmpty ? preferredName : attribution;
    }
  }

  final title = looksLikeRoleTitle(head) ? head : '';
  String constituency = '';
  for (final value in nonParty) {
    if (value == name) continue;
    if (looksLikeRoleTitle(value)) continue;
    constituency = value;
    break;
  }

  return SpeakerIdentity(
    name: name.replaceAll(RegExp(r'\s{2,}'), ' ').trim(),
    title: title,
    constituency: constituency,
    partyFromAttribution: partyFromAttribution,
  );
}

/// True for things that look like a ministerial / officer role rather than a
/// person's name (e.g. "The Minister of State", "Mr Speaker", "Lord Chancellor").
bool looksLikeRoleTitle(String value) {
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

/// True for "Firstname Lastname" or "Firstname Middle Lastname" style values,
/// excluding strings containing function words that appear in titles.
bool looksLikePersonName(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return false;
  final personLike = RegExp(r"^[A-Z][a-zA-Z'\-]+$");
  if (!parts.every(personLike.hasMatch)) return false;
  const functionWords = {'the', 'of', 'and', 'at', 'for', 'in', 'to', 'by', 'or'};
  return !parts.any((p) => functionWords.contains(p.toLowerCase()));
}

bool isSpeakerRole(SpeakerIdentity speaker) {
  final label = '${speaker.name} ${speaker.title}'.toLowerCase();
  return RegExp(r'\bspeaker\b').hasMatch(label);
}

String _extractPartyNameFromAttribution(String attribution) {
  final matches = RegExp(r'\(([^)]+)\)').allMatches(attribution);
  String? bestRecognized;
  for (final match in matches) {
    final candidate = (match.group(1) ?? '').trim();
    if (candidate.isEmpty) continue;
    if (canonicalPartyToken(candidate) != null) {
      bestRecognized = candidate;
    }
  }
  return bestRecognized ?? '';
}
