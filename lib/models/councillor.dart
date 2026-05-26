enum CouncillorRole { councillor, commonCouncillor, alderman }

/// A single elected councillor, sourced from OpenCouncilData's free annual
/// councillors CSV (name, ward, party). Contact details live behind their paid
/// "Communications" dataset and are intentionally not modelled here.
class Councillor {
  /// The council name as it appears in the CSV (e.g. "Cambridgeshire").
  final String council;

  /// The ward the councillor represents (e.g. "Trumpington").
  final String ward;

  final String name;

  /// Full party name from the CSV (e.g. "Liberal Democrats"). Feed through
  /// `canonicalPartyToken` for colours.
  final String party;

  /// Electoral Commission party code (e.g. "PP90"), or empty if absent.
  final String partyCode;

  /// Date of the ward's next scheduled election, or null if unparseable.
  final DateTime? nextElection;

  /// Role within the authority (used for City of London exceptions).
  final CouncillorRole role;

  /// Bodies the councillor sits on (e.g. Court of Aldermen).
  final List<String> memberships;

  /// The typical term length in years, if known.
  final int? termYears;

  /// Whether the role is salaried/allowanced; null when unknown.
  final bool? isPaid;

  const Councillor({
    required this.council,
    required this.ward,
    required this.name,
    required this.party,
    required this.partyCode,
    this.nextElection,
    this.role = CouncillorRole.councillor,
    this.memberships = const [],
    this.termYears,
    this.isPaid,
  });

  String get roleLabel => switch (role) {
        CouncillorRole.alderman => 'Alderman',
        CouncillorRole.commonCouncillor => 'Common Councillor',
        CouncillorRole.councillor => 'Councillor',
      };

  Map<String, dynamic> toJson() => {
        'council': council,
        'ward': ward,
        'name': name,
        'party': party,
        'partyCode': partyCode,
        'nextElection': nextElection?.toIso8601String(),
        'role': _roleToString(role),
        'memberships': memberships,
        'termYears': termYears,
        'isPaid': isPaid,
      };

  factory Councillor.fromJson(Map<String, dynamic> json) => Councillor(
        council: (json['council'] as String?) ?? '',
        ward: (json['ward'] as String?) ?? '',
        name: (json['name'] as String?) ?? '',
        party: (json['party'] as String?) ?? '',
        partyCode: (json['partyCode'] as String?) ?? '',
        nextElection: DateTime.tryParse((json['nextElection'] as String?) ?? ''),
        role: _roleFromString(json['role'] as String?),
        memberships: (json['memberships'] as List<dynamic>? ?? const [])
            .whereType<String>()
            .toList(),
        termYears: (json['termYears'] as num?)?.toInt(),
        isPaid: json['isPaid'] as bool?,
      );
}

String _roleToString(CouncillorRole role) => switch (role) {
      CouncillorRole.alderman => 'alderman',
      CouncillorRole.commonCouncillor => 'common_councillor',
      CouncillorRole.councillor => 'councillor',
    };

CouncillorRole _roleFromString(String? value) => switch (value) {
      'alderman' => CouncillorRole.alderman,
      'common_councillor' => CouncillorRole.commonCouncillor,
      _ => CouncillorRole.councillor,
    };
