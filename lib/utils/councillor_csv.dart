import '../models/councillor.dart';
import 'area_match.dart';

/// Parses OpenCouncilData's free councillors CSV into [Councillor] records.
///
/// Expected header (column order is not relied upon — we map by name):
/// `Council, Ward Name, Councillor Name, Next Election, Party Name,
/// Electoral Commission Party Code`.
List<Councillor> parseCouncillors(String csv) {
  final rows = _parseCsv(csv);
  if (rows.isEmpty) return const [];

  final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
  int col(String name) => header.indexOf(name.toLowerCase());

  final councilCol = col('Council');
  final wardCol = col('Ward Name');
  final nameCol = col('Councillor Name');
  final electionCol = col('Next Election');
  final partyCol = col('Party Name');
  final partyCodeCol = col('Electoral Commission Party Code');

  // Council, ward and name are the minimum we need for a useful record.
  if (councilCol < 0 || wardCol < 0 || nameCol < 0) return const [];

  String at(List<String> row, int i) =>
      (i >= 0 && i < row.length) ? row[i].trim() : '';

  final councillors = <Councillor>[];
  for (final row in rows.skip(1)) {
    final name = at(row, nameCol);
    final council = at(row, councilCol);
    if (name.isEmpty || council.isEmpty) continue;
    final isCity = isCityOfLondonCouncil(council);
    final role = isCity ? _cityRoleForName(name) : CouncillorRole.councillor;
    final memberships =
        isCity ? _cityMemberships(role) : const <String>[];
    final termYears = isCity ? (role == CouncillorRole.alderman ? 6 : 4) : null;
    final partyRaw = at(row, partyCol);
    final party = isCity && partyRaw.isEmpty ? 'Independent' : partyRaw;
    councillors.add(Councillor(
      council: council,
      ward: at(row, wardCol),
      name: name,
      party: party,
      partyCode: at(row, partyCodeCol),
      nextElection: DateTime.tryParse(at(row, electionCol)),
      role: role,
      memberships: memberships,
      termYears: termYears,
      isPaid: isCity ? false : null,
    ));
  }
  return councillors;
}

CouncillorRole _cityRoleForName(String name) {
  final normalized = name.toLowerCase().trim();
  if (normalized.startsWith('alderman ') ||
      normalized.contains(' alderman ')) {
    return CouncillorRole.alderman;
  }
  if (normalized.startsWith('ald. ') || normalized.startsWith('ald ')) {
    return CouncillorRole.alderman;
  }
  return CouncillorRole.commonCouncillor;
}

List<String> _cityMemberships(CouncillorRole role) {
  if (role == CouncillorRole.alderman) {
    return const ['Court of Common Council', 'Court of Aldermen'];
  }
  return const ['Court of Common Council'];
}

/// Minimal RFC 4180 CSV reader: handles quoted fields, embedded commas and
/// newlines, and `""` escapes. Sufficient for the well-formed OpenCouncilData
/// export — no need to pull in a dependency.
List<List<String>> _parseCsv(String input) {
  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;

  void endField() {
    row.add(field.toString());
    field = StringBuffer();
  }

  void endRow() {
    endField();
    // Skip blank trailing lines.
    if (row.length > 1 || row.first.isNotEmpty) rows.add(row);
    row = <String>[];
  }

  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
    } else {
      switch (ch) {
        case '"':
          inQuotes = true;
        case ',':
          endField();
        case '\r':
          break; // handled by the following \n
        case '\n':
          endRow();
        default:
          field.write(ch);
      }
    }
  }
  // Flush any trailing field/row not terminated by a newline.
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
