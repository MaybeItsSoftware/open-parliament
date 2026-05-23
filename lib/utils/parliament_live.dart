import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/parliament_live_event.dart';
import '../views/parliament_live_view.dart';

/// Builds a parliamentlive.tv search URL for a given sitting day.
///
/// [date] is `YYYY-MM-DD`. [house] may be the strings the rest of the app
/// uses ("Commons", "Lords", "Commons & Lords", "Westminster Hall", etc.);
/// it is mapped to the `Commons` / `Lords` value the search page expects.
/// A null or unmappable house leaves the parameter off so the search shows
/// every house's content for the day.
Uri parliamentLiveSearchUrl({required String date, String? house}) {
  final params = <String, String>{'Day': date};
  final mapped = _mapHouse(house);
  if (mapped != null) params['House'] = mapped;
  return Uri.https('parliamentlive.tv', '/Search', params);
}

/// Direct deep-link to a single Parliament-Live event.
Uri parliamentLiveEventUrl(String guid, {String? timecode}) {
  final base = Uri.https('parliamentlive.tv', '/event/index/$guid');
  if (timecode == null || timecode.isEmpty) return base;
  return base.replace(queryParameters: {'in': timecode});
}

/// Direct URL for the standalone player app used by parliamentlive.tv.
///
/// This is intentionally different from [parliamentLiveEventUrl], which loads
/// the full site shell around the player. The standalone player endpoint is a
/// better fit for in-app WebViews because it avoids nested cross-site iframe
/// and cookie constraints.
Uri parliamentLivePlayerUrl(String guid, {Uri? parentUrl}) {
  final base = Uri.https(
    'videoplayback.parliamentlive.tv',
    '/Player/Index/$guid',
    const {
      'audioOnly': 'False',
      'autoStart': 'True',
      'script': 'True',
    },
  );
  if (parentUrl == null) return base;
  return Uri.parse(
      '${base.toString()}#${Uri.encodeComponent(parentUrl.toString())}');
}

/// Opens [url] in the in-app WebView on platforms that support it
/// (Android, iOS, macOS), or the system browser elsewhere. A snackbar is
/// shown on launch failure.
Future<void> openParliamentLive({
  required BuildContext context,
  required Uri url,
  String? title,
}) async {
  if (_supportsInAppWebView) {
    final inAppUrl = _inAppWebViewUrl(url);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ParliamentLiveView(
          url: inAppUrl,
          externalUrl: url,
          title: title ?? 'Parliament Live',
        ),
      ),
    );
    return;
  }

  final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not open parliamentlive.tv')),
    );
  }
}

/// Returns true when a Hansard section typically has a matching Parliament Live
/// recording (written-only sections do not).
bool parliamentLiveSectionHasVideo(String? section) {
  final normalized = _normalizeSection(section);
  if (normalized == null) return true;
  return !_isWrittenOnlySection(normalized);
}

/// Human-readable reason when a section does not have Parliament Live video.
String? parliamentLiveSectionUnavailableMessage(String? section) {
  final normalized = _normalizeSection(section);
  if (normalized == null || !_isWrittenOnlySection(normalized)) return null;
  if (normalized.contains('correction')) {
    return 'Written corrections are text-only and do not have a Parliament Live video.';
  }
  if (normalized == 'wms' || normalized.contains('statement')) {
    return 'Written statements are text-only and do not have a Parliament Live video.';
  }
  return 'Written items are text-only and do not have a Parliament Live video.';
}

/// Returns the parliamentlive.tv event that best matches [debateTitle], or
/// `null` if no event's title is close enough.
///
/// Strategy (cheap, deterministic):
///  1. Exact equality on normalised titles.
///  2. Either title contains the other (handles cases like Hansard's
///     "Courts and Tribunals Bill (Ninth sitting)" vs the event's bare
///     "Courts and Tribunals Bill").
///  3. Token-set inclusion when one normalised title's words are all
///     present in the other.
ParliamentLiveEvent? bestParliamentLiveMatch(
  String debateTitle,
  List<ParliamentLiveEvent> events,
) {
  if (events.isEmpty) return null;
  final target = _normalizeTitle(debateTitle);
  if (target.isEmpty) return null;

  for (final e in events) {
    if (_normalizeTitle(e.title) == target) return e;
  }

  for (final e in events) {
    final norm = _normalizeTitle(e.title);
    if (norm.length < 4) continue;
    if (target.contains(norm) || norm.contains(target)) return e;
  }

  final targetTokens = target.split(' ').where((t) => t.isNotEmpty).toSet();
  if (targetTokens.length >= 2) {
    for (final e in events) {
      final tokens = _normalizeTitle(e.title)
          .split(' ')
          .where((t) => t.isNotEmpty)
          .toSet();
      if (tokens.length < 2) continue;
      if (tokens.containsAll(targetTokens) ||
          targetTokens.containsAll(tokens)) {
        return e;
      }
    }
  }

  return null;
}

/// Fallback match when a debate title does not directly match any event.
///
/// This maps chamber-level Hansard debates (e.g. oral questions in Commons)
/// onto the day-level chamber stream so callers can still deep-link using
/// Hansard timecodes.
ParliamentLiveEvent? fallbackParliamentLiveMatchForHouse({
  required List<ParliamentLiveEvent> events,
  String? house,
}) {
  if (events.isEmpty || house == null || house.trim().isEmpty) return null;
  final h = house.toLowerCase();

  if (h.contains('westminster hall')) {
    return _bestTitleKeywordMatch(events, const ['westminster hall']);
  }
  if (h.contains('grand committee')) {
    return _bestTitleKeywordMatch(
      events,
      const ['grand committee', 'house of lords'],
    );
  }
  if (h.contains('lords')) {
    return _bestTitleKeywordMatch(
      events,
      const ['house of lords', 'lords chamber'],
    );
  }
  if (h.contains('commons')) {
    return _bestTitleKeywordMatch(
      events,
      const ['house of commons', 'commons chamber'],
    );
  }
  return null;
}

ParliamentLiveEvent? _bestTitleKeywordMatch(
  List<ParliamentLiveEvent> events,
  List<String> keywords,
) {
  final normalizedKeywords = keywords.map(_normalizeTitle).toList();

  for (final keyword in normalizedKeywords) {
    for (final event in events) {
      if (_normalizeTitle(event.title) == keyword) return event;
    }
  }
  for (final keyword in normalizedKeywords) {
    for (final event in events) {
      if (_normalizeTitle(event.title).contains(keyword)) return event;
    }
  }
  return null;
}

String _normalizeTitle(String s) {
  var x = s.toLowerCase();
  // Sign-language broadcasts duplicate the chamber title.
  if (x.startsWith('bsl - ')) x = x.substring(6);
  // Drop parenthesised sitting numbers / morning markers.
  x = x.replaceAll(RegExp(r'\([^)]*\)'), ' ');
  // Drop punctuation, collapse whitespace.
  x = x.replaceAll(RegExp(r"[^a-z0-9' ]"), ' ');
  x = x.replaceAll(RegExp(r'\s+'), ' ').trim();
  return x;
}

String? _normalizeSection(String? section) {
  if (section == null) return null;
  final normalized = section.trim().toLowerCase();
  return normalized.isEmpty ? null : normalized;
}

bool _isWrittenOnlySection(String normalized) {
  if (normalized == 'wms') return true;
  if (normalized.contains('written')) return true;
  if (normalized.contains('correction')) return true;
  return false;
}

/// True on platforms where `webview_flutter` provides a working
/// implementation. parliamentlive.tv's CSP would block its own player
/// inside a web `<iframe>`, so the web platform is excluded too.
bool get _supportsInAppWebView {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

Uri _inAppWebViewUrl(Uri url) {
  // Keep the full event page when deep-linking by `?in=` so their own page
  // script can translate it into a seek command for the embedded player.
  if (url.queryParameters.containsKey('in')) return url;
  final guid = _eventGuidFromEventUrl(url);
  if (guid == null) return url;
  return parliamentLivePlayerUrl(guid, parentUrl: url);
}

final RegExp _guidPattern = RegExp(
  r'^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$',
);

String? _eventGuidFromEventUrl(Uri url) {
  if (url.host.toLowerCase() != 'parliamentlive.tv') return null;
  final segments = url.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.length < 3) return null;
  if (segments[0].toLowerCase() != 'event' ||
      segments[1].toLowerCase() != 'index') {
    return null;
  }
  final guid = segments[2].toLowerCase();
  if (!_guidPattern.hasMatch(guid)) return null;
  return guid;
}

String? _mapHouse(String? house) {
  if (house == null) return null;
  final h = house.toLowerCase();
  if (h.contains('commons') && h.contains('lords')) return null;
  if (h.contains('lords')) return 'Lords';
  if (h.contains('commons')) return 'Commons';
  if (h.contains('westminster hall')) return 'Commons';
  if (h.contains('grand committee')) return 'Lords';
  return null;
}
