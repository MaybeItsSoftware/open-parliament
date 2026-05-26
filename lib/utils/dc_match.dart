// Helpers for joining OpenCouncilData councillors to Democracy Club records.
//
// Democracy Club has no person-name search, so the only way to find a
// councillor's DC person id (and hence their photo) is via that council's
// local-election ballots: `election_id = local.<slug>.<date>`. These helpers
// build the slug, enumerate the election dates worth trying, and fuzzily match
// names between the two sources (DC often carries middle names and honorifics
// that OpenCouncilData omits).

/// UK local-election polling dates worth querying, newest first. Councils that
/// elect by thirds spread their current members across several of these, so a
/// full roster is the union over all of them.
const List<String> kLocalElectionDates = [
  '2025-05-01',
  '2024-05-02',
  '2023-05-18', // Northern Ireland locals
  '2023-05-04',
  '2022-05-05', // England, Scotland, Wales, London boroughs
  '2021-05-06',
];

/// Slugifies a council name into the form Democracy Club uses in election ids,
/// e.g. "Amber Valley" → "amber-valley", "City of London" → "city-of-london".
String dcCouncilSlug(String councilName) {
  return councilName
      .toLowerCase()
      .replaceAll('&', ' and ')
      .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
      .trim()
      .replaceAll(RegExp(r'\s+'), '-');
}

const Set<String> _honorifics = {
  'cllr', 'councillor', 'alderman', 'ald', 'mr', 'mrs', 'ms', 'miss', 'mx',
  'dr', 'sir', 'dame', 'prof', 'professor', 'rev', 'reverend', 'the', 'lord',
  'lady', 'baroness', 'count', 'councilman',
};

/// Lowercased name tokens with punctuation and honorifics removed.
/// "Cllr Susan Mary Hall" → ["susan", "mary", "hall"].
List<String> nameTokens(String name) {
  return name
      .toLowerCase()
      .replaceAll(RegExp(r"[^a-z\s-]"), '')
      .replaceAll('-', ' ')
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_honorifics.contains(t))
      .toList();
}

/// True when two names plausibly refer to the same person. Requires the last
/// token to match and the first tokens to be compatible (equal, or one an
/// initial/prefix of the other), tolerating DC's middle names.
bool namesMatch(String a, String b) {
  final ta = nameTokens(a);
  final tb = nameTokens(b);
  if (ta.isEmpty || tb.isEmpty) return false;
  if (ta.last != tb.last) return false;

  final fa = ta.first;
  final fb = tb.first;
  if (fa == fb) return true;
  // Initial against full name, e.g. "j" vs "john".
  if (fa.length == 1 || fb.length == 1) {
    return fa[0] == fb[0];
  }
  // One a prefix of the other guards against "Cathy" vs "Catherine" only
  // loosely; keep it strict-ish by requiring 3+ shared leading chars.
  final shorter = fa.length < fb.length ? fa : fb;
  final longer = fa.length < fb.length ? fb : fa;
  return shorter.length >= 3 && longer.startsWith(shorter);
}
