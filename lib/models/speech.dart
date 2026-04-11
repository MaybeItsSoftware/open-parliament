/// A single speech contribution made by a Member during a Parliamentary sitting.
class Speech {
  final String id;
  final String debateId;
  final String debateTitle;
  final int? memberId;
  final String memberName;
  final String attributedTo;
  final String speechText;
  final String? timecode;
  final int orderIndex;

  const Speech({
    required this.id,
    required this.debateId,
    required this.debateTitle,
    this.memberId,
    required this.memberName,
    required this.attributedTo,
    required this.speechText,
    this.timecode,
    required this.orderIndex,
  });

  /// Parses a speech from the Hansard debates API JSON response.
  ///
  /// The `Value` field may contain HTML markup which is stripped to plain text.
  factory Speech.fromApiJson(
    Map<String, dynamic> json, {
    required String debateId,
    required String debateTitle,
    required int orderIndex,
  }) {
    final attribution = _asString(json['AttributedTo']) ??
        _asString(json['attributedTo']) ??
        '';
    final memberName = _asString(json['MemberName']) ??
        _asString(json['memberName']) ??
        attribution.split('(').first.trim();
    final rawMemberId = json['MemberId'] ?? json['memberId'];
    final rawText = _asString(json['Value']) ?? _asString(json['value']) ?? '';
    final parsedMemberId = _asInt(rawMemberId);

    return Speech(
      id: _asString(json['ItemId']) ??
          _asString(json['id']) ??
          '${debateId}_$orderIndex',
      debateId: debateId,
      debateTitle: debateTitle,
      memberId: parsedMemberId,
      memberName: memberName,
      attributedTo: attribution,
      speechText: _stripHtml(rawText),
      timecode: _asString(json['Timecode']) ?? _asString(json['timecode']),
      orderIndex: orderIndex,
    );
  }

  /// Restores a [Speech] from a SQLite row map.
  factory Speech.fromDb(Map<String, dynamic> row) {
    return Speech(
      id: (row['id'] as String?) ?? '',
      debateId: (row['debate_id'] as String?) ?? '',
      debateTitle: (row['debate_title'] as String?) ?? '',
      memberId: row['member_id'] as int?,
      memberName: (row['member_name'] as String?) ?? '',
      attributedTo: (row['attributed_to'] as String?) ?? '',
      speechText: (row['speech_text'] as String?) ?? '',
      timecode: row['timecode'] as String?,
      orderIndex: (row['order_idx'] as int?) ?? 0,
    );
  }

  /// Serialises this speech for insertion into SQLite.
  Map<String, dynamic> toDb() => {
        'id': id,
        'debate_id': debateId,
        'debate_title': debateTitle,
        'member_id': memberId,
        'member_name': memberName,
        'attributed_to': attributedTo,
        'speech_text': speechText,
        'timecode': timecode,
        'order_idx': orderIndex,
      };

  /// Strips basic HTML tags and decodes common HTML entities to plain text.
  static String _stripHtml(String html) {
    final text = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    return text;
  }

  static String? _asString(dynamic value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  @override
  bool operator ==(Object other) => other is Speech && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Speech($id, $memberName)';
}
