/// A top-level debate section within a sitting day (e.g. "Oral Answers to Questions").
class Debate {
  final String id;
  final String title;
  final String house;
  final int orderIndex;

  const Debate({
    required this.id,
    required this.title,
    required this.house,
    required this.orderIndex,
  });

  /// Parses a debate from the Hansard sittings API JSON response.
  factory Debate.fromApiJson(Map<String, dynamic> json, {int orderIndex = 0}) {
    return Debate(
      id: (json['ExternalId'] as String?) ??
          (json['externalId'] as String?) ??
          '',
      title: (json['Title'] as String?) ??
          (json['title'] as String?) ??
          'Unknown',
      house: (json['House'] as String?) ??
          (json['house'] as String?) ??
          'Commons',
      orderIndex: orderIndex,
    );
  }

  /// Restores a [Debate] from a SQLite row map.
  factory Debate.fromDb(Map<String, dynamic> row) {
    return Debate(
      id: (row['id'] as String?) ?? '',
      title: (row['title'] as String?) ?? '',
      house: (row['house'] as String?) ?? 'Commons',
      orderIndex: (row['order_idx'] as int?) ?? 0,
    );
  }

  /// Serialises this debate for insertion into SQLite.
  Map<String, dynamic> toDb() => {
        'id': id,
        'title': title,
        'house': house,
        'order_idx': orderIndex,
      };

  @override
  bool operator ==(Object other) => other is Debate && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Debate($id, $title)';
}
