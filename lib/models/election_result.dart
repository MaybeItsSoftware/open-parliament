/// A general-election result for a Westminster constituency, sourced from the
/// Parliament Members API (`.../Location/Constituency/{id}/ElectionResult`).
///
/// Every GB seat was redrawn in the July 2024 boundary review, so the API holds
/// only the latest election for the current constituency IDs — this models that
/// single result, not a cross-election history.
class ConstituencyElectionResult {
  /// e.g. "2024 General Election".
  final String electionTitle;
  final DateTime? electionDate;

  /// Outcome string, e.g. "Lab Hold", "Ind Gain", "Con Win".
  final String result;

  final int majority;
  final int turnout;
  final int electorate;

  /// Candidates ordered by [ElectionCandidate.rankOrder] (winner first).
  final List<ElectionCandidate> candidates;

  const ConstituencyElectionResult({
    required this.electionTitle,
    required this.electionDate,
    required this.result,
    required this.majority,
    required this.turnout,
    required this.electorate,
    required this.candidates,
  });

  /// The total votes cast across all candidates, used to size vote-share bars.
  int get totalVotes =>
      candidates.fold<int>(0, (sum, c) => sum + c.votes);

  /// Parses the API payload, accepting both the `{ "value": {...} }` envelope
  /// the Members API uses and a bare object.
  factory ConstituencyElectionResult.fromJson(Map<String, dynamic> json) {
    final value = (json['value'] as Map<String, dynamic>?) ?? json;
    final rawDate = value['electionDate'] as String?;
    final candidates = ((value['candidates'] as List<dynamic>?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ElectionCandidate.fromJson)
        .toList()
      ..sort((a, b) => a.rankOrder.compareTo(b.rankOrder));

    return ConstituencyElectionResult(
      electionTitle: (value['electionTitle'] as String?) ?? '',
      electionDate: rawDate != null ? DateTime.tryParse(rawDate) : null,
      result: (value['result'] as String?) ?? '',
      majority: (value['majority'] as num?)?.toInt() ?? 0,
      turnout: (value['turnout'] as num?)?.toInt() ?? 0,
      electorate: (value['electorate'] as num?)?.toInt() ?? 0,
      candidates: candidates,
    );
  }
}

/// A single candidate's result within a [ConstituencyElectionResult].
class ElectionCandidate {
  final String name;
  final String party;
  final String partyAbbreviation;
  final int votes;

  /// Share of the vote as a percentage (e.g. 49.2).
  final double voteShare;

  /// 1 = winner, 2 = runner-up, …
  final int rankOrder;

  /// Change vs the previous election (e.g. "-29.9"); empty for new candidates.
  final String resultChange;

  const ElectionCandidate({
    required this.name,
    required this.party,
    required this.partyAbbreviation,
    required this.votes,
    required this.voteShare,
    required this.rankOrder,
    required this.resultChange,
  });

  bool get isWinner => rankOrder == 1;

  factory ElectionCandidate.fromJson(Map<String, dynamic> json) {
    final party = (json['party'] as Map<String, dynamic>?) ?? const {};
    return ElectionCandidate(
      name: (json['name'] as String?) ?? '',
      party: (party['name'] as String?) ?? '',
      partyAbbreviation: (party['abbreviation'] as String?) ?? '',
      votes: (json['votes'] as num?)?.toInt() ?? 0,
      voteShare: (json['voteShare'] as num?)?.toDouble() ?? 0,
      rankOrder: (json['rankOrder'] as num?)?.toInt() ?? 0,
      resultChange: (json['resultChange'] as String?) ?? '',
    );
  }
}
