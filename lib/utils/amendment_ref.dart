/// Pure helpers that work out which bill amendment a division was about, from
/// the division title (Commons) or the motion notes (Lords).
library;

/// A pointer from a division to an amendment on the amendment paper.
class AmendmentRef {
  /// Bill short title as written in the division title, e.g.
  /// `Sporting Events Bill [Lords]`.
  final String billTitle;

  /// The number as printed on the paper: `"48"`, `"NC62"`, `"NS3"`, `"16A"`.
  /// Null when the division was on a bill but not on a numbered amendment.
  final String? number;

  /// "report" / "committee" when the title names the stage.
  final String? stageHint;

  /// True for Commons votes on "Lords Amendment N" — those are renumbered in
  /// a separate paper that the Bills API does not expose.
  final bool isLordsAmendment;

  const AmendmentRef({
    required this.billTitle,
    this.number,
    this.stageHint,
    this.isLordsAmendment = false,
  });
}

final _stageSuffix = RegExp(
  r'\s+(report stage|report|committee stage|committee of the whole house|committee)\s*$',
  caseSensitive: false,
);
final _numbered = RegExp(
  r'^(new clause|new schedule|amendment)s?\s+(\d+[A-Z]*)\b',
  caseSensitive: false,
);
final _lordsAmendment =
    RegExp(r'(lords amendment)s?\s+(\d+[A-Z]*)\b', caseSensitive: false);

/// Parses a Commons division title such as
/// "Immigration and Asylum Bill Report Stage: New Clause 62" or
/// `Sporting Events Bill [Lords] Report: Amendment 8`.
///
/// Returns null when the title is not about a bill amendment (second/third
/// readings, opposition days, SIs, budget resolutions).
AmendmentRef? parseCommonsDivisionTitle(String title) {
  final colon = title.indexOf(':');
  if (colon < 0) return null;
  var head = title.substring(0, colon).trim();
  final tail = title.substring(colon + 1).trim();

  // "motion to disagree with Lords Amendment 106" — the reference sits
  // mid-sentence, so search the whole tail for it.
  final m = _lordsAmendment.firstMatch(tail) ?? _numbered.firstMatch(tail);
  if (m == null) return null;
  final kind = m.group(1)!.toLowerCase();
  final n = m.group(2)!.toUpperCase();

  String? stageHint;
  final s = _stageSuffix.firstMatch(head);
  if (s != null) {
    stageHint =
        s.group(1)!.toLowerCase().startsWith('report') ? 'report' : 'committee';
    head = head.substring(0, s.start).trim();
  }
  if (!head.toLowerCase().contains('bill')) return null;

  final isLords = kind.startsWith('lords');
  return AmendmentRef(
    billTitle: head,
    // Same-day stages (programme motions) would otherwise sort first.
    stageHint: isLords ? 'lords amendments' : stageHint,
    isLordsAmendment: isLords,
    number: switch (kind) {
      'new clause' => 'NC$n',
      'new schedule' => 'NS$n',
      _ => n,
    },
  );
}

final _lordsMoved =
    RegExp(r'moved amendments?\s+(\d+[A-Z]*)\b', caseSensitive: false);

/// Pulls the amendment number out of Lords motion notes, e.g.
/// "Baroness X moved amendment 16, Schedule 2, page 71…" → "16".
String? parseLordsAmendmentNumber(String notes) =>
    _lordsMoved.firstMatch(notes)?.group(1)?.toUpperCase();

/// Reduces a bill title to a comparable key so a division title matches the
/// Bills API `shortTitle`: lower-cased, bracketed origin tags (`[Lords]`,
/// `[HL]`) dropped, curly apostrophes straightened, and the trailing "Bill"
/// or "Act 2026" removed — a bill is renamed once it gets Royal Assent.
String normaliseBillTitle(String title) => title
    .toLowerCase()
    .replaceAll(RegExp(r'\[[^\]]*\]'), '')
    .replaceAll(RegExp('[‘’]'), "'")
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .replaceFirst(RegExp(r'\s+(bill|act(\s+\d{4})?)$'), '');

/// Picks the Bills API stage(s) a division on [date] in [house] ("Commons" /
/// "Lords") could belong to: the house must match and one of the stage's
/// sittings must fall on that day. Stages whose description contains
/// [stageHint] sort first. Returns `(stageId, description)` pairs.
List<(int, String)> candidateStages(
  List<Map<String, dynamic>> stages, {
  required String house,
  required DateTime date,
  String? stageHint,
}) {
  final day = _ymd(date);
  final hits = <(int, String)>[];
  for (final stage in stages) {
    if ((stage['house'] as String?)?.toLowerCase() != house.toLowerCase()) {
      continue;
    }
    final sittings = (stage['stageSittings'] as List?) ?? const [];
    final sat = sittings.whereType<Map<String, dynamic>>().any((s) {
      final d = DateTime.tryParse((s['date'] as String?) ?? '');
      return d != null && _ymd(d) == day;
    });
    final id = (stage['id'] as num?)?.toInt();
    if (sat && id != null) {
      hits.add((id, (stage['description'] as String?) ?? ''));
    }
  }
  if (stageHint != null) {
    int rank((int, String) s) =>
        s.$2.toLowerCase().contains(stageHint) ? 0 : 1;
    hits.sort((a, b) => rank(a).compareTo(rank(b)));
  }
  return hits;
}

String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
