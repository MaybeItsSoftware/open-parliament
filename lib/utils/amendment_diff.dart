/// Turns amendment-paper wording into a "diff" the UI can colour.
///
/// Amendments are written as editing instructions rather than as a patch:
/// `page 26, line 15, leave out “without” and insert “them or …”`. The quoted
/// spans are what changes, and the verb before each quote says how:
///
/// * `leave out “X”`         → X is deleted text
/// * `insert “Y”`            → Y is inserted text
/// * `after “X”`, `from “X”` → X is an anchor into the existing bill text
///
/// Inserted text often spans many printed lines (a whole new clause is one
/// long quotation), so the quote state is carried across lines.
library;

enum DiffOp {
  /// Instruction wording ("Clause 28, page 26, line 15, leave out").
  instruction,

  /// Existing bill text quoted only to locate the change.
  anchor,

  /// Text the amendment removes.
  deleted,

  /// Text the amendment adds.
  inserted,
}

class DiffSegment {
  final String text;
  final DiffOp op;

  /// True when the source marked this text bold (new-clause headings).
  final bool bold;

  const DiffSegment(this.text, this.op, {this.bold = false});

  @override
  String toString() => '${op.name}(${bold ? 'b:' : ''}$text)';
}

/// Strips the inline HTML and entities used in Bills API amendment lines and
/// Lords motion notes, keeping `<b>` as `\u0001…\u0002` markers so bold can
/// survive segmentation.
String cleanAmendmentHtml(String html) => html
    .replaceAll(RegExp(r'<\s*(b|strong)\s*>', caseSensitive: false), '\u0001')
    .replaceAll(RegExp(r'<\s*/\s*(b|strong)\s*>', caseSensitive: false), '\u0002')
    .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), ' ')
    .replaceAll(RegExp(r'<[^>]+>'), '')
    .replaceAll('&ldquo;', '“')
    .replaceAll('&rdquo;', '”')
    .replaceAll('&lsquo;', '‘')
    .replaceAll('&rsquo;', '’')
    .replaceAll('&mdash;', '—')
    .replaceAll('&ndash;', '–')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'[ \t]{2,}'), ' ')
    .trim();

/// Segments each of [lines] (already passed through [cleanAmendmentHtml] or
/// raw — both work) into instruction / anchor / deleted / inserted spans.
///
/// When [quotesAreInsertions] is true (new clauses and schedules), a quote
/// with no recognisable verb in front of it is treated as inserted text.
List<List<DiffSegment>> segmentAmendment(
  List<String> lines, {
  bool quotesAreInsertions = false,
}) {
  final out = <List<DiffSegment>>[];
  DiffOp? openOp; // non-null while inside a quotation
  var depth = 0; // nested “…” inside a quotation (inserted text quoting a term)
  var bold = false;
  final context = StringBuffer(); // instruction text since the last quote

  for (final raw in lines) {
    final line = raw.contains('<') || raw.contains('&')
        ? cleanAmendmentHtml(raw)
        : raw;
    final segs = <DiffSegment>[];
    final buf = StringBuffer();

    void flush() {
      if (buf.isEmpty) return;
      final op = openOp ?? DiffOp.instruction;
      final text = buf.toString();
      if (segs.isNotEmpty && segs.last.op == op && segs.last.bold == bold) {
        segs[segs.length - 1] = DiffSegment(segs.last.text + text, op, bold: bold);
      } else {
        segs.add(DiffSegment(text, op, bold: bold));
      }
      buf.clear();
    }

    for (final ch in line.split('')) {
      switch (ch) {
        case '\u0001':
          flush();
          bold = true;
        case '\u0002':
          flush();
          bold = false;
        case '“' when openOp == null:
          buf.write(ch);
          flush();
          openOp = _opFor(context.toString(), quotesAreInsertions);
          context.clear();
        case '“':
          depth++;
          buf.write(ch);
        case '”' when openOp != null && depth > 0:
          depth--;
          buf.write(ch);
        case '”' when openOp != null:
          flush();
          openOp = null;
          buf.write(ch);
        default:
          buf.write(ch);
          if (openOp == null) context.write(ch);
      }
    }
    flush();
    if (openOp == null) context.write(' ');
    out.add(segs);
  }
  return out;
}

DiffOp _opFor(String before, bool quotesAreInsertions) {
  final t = before.toLowerCase().replaceAll(RegExp(r'[\s—–:,-]+$'), '').trimRight();
  if (RegExp(r'(insert|substitute|add|insert the following|following)$').hasMatch(t)) {
    return DiffOp.inserted;
  }
  // "for “X” substitute “Y”" — X is the text being replaced.
  if (RegExp(r'(leave out|omit|\bfor)$').hasMatch(t)) return DiffOp.deleted;
  if (RegExp(r'\b(after|before|from|to|of|word|words)$').hasMatch(t)) {
    return DiffOp.anchor;
  }
  return quotesAreInsertions ? DiffOp.inserted : DiffOp.anchor;
}
