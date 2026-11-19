/// One printed line of an amendment, as laid out on the amendment paper.
class AmendmentLine {
  /// Raw line text. May contain simple inline HTML (`<b>`, `<i>`).
  final String text;

  /// Nesting depth (0 = the instruction, 1 = clause body, 2 = paragraph, …).
  final int indentation;

  /// Hanging label such as `(1)` or `(a)`, printed before the text.
  final String? hangingIndentation;

  const AmendmentLine({
    required this.text,
    this.indentation = 0,
    this.hangingIndentation,
  });

  factory AmendmentLine.fromJson(Map<String, dynamic> json) => AmendmentLine(
        text: (json['text'] as String?) ?? '',
        indentation: (json['indentation'] as num?)?.toInt() ?? 0,
        hangingIndentation: json['hangingIndentation'] as String?,
      );
}

/// What an amendment does to the bill, from the Bills API `amendmentType`.
enum AmendmentKind { edit, addClause, deleteClause, other }

/// A bill amendment from the Bills API (`/Bills/{id}/Stages/{id}/Amendments`).
class Amendment {
  final int amendmentId;

  /// The number printed on the paper: `"48"`, `"NC62"`, `"NS3"`, `"16A"`.
  final String number;
  final AmendmentKind kind;

  /// API decision token, e.g. `Agreed`, `Negatived`, `NoDecision`.
  final String decision;
  final String? decisionExplanation;

  /// The sponsor's "explanatory statement": a plain-English summary of
  /// what the amendment would do. May contain HTML.
  final String? explanatoryText;
  final int? clause;
  final int? schedule;
  final int? page;
  final int? line;

  /// Sponsor names, lead sponsor first.
  final List<String> sponsors;
  final List<AmendmentLine> lines;

  const Amendment({
    required this.amendmentId,
    required this.number,
    required this.kind,
    required this.decision,
    this.decisionExplanation,
    this.explanatoryText,
    this.clause,
    this.schedule,
    this.page,
    this.line,
    this.sponsors = const [],
    this.lines = const [],
  });

  /// Parses either a list item (which only carries `summaryText`) or the
  /// detail record (which carries the full `amendmentLines`).
  factory Amendment.fromJson(Map<String, dynamic> json) {
    final rawLines = json['amendmentLines'];
    final lines = rawLines is List
        ? rawLines
            .whereType<Map<String, dynamic>>()
            .where((l) => l['isImage'] != true)
            .map(AmendmentLine.fromJson)
            .toList()
        : ((json['summaryText'] as List?) ?? const [])
            .whereType<String>()
            .map((t) => AmendmentLine(text: t))
            .toList();
    final sponsors = ((json['sponsors'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList()
      ..sort((a, b) => ((a['sortOrder'] as num?) ?? 0)
          .compareTo((b['sortOrder'] as num?) ?? 0));
    return Amendment(
      amendmentId: (json['amendmentId'] as num?)?.toInt() ?? 0,
      number: ((json['marshalledListText'] as String?) ?? '').trim(),
      kind: switch (json['amendmentType']) {
        'EditBillBody' => AmendmentKind.edit,
        'AddClauseOrSchedule' => AmendmentKind.addClause,
        'DeleteClauseOrSchedule' => AmendmentKind.deleteClause,
        _ => AmendmentKind.other,
      },
      decision: (json['decision'] as String?) ?? 'NoDecision',
      decisionExplanation: json['decisionExplanation'] as String?,
      explanatoryText: json['explanatoryText'] as String?,
      clause: (json['clause'] as num?)?.toInt(),
      schedule: (json['schedule'] as num?)?.toInt(),
      page: (json['pageNumber'] as num?)?.toInt(),
      line: (json['lineNumber'] as num?)?.toInt(),
      sponsors: [
        for (final s in sponsors)
          if ((s['name'] as String?)?.isNotEmpty ?? false) s['name'] as String,
      ],
      lines: lines,
    );
  }

  /// "Clause 28 · page 26 · line 15", or null for a new clause.
  String? get location {
    final parts = [
      if (clause != null) 'Clause $clause',
      if (schedule != null) 'Schedule $schedule',
      if (page != null) 'page $page',
      if (line != null) 'line $line',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// Human label for [decision] ("NoDecision" → null, since the API often
  /// lags the vote by days and "not considered" would read as wrong).
  String? get decisionLabel => switch (decision) {
        'NoDecision' => null,
        'Agreed' => 'Agreed',
        'Negatived' => 'Negatived',
        'Withdrawn' || 'WithdrawnBeforeDebate' => 'Withdrawn',
        'NotMoved' || 'NotCalledOrNotMoved' => 'Not moved',
        'NotSelected' => 'Not selected',
        'Disagreed' => 'Disagreed',
        _ => decision
            .replaceAllMapped(RegExp(r'(?<=[a-z])([A-Z])'), (m) => ' ${m[1]}'),
      };
}

/// Everything known about what a division was voting on.
class DivisionAmendment {
  /// The Lords' plain-text record of the motion ("Baroness X moved amendment
  /// 16, … to insert “…”"). Commons divisions have no equivalent.
  final String? motionText;

  /// The amendment being voted on, when it could be matched in the Bills API.
  final Amendment? amendment;

  /// e.g. "Report stage" — the bill stage the amendment was tabled at.
  final String? stageName;
  final int? billId;

  /// Why [amendment] is missing, shown in place of the text.
  final String? unavailableReason;

  const DivisionAmendment({
    this.motionText,
    this.amendment,
    this.stageName,
    this.billId,
    this.unavailableReason,
  });
}
