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
    case 'restorebritain':
      return 'Restore Britain';
    case 'independent':
      return 'Independent';
    default:
      return code; // local/unknown party: show the raw code
  }
}

const Set<String> _scottishCouncilNames = {
  'aberdeen', 'aberdeenshire', 'angus', 'argyll and bute', 'clackmannanshire',
  'dumfries and galloway', 'dundee', 'east ayrshire', 'east dunbartonshire',
  'east lothian', 'east renfrewshire', 'edinburgh', 'falkirk', 'fife',
  'glasgow', 'highland', 'inverclyde', 'midlothian', 'moray', 'north ayrshire',
  'north lanarkshire', 'orkney', 'perth and kinross', 'renfrewshire',
  'shetland', 'south ayrshire', 'south lanarkshire', 'stirling',
  'west dunbartonshire', 'west lothian', 'western isles', 'na h-eileanan siar'
};

const Set<String> _welshCouncilNames = {
  'blaenau gwent', 'bridgend', 'caerphilly', 'cardiff', 'carmarthenshire',
  'ceredigion', 'conwy', 'denbighshire', 'flintshire', 'gwynedd',
  'isle of anglesey', 'merthyr tydfil', 'monmouthshire', 'neath port talbot',
  'newport', 'pembrokeshire', 'powys', 'rhondda cynon taf', 'swansea',
  'torfaen', 'vale of glamorgan', 'wrexham', 'ynys mon'
};

List<Council> parseHistoricalCouncils16(String html) {
  final rowPattern = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
  final tdPattern = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
  final spanPattern = RegExp(
    r'class="pop\s+([a-zA-Z0-9_-]+)"[^>]*>.*?(?:class="poptext"[^>]*>)?(\d+)',
    dotAll: true,
  );
  final tagPattern = RegExp(r'<[^>]+>');

  String clean(String s) => s.replaceAll(tagPattern, '').replaceAll('&nbsp;', ' ').trim();

  final councils = <Council>[];

  for (final row in rowPattern.allMatches(html)) {
    final inner = row.group(1)!;
    final cells = tdPattern.allMatches(inner).map((m) => m.group(1)!).toList();
    if (cells.length < 3) continue;

    final name = clean(cells[0]);
    if (name.isEmpty ||
        name.toLowerCase() == 'authority' ||
        name.toLowerCase().startsWith('total')) {
      continue;
    }

    final total = int.tryParse(clean(cells[1])) ?? 0;
    if (total == 0) continue;

    final compositionHtml = cells[2];
    final seats = <String, int>{};

    for (final span in spanPattern.allMatches(compositionHtml)) {
      final partyClass = span.group(1)!.toLowerCase();
      final count = int.tryParse(span.group(2)!) ?? 0;
      if (count == 0) continue;

      final String canonicalKey;
      switch (partyClass) {
        case 'con':
          canonicalKey = 'Con';
        case 'lab':
          canonicalKey = 'Lab';
        case 'ld':
          canonicalKey = 'LD';
        case 'grn':
          canonicalKey = 'Grn';
        case 'ref':
          canonicalKey = 'Ref';
        case 'snp':
          canonicalKey = 'SNP';
        case 'pc':
          canonicalKey = 'PC';
        case 'vac':
          canonicalKey = 'Vac';
        case 'ind':
        default:
          canonicalKey = 'Oth';
      }
      seats[canonicalKey] = (seats[canonicalKey] ?? 0) + count;
    }

    // Since control/majority is not in historyYear16.php columns,
    // we calculate control from the seats!
    // Control is the party with >50% of the total seats, or "NOC".
    String control = 'NOC';
    for (final entry in seats.entries) {
      if (entry.key != 'Vac' && entry.value > total / 2) {
        switch (entry.key) {
          case 'Con':
            control = 'CON';
          case 'Lab':
            control = 'LAB';
          case 'LD':
            control = 'LD';
          case 'Grn':
            control = 'GRN';
          case 'Ref':
            control = 'REF';
          case 'SNP':
            control = 'SNP';
          case 'PC':
            control = 'PC';
          case 'Oth':
            control = 'IND';
        }
        break;
      }
    }

    final isCity = isCityOfLondonCouncil(name);
    if (isCity) {
      control = 'IND';
    }

    councils.add(Council(
      name: name,
      type: isCity ? 'Sui Generis' : '',
      control: control,
      seats: seats,
      total: total,
    ));
  }
  return councils;
}

List<Council> parseHistoricalCouncils73(String html) {
  final rowPattern = RegExp(r'<tr[^>]*>(.*?)</tr>', dotAll: true);
  final tdPattern = RegExp(r'<td[^>]*>(.*?)</td>', dotAll: true);
  final spanPattern = RegExp(
    r'class="pop\s+([a-zA-Z0-9_-]+)"[^>]*>.*?(?:class="poptext"[^>]*>)?(\d+)',
    dotAll: true,
  );
  final tagPattern = RegExp(r'<[^>]+>');

  String clean(String s) => s.replaceAll(tagPattern, '').replaceAll('&nbsp;', ' ').trim();

  final councils = <Council>[];

  for (final row in rowPattern.allMatches(html)) {
    final inner = row.group(1)!;
    final cells = tdPattern.allMatches(inner).map((m) => m.group(1)!).toList();
    if (cells.length < 4) continue;

    final name = clean(cells[0]);
    if (name.isEmpty ||
        name.toLowerCase() == 'authority' ||
        name.toLowerCase().startsWith('total')) {
      continue;
    }

    final control = clean(cells[1]);
    final total = int.tryParse(clean(cells[2])) ?? 0;
    if (total == 0) continue;

    final compositionHtml = cells[3];
    final seats = <String, int>{};

    final normName = normaliseCouncilName(name);
    final isScot = _scottishCouncilNames.contains(normName);
    final isWel = _welshCouncilNames.contains(normName);

    for (final span in spanPattern.allMatches(compositionHtml)) {
      final partyClass = span.group(1)!.toLowerCase();
      final count = int.tryParse(span.group(2)!) ?? 0;
      if (count == 0) continue;

      final String canonicalKey;
      switch (partyClass) {
        case 'con':
          canonicalKey = 'Con';
        case 'lab':
          canonicalKey = 'Lab';
        case 'ld':
          canonicalKey = 'LD';
        case 'vac':
          if (isScot) {
            canonicalKey = 'SNP';
          } else if (isWel) {
            canonicalKey = 'PC';
          } else {
            canonicalKey = 'Oth';
          }
        case 'ind':
        default:
          canonicalKey = 'Oth';
      }
      seats[canonicalKey] = (seats[canonicalKey] ?? 0) + count;
    }

    final isCity = isCityOfLondonCouncil(name);

    councils.add(Council(
      name: name,
      type: isCity ? 'Sui Generis' : '',
      control: isCity ? 'IND' : control,
      seats: seats,
      total: total,
    ));
  }
  return councils;
}
