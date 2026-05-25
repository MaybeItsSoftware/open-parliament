import '../models/member.dart';
import 'party_tokens.dart';

/// Indexes a list of [Member]s for fast name-based matching, optionally biased
/// by a party hint. Used by the transcript speaker resolver to match Hansard's
/// "Right hon. Sir Jane Smith (Lab)" attribution strings to a real [Member].
class MemberLookupIndex {
  final List<MemberCandidate> _candidates;
  final Map<String, List<MemberCandidate>> _exactByNormalizedName;
  final Map<int, MemberCandidate> _byId;

  MemberLookupIndex(List<Member> members)
      : _candidates = members.map(MemberCandidate.fromMember).toList(),
        _exactByNormalizedName = {},
        _byId = {} {
    for (final candidate in _candidates) {
      _byId[candidate.member.id] = candidate;
      _exactByNormalizedName
          .putIfAbsent(candidate.normalizedName, () => <MemberCandidate>[])
          .add(candidate);
    }
  }

  Member? memberById(int memberId) => _byId[memberId]?.member;

  /// Exact name match (after normalisation): returns the first candidate whose
  /// normalised name equals any of [nameCandidates], preferring [partyHint]
  /// if multiple members share a name.
  Member? matchExact(List<String> nameCandidates, {String? partyHint}) {
    for (final raw in nameCandidates) {
      final normalized = MemberCandidate.normalizeName(raw);
      if (normalized.isEmpty) continue;
      final exactMatches = _exactByNormalizedName[normalized];
      if (exactMatches != null && exactMatches.isNotEmpty) {
        return _pickByParty(exactMatches, partyHint).member;
      }
    }
    return null;
  }

  /// Fuzzy name match by token overlap. Returns the highest-scoring candidate
  /// with overlap >= 0.67. Below 0.9, the [partyHint] (if any) must agree.
  Member? matchFuzzy(List<String> nameCandidates, {String? partyHint}) {
    MemberCandidate? best;
    double bestScore = 0;
    for (final raw in nameCandidates) {
      final probe = MemberCandidate.normalizeName(raw);
      if (probe.isEmpty) continue;
      final probeTokens = probe.split(' ').where((t) => t.isNotEmpty).toSet();
      if (probeTokens.isEmpty) continue;

      for (final candidate in _candidates) {
        final score = _tokenOverlap(probeTokens, candidate.tokens);
        if (score > bestScore) {
          bestScore = score;
          best = candidate;
        }
      }
    }

    if (best == null || bestScore < 0.67) return null;
    if (bestScore >= 0.9) return best.member;
    if (partyHint == null || best.partyToken == null) return best.member;
    if (partyHint == best.partyToken) return best.member;
    return null;
  }

  MemberCandidate _pickByParty(List<MemberCandidate> options, String? party) {
    if (party == null) return options.first;
    for (final option in options) {
      if (option.partyToken == party) return option;
    }
    return options.first;
  }

  double _tokenOverlap(Set<String> a, Set<String> b) {
    if (a.isEmpty || b.isEmpty) return 0;
    final intersection = a.intersection(b).length.toDouble();
    return intersection / a.length;
  }
}

/// A pre-indexed [Member] with the data needed for fast name/party matching.
class MemberCandidate {
  final Member member;
  final String normalizedName;
  final Set<String> tokens;
  final String? partyToken;

  MemberCandidate({
    required this.member,
    required this.normalizedName,
    required this.tokens,
    required this.partyToken,
  });

  factory MemberCandidate.fromMember(Member member) {
    final normalized = normalizeName(member.name);
    final tokens = normalized.split(' ').where((t) => t.isNotEmpty).toSet();
    return MemberCandidate(
      member: member,
      normalizedName: normalized,
      tokens: tokens,
      partyToken: canonicalPartyToken(
        member.partyAbbreviation.isNotEmpty
            ? member.partyAbbreviation
            : member.party,
      ),
    );
  }

  static const _honorifics = {
    'rt',
    'hon',
    'right',
    'sir',
    'dame',
    'dr',
    'mr',
    'mrs',
    'ms',
    'prof',
    'lord',
    'lady',
    'baron',
    'baroness',
    'viscount',
    'viscountess',
    'earl',
    'countess',
    'duke',
    'duchess',
  };

  /// Lowercases, strips punctuation, drops common honorifics. The result is
  /// what's used for both exact and fuzzy matching.
  static String normalizeName(String raw) {
    final base = raw
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final stripped = base
        .split(' ')
        .where((t) => t.isNotEmpty && !_honorifics.contains(t))
        .join(' ');
    return stripped.isNotEmpty ? stripped : base;
  }
}
