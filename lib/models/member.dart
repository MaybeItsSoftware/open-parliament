/// Represents a UK Member of Parliament (or Lord) with party affiliation and portrait.
class Member {
  final int id;
  final String name;
  final String party;
  final String partyAbbreviation;
  final String? thumbnailUrl;

  const Member({
    required this.id,
    required this.name,
    required this.party,
    required this.partyAbbreviation,
    this.thumbnailUrl,
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
    return Member(
      id: (value['id'] as num).toInt(),
      name: (value['nameDisplayAs'] as String?) ?? '',
      party: (latestParty['name'] as String?) ?? '',
      partyAbbreviation: (latestParty['abbreviation'] as String?) ?? '',
      thumbnailUrl: value['thumbnailUrl'] as String?,
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
    );
  }

  /// Serialises this member for insertion into SQLite.
  Map<String, dynamic> toDb() => {
        'id': id,
        'name': name,
        'party': party,
        'party_abbreviation': partyAbbreviation,
        'thumbnail_url': thumbnailUrl,
      };

  @override
  bool operator ==(Object other) => other is Member && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Member($id, $name, $party)';
}
