/// One spoken Hansard contribution by a member, from
/// `/search/contributions/Spoken.json`.
class MemberContribution {
  /// Hansard `ItemId` — the same id the transcript gives this speech
  /// (`Speech.id`), so the transcript can scroll straight to it.
  final String speechId;

  /// Title of the (sub-)debate the speech was made in, e.g. "Engagements".
  final String debateTitle;

  /// Hansard external id of that (sub-)debate. The transcript narrows to it.
  final String debateSectionId;
  final DateTime sittingDate;

  /// "Commons" or "Lords".
  final String house;

  /// Where in the House: "Commons Chamber", "Westminster Hall", "Lords
  /// Chamber", "Grand Committee", …
  final String section;
  final String text;

  const MemberContribution({
    required this.speechId,
    required this.debateTitle,
    required this.debateSectionId,
    required this.sittingDate,
    required this.house,
    required this.section,
    required this.text,
  });

  factory MemberContribution.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['SittingDate'] as String?) ?? '';
    final date = DateTime.tryParse(rawDate) ?? DateTime(1970);
    final full = (json['ContributionTextFull'] as String?)?.trim() ?? '';
    final rawText =
        full.isNotEmpty ? full : (json['ContributionText'] as String?) ?? '';
    return MemberContribution(
      speechId: json['ItemId']?.toString() ?? '',
      debateTitle: ((json['DebateSection'] as String?) ?? '').trim(),
      debateSectionId: (json['DebateSectionExtId'] as String?) ?? '',
      sittingDate: DateTime(date.year, date.month, date.day),
      house: (json['House'] as String?) ?? '',
      section: (json['Section'] as String?) ?? '',
      text: _stripHtml(rawText),
    );
  }

  /// "Westminster Hall" / "Lords Chamber" — the venue line under the title,
  /// falling back to the House.
  String get venue => section.isNotEmpty ? section : house;

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&mdash;', '—')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
}

/// Parses raw contribution search results, skipping malformed rows and rows
/// with no debate title (nothing to show or open).
List<MemberContribution> parseMemberContributions(
  Iterable<Map<String, dynamic>> raw,
) {
  final out = <MemberContribution>[];
  for (final json in raw) {
    try {
      final c = MemberContribution.fromJson(json);
      if (c.debateTitle.isNotEmpty) out.add(c);
    } catch (_) {
      // Skip a malformed row rather than lose the page.
    }
  }
  return out;
}
