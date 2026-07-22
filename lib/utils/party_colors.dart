import 'package:flutter/material.dart';

import 'council_control.dart';
import 'party_tokens.dart';

export 'party_tokens.dart' show canonicalPartyToken;

/// Neutral grey used for areas with no single controlling party (no overall
/// control) or that could not be matched to data.
const Color noControlColor = Color(0xFF9E9E9E);

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
  if (token == 'speaker') return Colors.black;
  if (token == 'reform') return const Color(0xFF17B9D1);
  if (token == 'restorebritain') return const Color(0xFF051D3F);
  return fallback ?? const Color(0xFF6C757D);
}

/// Brand colour for a council's political control string (e.g. `"LAB"`,
/// `"SNP/LD"`), falling back to [noControlColor] for no-overall-control.
Color controlColor(String control) {
  final token = councilControlToken(control);
  return token == null ? noControlColor : partyColor(token);
}

/// Light foreground (white) or dark foreground depending on background luminance.
Color foregroundForParty(Color bg) {
  return bg.computeLuminance() > 0.35 ? Colors.black87 : Colors.white;
}
