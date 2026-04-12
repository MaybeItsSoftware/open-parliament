/// A single speech contribution made by a Member during a Parliamentary sitting.
class Speech {
  final String id;
  final String debateId;
  final String debateTitle;
  final String itemType;
  final String hrsTag;
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
    this.itemType = 'Contribution',
    this.hrsTag = '',
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
    final itemType = _asString(json['ItemType']) ??
        _asString(json['itemType']) ??
        'Contribution';
    final hrsTag = _asString(json['HRSTag']) ?? _asString(json['hrsTag']) ?? '';
    final attribution = _asString(json['AttributedTo']) ??
        _asString(json['attributedTo']) ??
        '';
    final memberName = _asString(json['MemberName']) ??
        _asString(json['memberName']) ??
        attribution.split('(').first.trim();
    final rawMemberId = json['MemberId'] ?? json['memberId'];
    final rawText = _asString(json['Value']) ?? _asString(json['value']) ?? '';
    final parsedMemberId = _asInt(rawMemberId);
    final strippedText = _stripHtml(rawText);
    final rawTimecode =
        _asString(json['Timecode']) ?? _asString(json['timecode']);
    final effectiveTimecode = rawTimecode ??
        ((itemType.toLowerCase() == 'timestamp' && _isClockTime(strippedText))
            ? strippedText
            : null);

    return Speech(
      id: _asString(json['ItemId']) ??
          _asString(json['id']) ??
          '${debateId}_$orderIndex',
      debateId: debateId,
      debateTitle: debateTitle,
      itemType: itemType,
      hrsTag: hrsTag,
      memberId: parsedMemberId,
      memberName: memberName,
      attributedTo: attribution,
      speechText: strippedText,
      timecode: effectiveTimecode,
      orderIndex: orderIndex,
    );
  }

  /// Restores a [Speech] from a SQLite row map.
  factory Speech.fromDb(Map<String, dynamic> row) {
    return Speech(
      id: (row['id'] as String?) ?? '',
      debateId: (row['debate_id'] as String?) ?? '',
      debateTitle: (row['debate_title'] as String?) ?? '',
      itemType: (row['item_type'] as String?) ?? 'Contribution',
      hrsTag: (row['hrs_tag'] as String?) ?? '',
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
        'item_type': itemType,
        'hrs_tag': hrsTag,
        'member_id': memberId,
        'member_name': memberName,
        'attributed_to': attributedTo,
        'speech_text': speechText,
        'timecode': timecode,
        'order_idx': orderIndex,
      };

  /// True when the speech is attributed to a collective/anonymous entity
  /// rather than a named individual.
  bool get isCollectiveSpeaker {
    final a = attributedTo.trim();
    if (a.isEmpty) return false;
    return a == 'Hon. Members' ||
        a == 'Opposition Members' ||
        a == 'Government Members' ||
        a == 'Noble Lords' ||
        a.startsWith('An hon. Member') ||
        a.startsWith('Several hon. Members') ||
        a.startsWith('A noble Lord') ||
        a.startsWith('Noble Lords');
  }

  /// True when this is a Prayers debate entry (title is "Prayers").
  bool get isPrayers => debateTitle.trim().toLowerCase() == 'prayers';

  /// True when the text marks a procedural event (verbal vote outcome,
  /// question put, etc.) without being a named speech.
  bool get isEventTag {
    if (hasNamedSpeaker && !isCollectiveSpeaker) return false;
    final t = speechText.trim();
    return t.startsWith('Question put') ||
        t.startsWith('Question agreed') ||
        t.startsWith('Motion made') ||
        t.endsWith('agreed to.') ||
        t.endsWith('negatived.') ||
        t.endsWith('disagreed to.') ||
        (t.startsWith('The ') && t.endsWith('was asked—'));
  }

  /// Extracts the name from a "[Name in the Chair]" procedural line, or null.
  String? get inChairName {
    final match =
        RegExp(r'^\[(.+?)\s+in\s+the\s+[Cc]hair\]$').firstMatch(speechText.trim());
    return match?.group(1)?.trim();
  }

  /// True when the speech text is a stage direction / action (e.g. "rose—").
  ///
  /// These are attributed to a member but describe a physical action rather
  /// than spoken words. They end with an em-dash and are very short.
  bool get isAction {
    final t = speechText.trim();
    if (t.isEmpty) return false;
    if (!t.endsWith('—')) return false;
    // Must be short — real speeches don't end mid-sentence with an em-dash.
    if (t.length > 80) return false;
    return true;
  }

  /// True when the speech text is a division (vote) result line.
  ///
  /// Format from the API: `index|time|ayes|noes|description|result||...`
  bool get isDivision {
    final t = speechText.trim();
    return RegExp(r'^\d+\|\d{1,2}:\d{2}').hasMatch(t);
  }

  bool get hasNamedSpeaker {
    if (memberId != null) return true;
    if (memberName.trim().isNotEmpty) return true;
    if (attributedTo.trim().isNotEmpty) return true;
    return false;
  }

  bool get isTimestamp {
    if (itemType.toLowerCase() == 'timestamp') return true;
    return !hasNamedSpeaker && _isClockTime(speechText);
  }

  bool get isDateHeading => hrsTag.toLowerCase() == 'hs_date';
  bool get isQuote => hrsTag.toLowerCase() == 'hs_quote';
  bool get isTabledBy => hrsTag.toLowerCase() == 'hs_tabledby';
  bool get isProcedureOutcome => hrsTag.toLowerCase() == 'hs_procedure';

  bool get isProceduralText => !isTimestamp && !hasNamedSpeaker;

  String? get displayTime {
    final source = (timecode ?? speechText).trim();
    if (!_isClockTime(source)) return null;
    final parts = source.split(':');
    if (parts.length < 2) return source;
    return '${parts[0]}:${parts[1]}';
  }

  /// Strips basic HTML tags and decodes common HTML entities to plain text.
  static String _stripHtml(String html) {
    final text = html
        .replaceAll(
          RegExp(
            r'<span[^>]*class\s*=\s*"column-number"[^>]*>.*?</span>',
            caseSensitive: false,
            dotAll: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&mdash;', '—')
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

  static bool _isClockTime(String value) =>
      RegExp(r'^\d{1,2}:\d{2}(:\d{2})?$').hasMatch(value.trim());

  @override
  bool operator ==(Object other) => other is Speech && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Speech($id, $memberName)';
}
