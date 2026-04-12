import 'package:flutter/material.dart';

/// Canonical party token from any spelling of a party name/abbreviation.
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
  if (norm == 'green' || raw.contains('green party')) return 'green';
  if (norm == 'plaidcymru') return 'plaidcymru';
  if (norm == 'sinnfein') return 'sinnfein';
  if (norm == 'dup' || norm == 'democraticunionistparty') return 'dup';
  if (norm == 'uup' || norm == 'ulsterunionistparty') return 'uup';
  if (norm == 'alliance' || norm == 'allianceparty') return 'alliance';
  if (norm == 'cb' || norm == 'crossbench' || raw.contains('crossbench')) {
    return 'crossbench';
  }
  if (norm == 'nonaffiliated' || norm == 'independent') return 'independent';
  if (norm == 'reform' || norm == 'reformuk') return 'reform';
  return null;
}

/// Party brand color for a given party name or abbreviation.
Color partyColor(String partyName, {Color? fallback}) {
  final token = canonicalPartyToken(partyName);
  if (token == 'labour') return const Color(0xFFE4003B);
  if (token == 'conservative') return const Color(0xFF0087DC);
  if (token == 'libdem') return const Color(0xFFFDBB30);
  if (token == 'snp') return const Color(0xFFEACB00);
  if (token == 'green') return const Color(0xFF6AB023);
  if (token == 'plaidcymru') return const Color(0xFF008142);
  if (token == 'sinnfein') return const Color(0xFF326760);
  if (token == 'dup') return const Color(0xFFD46A4C);
  if (token == 'uup') return const Color(0xFF48A9E6);
  if (token == 'alliance') return const Color(0xFFFFD447);
  if (token == 'crossbench' || token == 'independent') return const Color(0xFF6C757D);
  if (token == 'reform') return const Color(0xFF12B6CF);
  return fallback ?? const Color(0xFF6C757D);
}

/// Light foreground (white) or dark foreground depending on background luminance.
Color foregroundForParty(Color bg) {
  return bg.computeLuminance() > 0.35 ? Colors.black87 : Colors.white;
}
