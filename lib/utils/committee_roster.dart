import 'party_tokens.dart';

/// A chair seat on a committee roster.
class CommitteeChair {
  final String name;
  final bool attended;
  const CommitteeChair({required this.name, required this.attended});
}

/// A single member entry on a committee roster.
class CommitteeMember {
  final String name;
  final String constituency;
  final String role;
  final String party;
  final bool attended;

  const CommitteeMember({
    required this.name,
    required this.constituency,
    required this.role,
    required this.party,
    required this.attended,
  });
}

/// Parsed structure of the "Committee consisted of the following Members:"
/// procedural block produced by the transcript view-model's roster merger.
///
/// Use [CommitteeRoster.tryParse] to attempt a parse; returns `null` when the
/// text isn't a roster block, in which case the caller falls back to plain
/// italic procedural rendering.
class CommitteeRoster {
  final List<CommitteeChair> chairs;
  final List<CommitteeMember> members;
  final String clerks;

  const CommitteeRoster({
    required this.chairs,
    required this.members,
    required this.clerks,
  });

  bool get attendedAny =>
      chairs.any((c) => c.attended) || members.any((m) => m.attended);

  static CommitteeRoster? tryParse(String fullText) {
    final raw = fullText.trim();
    if (raw.isEmpty) return null;
    final lines = raw
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.length < 2) return null;
    if (!lines.first
        .toLowerCase()
        .contains('the committee consisted of the following members:')) {
      return null;
    }

    final chairs = <CommitteeChair>[];
    final members = <CommitteeMember>[];
    String clerks = '';

    for (var i = 1; i < lines.length; i++) {
      final line = lines[i];
      final lower = line.toLowerCase();

      if (lower.startsWith('chair:') || lower.startsWith('chairs:')) {
        final tail = line.substring(line.indexOf(':') + 1);
        chairs.addAll(_parseChairs(tail));
        continue;
      }

      if (_isLegendLine(lower)) continue;

      if (lower.contains('committee clerk')) {
        clerks = _stripClerksSuffix(line);
        continue;
      }

      final parsed = _parseMemberLine(line);
      if (parsed != null) members.add(parsed);
    }

    if (chairs.isEmpty && members.isEmpty) return null;
    return CommitteeRoster(
      chairs: chairs,
      members: members,
      clerks: clerks,
    );
  }
}

bool _isLegendLine(String lower) {
  final stripped = lower.replaceFirst(RegExp(r'^[•†]\s*'), '');
  return stripped.startsWith('attended the committee');
}

String _stripClerksSuffix(String line) {
  var text = line.replaceFirst(RegExp(r'^[•†]\s*'), '').trim();
  text = text.replaceAll(
    RegExp(r',\s*Committee Clerks?\.?\s*$', caseSensitive: false),
    '',
  );
  return text.trim();
}

List<CommitteeChair> _parseChairs(String segment) {
  return segment
      .split(',')
      .map((c) => c.trim())
      .where((c) => c.isNotEmpty)
      .map((c) {
    final attended = c.startsWith('†');
    final name = attended ? c.replaceFirst(RegExp(r'^†\s*'), '').trim() : c;
    return CommitteeChair(name: name, attended: attended);
  }).toList();
}

CommitteeMember? _parseMemberLine(String line) {
  var text = line.trim();
  if (text.isEmpty) return null;
  var attended = false;
  if (text.startsWith('•') || text.startsWith('†')) {
    attended = true;
    text = text.replaceFirst(RegExp(r'^[•†]\s*'), '').trim();
  }
  if (text.isEmpty) return null;

  final parens = RegExp(r'\(([^)]+)\)').allMatches(text).toList();
  if (parens.isEmpty) {
    return CommitteeMember(
      name: text,
      constituency: '',
      role: '',
      party: '',
      attended: attended,
    );
  }
  final name = text.substring(0, parens.first.start).trim().replaceAll(
        RegExp(r',\s*$'),
        '',
      );
  final brackets = parens
      .map((m) => (m.group(1) ?? '').trim())
      .where((b) => b.isNotEmpty)
      .toList();

  String constituency = '';
  String role = '';
  String party = '';
  for (final b in brackets) {
    if (canonicalPartyToken(b) != null) {
      party = b;
    } else if (constituency.isEmpty && !_looksLikeMinisterialRole(b)) {
      constituency = b;
    } else {
      role = role.isEmpty ? b : '$role; $b';
    }
  }

  return CommitteeMember(
    name: name,
    constituency: constituency,
    role: role,
    party: party,
    attended: attended,
  );
}

bool _looksLikeMinisterialRole(String value) {
  final v = value.toLowerCase();
  return v.contains('minister') ||
      v.contains('treasury') ||
      v.contains('secretary') ||
      v.contains('whip') ||
      v.contains('attorney') ||
      v.contains('advocate') ||
      v.contains('commissioner');
}
