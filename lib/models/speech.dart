/// A single speech contribution made by a Member during a Parliamentary sitting.
class Speech {
  final String id;
  final String debateId;
  final String debateTitle;

  /// The top-level Hansard section root this speech was fetched under.
  ///
  /// [debateId] identifies the innermost (possibly nested) debate node, which
  /// is often not itself a root of the day's section tree — e.g. a topical
  /// question under "Oral Answers to Questions". This field records the root,
  /// so speeches can be grouped per root debate without relying on document
  /// order. `null` on rows cached before the column existed.
  final String? rootDebateId;
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
    this.rootDebateId,
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
    String? rootDebateId,
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
      rootDebateId: rootDebateId,
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
      rootDebateId: row['root_debate_id'] as String?,
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
        'root_debate_id': rootDebateId,
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

  /// True for the boilerplate "The House met at …" / "The Committee met at …"
  /// procedural opener that normally fills its own one-speech debate.
  bool get isSittingStartAnnouncement {
    final lower = speechText.trim().toLowerCase();
    if (lower.length > 200) return false;
    if (!lower.startsWith('the ')) return false;
    if (!lower.contains(' met at ')) return false;
    return RegExp(r'^the\s+(house|lords|committee|grand\s+committee)\b')
        .hasMatch(lower);
  }

  /// Parses the clock time embedded in a sitting-start announcement and
  /// returns it as seconds-since-midnight.
  int? get sittingStartSeconds {
    if (!isSittingStartAnnouncement) return null;
    final lower = speechText.trim().toLowerCase();
    final numericMatch = RegExp(
            r'(\d{1,2})[.:](\d{2})\s*(a\.?m\.?|p\.?m\.?)?')
        .firstMatch(lower);
    if (numericMatch != null) {
      var hour = int.parse(numericMatch.group(1)!);
      final minute = int.parse(numericMatch.group(2)!);
      final ampm = numericMatch.group(3)?.replaceAll('.', '');
      if (ampm != null) {
        final pm = ampm.startsWith('p');
        if (pm && hour < 12) hour += 12;
        if (!pm && hour == 12) hour = 0;
      }
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return hour * 3600 + minute * 60;
    }

    return _parseWordClockTime(lower);
  }

  int? _parseWordClockTime(String lower) {
    final normalized = lower.replaceAll('\u2019', "'");

    if (RegExp(r'\b(noon|midday)\b').hasMatch(normalized)) {
      return 12 * 3600;
    }
    if (RegExp(r'\bmidnight\b').hasMatch(normalized)) {
      return 0;
    }

    final halfPast = RegExp(r'\bhalf[-\s]past\s+([a-z]+)\b')
        .firstMatch(normalized);
    if (halfPast != null) {
      final hour = _wordToHour(halfPast.group(1));
      if (hour != null) return hour * 3600 + 30 * 60;
    }

    final quarterPast =
        RegExp(r'\bquarter\s+past\s+([a-z]+)\b').firstMatch(normalized);
    if (quarterPast != null) {
      final hour = _wordToHour(quarterPast.group(1));
      if (hour != null) return hour * 3600 + 15 * 60;
    }

    final quarterTo =
        RegExp(r'\bquarter\s+to\s+([a-z]+)\b').firstMatch(normalized);
    if (quarterTo != null) {
      final hour = _wordToHour(quarterTo.group(1));
      if (hour != null) {
        final adjusted = (hour + 23) % 24;
        return adjusted * 3600 + 45 * 60;
      }
    }

    final oclock =
        RegExp(r"\b([a-z]+)\s+o'?clock\b").firstMatch(normalized);
    if (oclock != null) {
      final hour = _wordToHour(oclock.group(1));
      if (hour != null) return hour * 3600;
    }

    final wordAmPm = RegExp(r'\b([a-z]+)\s*(a\.?m\.?|p\.?m\.?)\b')
        .firstMatch(normalized);
    if (wordAmPm != null) {
      var hour = _wordToHour(wordAmPm.group(1));
      if (hour != null) {
        final ampm = wordAmPm.group(2)?.replaceAll('.', '');
        if (ampm != null) {
          final pm = ampm.startsWith('p');
          if (pm && hour < 12) hour += 12;
          if (!pm && hour == 12) hour = 0;
        }
        return hour * 3600;
      }
    }

    return null;
  }

  int? _wordToHour(String? word) {
    if (word == null) return null;
    final key = word.replaceAll(RegExp(r'[^a-z]'), '');
    const hours = <String, int>{
      'one': 1,
      'two': 2,
      'three': 3,
      'four': 4,
      'five': 5,
      'six': 6,
      'seven': 7,
      'eight': 8,
      'nine': 9,
      'ten': 10,
      'eleven': 11,
      'twelve': 12,
    };
    return hours[key];
  }

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
