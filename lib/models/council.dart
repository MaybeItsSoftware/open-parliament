/// A local authority and its political makeup, sourced from OpenCouncilData.
class Council {
  final String name;

  /// Authority type, e.g. "District", "Unitary", "Metropolitan", "Scotland".
  final String type;

  /// Control string: a single party (`"LAB"`), a coalition (`"SNP/LD"`) or
  /// `"NOC"` for no overall control.
  final String control;

  /// Seat counts keyed by the table's party labels (`"Lab"`, `"Con"`,
  /// `"LibDem"`, `"Green"`, `"Reform"`, `"SNP"`, `"Plaid"`, `"Other"`,
  /// `"Vacant"`). Insertion order follows the source columns.
  final Map<String, int> seats;

  final int total;

  const Council({
    required this.name,
    required this.type,
    required this.control,
    required this.seats,
    required this.total,
  });

  /// Seats held by parties (excludes the "Vacant" bucket), largest first.
  List<MapEntry<String, int>> get heldSeats => seats.entries
      .where((e) => e.key.toLowerCase() != 'vacant' && e.value > 0)
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'control': control,
        'seats': seats,
        'total': total,
      };

  factory Council.fromJson(Map<String, dynamic> json) => Council(
        name: (json['name'] as String?) ?? '',
        type: (json['type'] as String?) ?? '',
        control: (json['control'] as String?) ?? '',
        seats: {
          for (final e in (json['seats'] as Map<String, dynamic>? ?? {}).entries)
            e.key: (e.value as num).toInt(),
        },
        total: (json['total'] as num?)?.toInt() ?? 0,
      );
}
