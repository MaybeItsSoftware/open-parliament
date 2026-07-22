/// Pure, Flutter-free canonicalisation of UK party names and abbreviations.
///
/// Returns a stable lowercase token (e.g. `'labour'`, `'conservative'`,
/// `'libdem'`, `'snp'`, `'crossbench'`) for the many spellings that appear in
/// Hansard payloads and Members API responses. Returns `null` when nothing
/// can be canonicalised — callers treat that as "unknown / use fallback".
String? canonicalPartyToken(String value) {
  final raw = value.toLowerCase().trim();
  final norm = raw.replaceAll(RegExp(r'[^a-z]'), '');
  if (norm.isEmpty) return null;

  if (norm == 'lab' ||
      norm == 'labour' ||
      norm == 'labourparty' ||
      norm == 'labourandcooperative' ||
      norm == 'labourcooperative' ||
      norm == 'labcoop' ||
      raw.contains('lab co-op')) {
    return 'labour';
  }
  if (norm == 'con' ||
      norm == 'conservative' ||
      norm == 'conservativeparty' ||
      norm == 'conservativeandunionist' ||
      norm == 'conservativeandunionistparty') {
    return 'conservative';
  }
  if (norm == 'ld' ||
      norm == 'libdem' ||
      norm == 'liberaldemocrat' ||
      norm == 'liberaldemocrats' ||
      raw.contains('lib dem')) {
    return 'libdem';
  }
  if (norm == 'snp' || norm == 'scottishnationalparty') return 'snp';
  if (norm == 'green' || norm == 'grn' || raw.contains('green party')) {
    return 'green';
  }
  if (norm == 'plaidcymru' || norm == 'plaid' || norm == 'pc') {
    return 'plaidcymru';
  }
  if (norm == 'sinnfein') return 'sinnfein';
  if (norm == 'dup' || norm == 'democraticunionistparty') return 'dup';
  if (norm == 'uup' || norm == 'ulsterunionistparty') return 'uup';
  if (norm == 'alliance' || norm == 'allianceparty') return 'alliance';
  if (norm == 'cb' || norm == 'crossbench' || raw.contains('crossbench')) {
    return 'crossbench';
  }
  if (norm == 'nonaffiliated' || norm == 'independent' || norm == 'ind') {
    return 'independent';
  }
  if (norm == 'speaker') return 'speaker';
  if (norm == 'reform' || norm == 'reformuk' || norm == 'ref') return 'reform';
  if (norm == 'restorebritain' || norm == 'restorebritainparty' || norm == 'rb') {
    return 'restorebritain';
  }
  return null;
}
