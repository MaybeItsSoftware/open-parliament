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
    final attribution = (json['AttributedTo'] as String?) ??
        (json['attributedTo'] as String?) ??
        '';
    final memberName = (json['MemberName'] as String?) ??
        (json['memberName'] as String?) ??
        attribution.split('(').first.trim();
    final rawMemberId = json['MemberId'] ?? json['memberId'];

    final rawText =
        (json['Value'] as String?) ?? (json['value'] as String?) ?? '';

    return Speech(
      id: (json['ItemId'] as String?) ??
          (json['id'] as String?) ??
          '${debateId}_$orderIndex',
      debateId: debateId,
      debateTitle: debateTitle,
      memberId:
          rawMemberId != null ? (rawMemberId as num).toInt() : null,
      memberName: memberName,
      attributedTo: attribution,
      speechText: _stripHtml(rawText),
      timecode:
          (json['Timecode'] as String?) ?? (json['timecode'] as String?),
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

  @override
  bool operator ==(Object other) => other is Speech && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Speech($id, $memberName)';
}
