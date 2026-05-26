import '../models/council.dart';
import 'area_match.dart';
import 'party_tokens.dart';

/// Parses the OpenCouncilData "councils" table into [Council] records.
///
/// The page renders a header row of `<th>` labels (`Type | Council | Control |
/// Lab | Con | … | Total`) followed by one `<tr>` of `<td>` per council. We map
/// each data row's cells onto the header labels, which keeps us robust if the
/// seat columns change, and skip the trailing "Totals:" summary row.
List<Council> parseCouncils(String html) {
  final rowPattern = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
  final thPattern = RegExp(r'<th[^>]*>(.*?)</th>', dotAll: true);
  final tdPattern = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
  final tagPattern = RegExp(r'<[^>]+>');

  String clean(String s) =>
      _unescape(s.replaceAll(tagPattern, '')).trim();

  List<String>? headers;
  final councils = <Council>[];

  for (final row in rowPattern.allMatches(html)) {
    final inner = row.group(1)!;
    final ths = thPattern.allMatches(inner).map((m) => clean(m.group(1)!));
    if (ths.isNotEmpty) {
      headers ??= ths.toList();
      continue;
    }
    if (headers == null) continue;

    final cells =
        tdPattern.allMatches(inner).map((m) => clean(m.group(1)!)).toList();
    if (cells.length < headers.length) continue;

    final byHeader = <String, String>{
      for (var i = 0; i < headers.length; i++) headers[i]: cells[i],
    };
    final name = byHeader['Council'] ?? '';
    final rawControl = byHeader['Control'] ?? '';
    if (name.isEmpty) continue;
    final isCity = isCityOfLondonCouncil(name);
    final control = rawControl.isEmpty && isCity ? 'IND' : rawControl;
    if (control.isEmpty) continue;
    if (name.toLowerCase().startsWith('total')) continue;

    final seats = <String, int>{
      for (final h in headers)
        if (h != 'Type' && h != 'Council' && h != 'Control' && h != 'Total')
          h: int.tryParse(byHeader[h] ?? '') ?? 0,
    };

    councils.add(Council(
      name: name,
      type: isCity ? 'Sui Generis' : (byHeader['Type'] ?? ''),
      control: control,
      seats: seats,
      total: int.tryParse(byHeader['Total'] ?? '') ?? 0,
    ));
  }
  return councils;
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#039;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ')
    .trim();

/// Resolves a control string to a canonical party token for colouring, or
/// `null` when there is no single controlling party (e.g. "NOC", "TBC", or a
/// local party with no brand colour). Coalitions are coloured by their leading
/// party — the first segment of e.g. `"SNP/LD"`.
String? councilControlToken(String control) {
  final lead = _stripAnnotations(control.split('/').first);
  if (lead.toUpperCase() == 'NOC') return null;
  return canonicalPartyToken(lead);
}

/// Human-readable control label, e.g. `"SNP/LD"` → "SNP / Lib Dem", `"LABmin"`
/// → "Labour (minority)", `"NOC"` → "No overall control".
String controlDisplayName(String control) {
  if (control.toUpperCase().contains('NOC')) return 'No overall control';
  final minority = RegExp(r'min$').hasMatch(control);
  final parts = control
      .split('/')
      .map((p) => _partyDisplayName(_stripAnnotations(p)))
      .where((p) => p.isNotEmpty);
  final label = parts.join(' / ');
  return minority ? '$label (minority)' : label;
}

String _stripAnnotations(String code) => code
    .trim()
    .replaceAll(RegExp(r'\(.*?\)'), '')
    .replaceAll(RegExp(r'(min|Mayor)$'), '')
    .trim();

String _partyDisplayName(String code) {
  switch (canonicalPartyToken(code)) {
    case 'labour':
      return 'Labour';
    case 'conservative':
      return 'Conservative';
    case 'libdem':
      return 'Lib Dem';
    case 'green':
      return 'Green';
    case 'snp':
      return 'SNP';
    case 'plaidcymru':
      return 'Plaid Cymru';
    case 'reform':
      return 'Reform';
    case 'independent':
      return 'Independent';
    default:
      return code; // local/unknown party: show the raw code
  }
}
