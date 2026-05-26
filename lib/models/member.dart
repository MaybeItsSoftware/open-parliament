/// Represents a UK Member of Parliament (or Lord) with party affiliation and portrait.
class Member {
  final int id;
  final String name;
  final String party;
  final String partyAbbreviation;
  final String? thumbnailUrl;

  /// Commons constituency the member represents (`membershipFrom`), or empty
  /// for Lords / members without a current seat. Used to colour the national
  /// constituency map by the sitting MP's party.
  final String constituency;

  const Member({
    required this.id,
    required this.name,
    required this.party,
    required this.partyAbbreviation,
    this.thumbnailUrl,
    this.constituency = '',
  });

  /// Parses a member from the Parliament Members API JSON response.
  ///
  /// The Members API wraps each item in a `value` object:
  /// ```json
  /// { "value": { "id": 172, "nameDisplayAs": "...", "latestParty": {...} } }
  /// ```
  factory Member.fromApiJson(Map<String, dynamic> json) {
    final value = (json['value'] as Map<String, dynamic>?) ?? json;
    final latestParty = (value['latestParty'] as Map<String, dynamic>?) ?? {};
    final membership =
        (value['latestHouseMembership'] as Map<String, dynamic>?) ?? {};
    // membershipFrom is the constituency for Commons MPs (house == 1) and a
    // descriptive string for peers ("Life peer"); only keep it for the Commons.
    final house = (membership['house'] as num?)?.toInt();
    final membershipFrom = (membership['membershipFrom'] as String?) ?? '';
    return Member(
      id: (value['id'] as num).toInt(),
      name: (value['nameDisplayAs'] as String?) ?? '',
      party: (latestParty['name'] as String?) ?? '',
      partyAbbreviation: (latestParty['abbreviation'] as String?) ?? '',
      thumbnailUrl: value['thumbnailUrl'] as String?,
      constituency: house == 1 ? membershipFrom : '',
    );
  }

  /// Restores a [Member] from a SQLite row map.
  factory Member.fromDb(Map<String, dynamic> row) {
    return Member(
      id: row['id'] as int,
      name: (row['name'] as String?) ?? '',
      party: (row['party'] as String?) ?? '',
      partyAbbreviation: (row['party_abbreviation'] as String?) ?? '',
      thumbnailUrl: row['thumbnail_url'] as String?,
      constituency: (row['constituency'] as String?) ?? '',
    );
  }

  /// Serialises this member for insertion into SQLite.
  Map<String, dynamic> toDb() => {
        'id': id,
        'name': name,
        'party': party,
        'party_abbreviation': partyAbbreviation,
        'thumbnail_url': thumbnailUrl,
        'constituency': constituency,
      };

  @override
  bool operator ==(Object other) => other is Member && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Member($id, $name, $party)';
}
