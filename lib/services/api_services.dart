import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:sentry/sentry.dart';

import '../models/debate.dart';
import '../models/election_result.dart';
import '../models/member.dart';
import '../models/council.dart';
import '../models/councillor.dart';
import '../models/councillor_profile.dart';
import '../models/parliament_live_event.dart';
import '../models/recess_period.dart';
import '../models/speech.dart';
import '../utils/area_match.dart';
import '../utils/council_control.dart';
import '../utils/councillor_csv.dart';
import '../utils/dc_match.dart';

/// Upper bound on a single request across the lightweight, best-effort API
/// clients in this file (everything except [BoundaryApiService], which has
/// its own longer timeout + retry tuned for the ArcGIS gateway). Without
/// this, a stalled connection to any Parliament API left the caller's
/// `isLoading` state spinning forever instead of surfacing an error.
const Duration _defaultHttpTimeout = Duration(seconds: 20);

/// Adds a bounded-time `get` to [http.Client] so every call site below gets
/// the same timeout without repeating `.timeout(...)` everywhere.
extension _TimedHttpGet on http.Client {
  Future<http.Response> getTimed(Uri url, {Map<String, String>? headers}) {
    return get(url, headers: headers).timeout(_defaultHttpTimeout);
  }
}

/// Reports a failure that a caller is about to swallow (returning an empty
/// list / null fallback) so it's still visible in Sentry instead of vanishing
/// entirely. A no-op when Sentry hasn't been initialised (e.g. in tests or
/// local runs without a DSN), since the SDK no-ops until `Sentry.init` runs.
void _reportSilentFailure(Object error, StackTrace stackTrace) {
  unawaited(Sentry.captureException(error, stackTrace: stackTrace));
}

/// Low-level HTTP client for the official Parliament Members API.
///
/// Endpoint: https://members-api.parliament.uk/api/Members/Search
class MembersApiService {
  static const String _baseUrl =
      'https://members-api.parliament.uk/api/Members';

  final http.Client _client;

  MembersApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches all active Members from the API, paginating automatically.
  ///
  /// Returns an empty list on network failure (caller decides on retry logic).
  Future<List<Member>> fetchAllMembers() async {
    const int pageSize = 100;
    int skip = 0;
    final List<Member> members = [];

    while (true) {
      final uri = Uri.parse(
        '$_baseUrl/Search?skip=$skip&take=$pageSize&IsCurrentMember=true',
      );
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode != 200) {
        break;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = body['items'] as List<dynamic>? ?? [];

      if (items.isEmpty) {
        break;
      }

      for (final item in items) {
        try {
          members.add(Member.fromApiJson(item as Map<String, dynamic>));
        } catch (_) {
          // Skip malformed individual records.
        }
      }

      final totalResults = (body['totalResults'] as num?)?.toInt() ?? 0;
      skip += items.length;
      if (totalResults > 0 && skip >= totalResults) {
        break;
      }
    }

    return members;
  }

  /// Geocodes a UK constituency name to [latitude, longitude] using Nominatim.
  ///
  /// Returns `null` on network failure or if the constituency cannot be found.
  Future<List<double>?> geocodeConstituency(String constituencyName) async {
    final uri = Uri.parse(
      'https://nominatim.openstreetmap.org/search',
    ).replace(
      queryParameters: {
        'q': '$constituencyName UK constituency',
        'format': 'json',
        'limit': '1',
        'countrycodes': 'gb',
      },
    );
    try {
      final response = await _client.getTimed(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'open-hansard/1.0',
        },
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as List<dynamic>;
      if (body.isEmpty) return null;
      final first = body.first as Map<String, dynamic>;
      final lat = double.tryParse((first['lat'] as String?) ?? '');
      final lon = double.tryParse((first['lon'] as String?) ?? '');
      if (lat == null || lon == null) return null;
      return [lat, lon];
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return null;
    }
  }

  /// Fetches extended detail for a single member (constituency, house, start date).
  ///
  /// Returns the unwrapped `value` object from the API, or null on failure.
  Future<Map<String, dynamic>?> fetchMemberDetail(int id) async {
    final uri = Uri.parse('$_baseUrl/$id');
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['value'] as Map<String, dynamic>?) ?? body;
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return null;
    }
  }

  /// Base for the Location/Constituency endpoints (search + election results).
  static const String _constituencyBaseUrl =
      'https://members-api.parliament.uk/api/Location/Constituency';

  /// Resolves a Westminster constituency name to its numeric id via the
  /// Location search endpoint. Prefers an exact (normalised) name match,
  /// otherwise falls back to the first result. Returns null on failure / miss.
  Future<int?> fetchConstituencyId(String name) async {
    final uri = Uri.parse('$_constituencyBaseUrl/Search').replace(
      queryParameters: {'searchText': name, 'take': '10'},
    );
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = body['items'] as List<dynamic>? ?? const [];
      if (items.isEmpty) return null;

      final target = normaliseName(name);
      int? firstId;
      for (final item in items) {
        final value = (item as Map<String, dynamic>)['value']
                as Map<String, dynamic>? ??
            {};
        final id = (value['id'] as num?)?.toInt();
        if (id == null) continue;
        firstId ??= id;
        if (normaliseName((value['name'] as String?) ?? '') == target) {
          return id;
        }
      }
      return firstId;
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return null;
    }
  }

  /// Fetches the latest general-election result (winner, majority, turnout and
  /// per-candidate votes) for a constituency. Returns null on failure.
  Future<ConstituencyElectionResult?> fetchLatestElectionResult(
    int constituencyId,
  ) async {
    final uri =
        Uri.parse('$_constituencyBaseUrl/$constituencyId/ElectionResult/latest');
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return ConstituencyElectionResult.fromJson(body);
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return null;
    }
  }

  /// Fetches the biography for a member (government/opposition posts, party history).
  ///
  /// Returns the unwrapped `value` object from the API, or null on failure.
  Future<Map<String, dynamic>?> fetchMemberBiography(int id) async {
    final uri = Uri.parse('$_baseUrl/$id/Biography');
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['value'] as Map<String, dynamic>?) ?? body;
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return null;
    }
  }

  /// Fetches one page of a member's recorded division (vote) history for
  /// [house] (1 = Commons, 2 = Lords), newest first. Pages are 1-indexed and
  /// the API returns 20 votes per page.
  ///
  /// Returns the unwrapped `value` object of each result, or an empty list on
  /// network failure or when no votes are found.
  Future<List<Map<String, dynamic>>> fetchMemberVoting(
    int id, {
    int house = 1,
    int page = 1,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id/Voting').replace(
      queryParameters: {
        'house': house.toString(),
        'page': page.toString(),
      },
    );
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (body['items'] as List<dynamic>?) ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map((item) =>
              (item['value'] as Map<String, dynamic>?) ?? const <String, dynamic>{})
          .where((value) => value.isNotEmpty)
          .toList();
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  /// Fetches the party composition for a specific [house] ('Commons' or 'Lords')
  /// on a specific [date].
  ///
  /// Returns a list of party objects containing name, abbreviation, and count.
  Future<List<Map<String, dynamic>>> fetchStateOfTheParties(
    String house,
    DateTime date,
  ) async {
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse('$_baseUrl/Parties/StateOfTheParties/$house/$dateStr');
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (body['items'] as List<dynamic>?) ?? const [];
      return items
          .whereType<Map<String, dynamic>>()
          .map((item) => (item['value'] as Map<String, dynamic>?) ?? item)
          .toList();
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  void dispose() => _client.close();
}

/// Low-level HTTP client for the official Hansard API.
///
/// Primary:  https://hansard-api.parliament.uk/overview/sectionsforday.json
/// Fallback: https://hansard-api.parliament.uk/debates/debate/{id}.json
class HansardApiService {
  static const String _baseUrl = 'https://hansard-api.parliament.uk';

  final http.Client _client;

  HansardApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the list of debate sections for [date] (YYYY-MM-DD).
  ///
  /// Uses the Overview endpoints to discover available sections and their
  /// root debate IDs for the given day and house.
  ///
  /// Returns a list of top-level debate roots, each with an `ExternalId` used
  /// to fetch full speech content.
  Future<List<Debate>> fetchSittingDebates(
    String date, {
    String? house,
  }) async {
    final houses =
        house != null ? <String>[house] : <String>['Commons', 'Lords'];
    final debates = <Debate>[];
    int orderIndex = 0;

    for (final currentHouse in houses) {
      final sectionsUri = Uri.parse(
        '$_baseUrl/overview/sectionsforday.json',
      ).replace(
        queryParameters: {'house': currentHouse, 'date': date},
      );
      final sectionsResponse = await _client.getTimed(
        sectionsUri,
        headers: {'Accept': 'application/json'},
      );

      // 404 means no data for the selected date/house.
      if (sectionsResponse.statusCode == 404) {
        continue;
      }
      if (sectionsResponse.statusCode != 200) {
        throw HansardApiException(
          'Failed to fetch sections for $date ($currentHouse): '
          'HTTP ${sectionsResponse.statusCode}',
        );
      }

      final sectionsRaw = jsonDecode(sectionsResponse.body);
      final sections = sectionsRaw is List
          ? sectionsRaw.whereType<String>().toList()
          : const <String>[];

      for (final section in sections) {
        final treeUri = Uri.parse(
          '$_baseUrl/overview/sectiontrees.json',
        ).replace(
          queryParameters: {
            'house': currentHouse,
            'date': date,
            'section': section,
          },
        );
        final treeResponse = await _client.getTimed(
          treeUri,
          headers: {'Accept': 'application/json'},
        );

        if (treeResponse.statusCode == 404) {
          continue;
        }
        if (treeResponse.statusCode != 200) {
          throw HansardApiException(
            'Failed to fetch section tree for $date ($currentHouse/$section): '
            'HTTP ${treeResponse.statusCode}',
          );
        }

        final treeRaw = jsonDecode(treeResponse.body);
        final treeItems =
            treeRaw is List<dynamic> ? treeRaw : const <dynamic>[];

        for (final treeItem in treeItems) {
          if (treeItem is! Map<String, dynamic>) {
            continue;
          }

          final rootSections = _extractRootSectionNodes(treeItem);
          for (final rootSection in rootSections) {
            final debateId = (rootSection['ExternalId'] as String?) ??
                (rootSection['externalId'] as String?) ??
                '';
            if (debateId.isEmpty) {
              continue;
            }

            final title = (rootSection['Title'] as String?) ??
                (treeItem['Title'] as String?) ??
                section;

            debates.add(
              Debate(
                id: debateId,
                title: title,
                house: _resolveHouseLabel(currentHouse, section),
                section: section,
                orderIndex: orderIndex++,
              ),
            );
          }
        }
      }
    }
    return debates;
  }

  /// Fetches all speeches for a single debate identified by [debateId].
  Future<List<Speech>> fetchDebateSpeeches(
    String debateId,
    String debateTitle,
  ) async {
    final uri = Uri.parse('$_baseUrl/debates/debate/$debateId.json');
    final response = await _client.getTimed(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode == 404) {
      return const <Speech>[];
    }
    if (response.statusCode != 200) {
      throw HansardApiException(
        'Failed to fetch debate $debateId: HTTP ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final speeches = <Speech>[];
    int orderIndex = 0;

    void collectFromNode(
      Map<String, dynamic> node, {
      required String fallbackDebateId,
      required String fallbackDebateTitle,
    }) {
      final overview = node['Overview'] as Map<String, dynamic>?;
      final nodeDebateId = (overview?['ExtId'] as String?) ??
          (overview?['ExternalId'] as String?) ??
          fallbackDebateId;
      final nodeDebateTitle =
          (overview?['Title'] as String?) ?? fallbackDebateTitle;

      final items = (node['Items'] as List<dynamic>?) ?? const <dynamic>[];
      for (final item in items) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final speech = Speech.fromApiJson(
          item,
          debateId: nodeDebateId,
          debateTitle: nodeDebateTitle,
          orderIndex: orderIndex++,
        );
        // Ignore structural markers (e.g. empty column-number spans).
        if (speech.speechText.trim().isEmpty &&
            !speech.hasNamedSpeaker &&
            !speech.isTimestamp) {
          continue;
        }
        speeches.add(speech);
      }

      final childDebates =
          (node['ChildDebates'] as List<dynamic>?) ?? const <dynamic>[];
      for (final child in childDebates) {
        if (child is! Map<String, dynamic>) {
          continue;
        }
        collectFromNode(
          child,
          fallbackDebateId: nodeDebateId,
          fallbackDebateTitle: nodeDebateTitle,
        );
      }
    }

    collectFromNode(
      body,
      fallbackDebateId: debateId,
      fallbackDebateTitle: debateTitle,
    );
    return speeches;
  }

  /// Returns the nearest previous and next sitting dates around [date].
  ///
  /// Uses `/overview/linkedsittingdates.{format}`. When [house] is omitted,
  /// both Commons and Lords are queried and merged so that any parliamentary
  /// sitting counts.
  Future<LinkedSittingDates> fetchLinkedSittingDates(
    String date, {
    String? house,
  }) async {
    final houses =
        house != null ? <String>[house] : const <String>['Commons', 'Lords'];
    final previousCandidates = <DateTime>[];
    final nextCandidates = <DateTime>[];

    for (final currentHouse in houses) {
      final uri = Uri.parse(
        '$_baseUrl/overview/linkedsittingdates.json',
      ).replace(
        queryParameters: {'house': currentHouse, 'date': date},
      );
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );

      if (response.statusCode == 404) {
        continue;
      }
      if (response.statusCode != 200) {
        throw HansardApiException(
          'Failed to fetch linked sitting dates for $date ($currentHouse): '
          'HTTP ${response.statusCode}',
        );
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final previous = _parseSittingDate(body['PreviousSittingDate']);
      final next = _parseSittingDate(body['NextSittingDate']);
      if (previous != null) previousCandidates.add(previous);
      if (next != null) nextCandidates.add(next);
    }

    DateTime? closestPrevious;
    if (previousCandidates.isNotEmpty) {
      closestPrevious = previousCandidates.reduce(
        (a, b) => a.isAfter(b) ? a : b,
      );
    }

    DateTime? closestNext;
    if (nextCandidates.isNotEmpty) {
      closestNext = nextCandidates.reduce(
        (a, b) => a.isBefore(b) ? a : b,
      );
    }

    return LinkedSittingDates(
      previousSittingDate: closestPrevious,
      nextSittingDate: closestNext,
    );
  }

  /// Returns every sitting date in the given [month] of [year] for [house]
  /// (`Commons` or `Lords`), in one request via `/overview/calendar.{format}`.
  ///
  /// The endpoint yields a list of `{House, ItemDate, Metadata}` objects; we
  /// keep the dates (normalised to midnight). A 404 yields an empty list.
  Future<List<DateTime>> fetchSittingCalendar(
    int year,
    int month,
    String house,
  ) async {
    final uri = Uri.parse('$_baseUrl/overview/calendar.json').replace(
      queryParameters: {
        'year': year.toString(),
        'month': month.toString(),
        'house': house,
      },
    );
    final response = await _client.getTimed(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode == 404) return const [];
    if (response.statusCode != 200) {
      throw HansardApiException(
        'Failed to fetch sitting calendar for $year-$month ($house): '
        'HTTP ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body);
    if (body is! List) return const [];
    final dates = <DateTime>[];
    for (final item in body) {
      if (item is Map<String, dynamic>) {
        final date = _parseSittingDate(item['ItemDate']);
        if (date != null) dates.add(date);
      }
    }
    return dates;
  }

  /// Fetches recent Hansard contributions (speeches) for [memberId].
  ///
  /// Returns raw JSON result maps, newest first.  Returns an empty list on
  /// network failure or when no contributions are found.
  Future<List<Map<String, dynamic>>> fetchMemberContributions(
    int memberId, {
    int take = 20,
  }) async {
    final uri = Uri.parse(
      '$_baseUrl/search/contributions.json',
    ).replace(
      queryParameters: {
        'memberId': memberId.toString(),
        'take': take.toString(),
      },
    );
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['Results'] as List<dynamic>?) ?? [];
      return results.whereType<Map<String, dynamic>>().toList();
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  void dispose() => _client.close();

  /// Maps a (house, section) pair to a human-readable venue label.
  static String _resolveHouseLabel(String house, String section) {
    final s = section.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (s == 'pbc' || s.contains('publicbill') || s.contains('committee')) {
      return 'Committee';
    }
    if (s == 'westhall' || s.contains('westminsterhall')) {
      return 'Westminster Hall';
    }
    if (s.contains('grandcommittee')) return 'Grand Committee';
    if (s == 'gen') return 'General Committee';
    if (s == 'wms') return house; // Written Statements — keep house label
    return house;
  }

  /// Returns the top-level debate nodes from a section tree.
  ///
  /// The tree has one container node (ParentId == null) representing the
  /// chamber/section (e.g. "Commons Chamber"). The actual debates are its
  /// direct children. We return those direct children, each of which maps to
  /// a fetchable debate via its ExternalId.
  List<Map<String, dynamic>> _extractRootSectionNodes(
      Map<String, dynamic> treeItem) {
    final sectionTreeItems = treeItem['SectionTreeItems'];
    if (sectionTreeItems is! List<dynamic> || sectionTreeItems.isEmpty) {
      return const [];
    }

    final items = sectionTreeItems.whereType<Map<String, dynamic>>().toList();

    // Find the container node (ParentId == null).
    Map<String, dynamic>? container;
    for (final item in items) {
      if (item['ParentId'] == null) {
        container = item;
        break;
      }
    }

    if (container != null) {
      // Return direct children of the container that have an ExternalId.
      final containerId = container['Id'];
      final children = items.where((item) {
        final externalId = item['ExternalId'] ?? item['externalId'];
        return item['ParentId'] == containerId &&
            externalId is String &&
            externalId.isNotEmpty;
      }).toList();
      if (children.isNotEmpty) return children;
    }

    // Fallback: return all nodes with an ExternalId.
    return items.where((item) {
      final externalId = item['ExternalId'] ?? item['externalId'];
      return externalId is String && externalId.isNotEmpty;
    }).toList();
  }

  DateTime? _parseSittingDate(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      return null;
    }
    return DateTime(parsed.year, parsed.month, parsed.day);
  }
}

class LinkedSittingDates {
  final DateTime? previousSittingDate;
  final DateTime? nextSittingDate;

  const LinkedSittingDates({
    required this.previousSittingDate,
    required this.nextSittingDate,
  });
}

/// Low-level HTTP client for the official Parliament "What's On" API.
///
/// Endpoint: https://whatson-api.parliament.uk — the canonical source for
/// recesses and other named non-sitting periods (conference recess,
/// Christmas adjournment, dissolution, …).
class WhatsOnApiService {
  static const String _baseUrl = 'https://whatson-api.parliament.uk';

  final http.Client _client;

  WhatsOnApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the non-sitting periods for [house] (`Commons` or `Lords`)
  /// overlapping [startDate]..[endDate] (both `YYYY-MM-DD`, inclusive) via
  /// `/calendar/events/nonsitting.json`.
  ///
  /// Best-effort: returns an empty list on any HTTP or parse failure, since
  /// recess labels only decorate the calendar and must never block it.
  Future<List<RecessPeriod>> fetchNonSittingPeriods({
    required String startDate,
    required String endDate,
    required String house,
  }) async {
    final uri = Uri.parse('$_baseUrl/calendar/events/nonsitting.json').replace(
      queryParameters: {
        'startDate': startDate,
        'endDate': endDate,
        'house': house,
      },
    );
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body);
      if (body is! List) return const [];
      final periods = <RecessPeriod>[];
      for (final item in body) {
        if (item is! Map<String, dynamic>) continue;
        final period = RecessPeriod.fromApiJson(item, fallbackHouse: house);
        if (period != null) periods.add(period);
      }
      return periods;
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  void dispose() => _client.close();
}

/// Scrapes parliamentlive.tv's public search page to map a sitting day to
/// the per-event GUIDs used by `https://parliamentlive.tv/event/index/{guid}`.
///
/// There is no documented JSON endpoint for this; the search HTML is the
/// only canonical source. The shape we depend on is `<a href=".../Event/
/// Index/{guid}">…<img alt="{title}">` which has been stable for years.
class ParliamentLiveApiService {
  static const String _baseUrl = 'https://parliamentlive.tv';

  final http.Client _client;
  final Map<String, List<ParliamentLiveEvent>> _cache = {};

  ParliamentLiveApiService({http.Client? client})
      : _client = client ?? http.Client();

  /// Returns every event that aired on [date] (`YYYY-MM-DD`). Both chambers
  /// are included — the search page's House filter is too coarse for our
  /// needs. The result is cached in-memory for the life of the service.
  Future<List<ParliamentLiveEvent>> fetchEventsForDate(String date) async {
    final cached = _cache[date];
    if (cached != null) return cached;

    final parts = date.split('-');
    if (parts.length != 3) return const [];
    final formatted = '${parts[2]}/${parts[1]}/${parts[0]}';

    final uri = Uri.parse('$_baseUrl/Search').replace(
      queryParameters: <String, String>{
        'Start': formatted,
        'End': formatted,
      },
    );

    try {
      final response = await _client.getTimed(uri);
      if (response.statusCode != 200) return const [];
      final events = parseSearchHtml(response.body);
      _cache[date] = events;
      return events;
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  /// Extracts `(guid, title)` pairs from a parliamentlive.tv search page
  /// response. Public so it can be unit-tested with a fixture.
  static List<ParliamentLiveEvent> parseSearchHtml(String html) {
    final pattern = RegExp(
      r'href="https://parliamentlive\.tv/Event/Index/([a-f0-9-]{36})"[^>]*>\s*<img[^>]*\salt="([^"]+)"',
      multiLine: true,
    );
    final seen = <String>{};
    final events = <ParliamentLiveEvent>[];
    for (final match in pattern.allMatches(html)) {
      final guid = match.group(1)!;
      if (!seen.add(guid)) continue;
      events.add(
        ParliamentLiveEvent(
          guid: guid,
          title: _decodeHtmlEntities(match.group(2)!).trim(),
        ),
      );
    }
    return events;
  }

  static String _decodeHtmlEntities(String s) {
    return s
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>');
  }

  void dispose() => _client.close();
}

/// Low-level client for the official UK Parliament Bills API.
///
/// Endpoint: https://bills-api.parliament.uk/api/v1/Bills
/// Used to resolve a bill title (parsed from a debate title) to a canonical
/// bill id so the app can deep-link to `https://bills.parliament.uk/bills/{id}`.
class BillsApiService {
  static const String _baseUrl = 'https://bills-api.parliament.uk/api/v1/Bills';

  final http.Client _client;
  final Map<String, int?> _cache = {};
  List<Map<String, dynamic>>? _billTypesCache;

  BillsApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Returns the id of the best matching bill for [title], or `null` if none is
  /// found. Prefers an exact (case-insensitive) `shortTitle` match, otherwise
  /// falls back to the first (most relevant) result. Cached per title.
  Future<int?> findBillId(String title) async {
    final query = title.trim();
    if (query.isEmpty) return null;
    if (_cache.containsKey(query)) return _cache[query];

    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: <String, String>{'SearchTerm': query, 'Take': '20'},
    );

    try {
      final response = await _client.getTimed(uri);
      if (response.statusCode != 200) return _cache[query] = null;
      final body = json.decode(response.body);
      final items = (body is Map<String, dynamic>) ? body['items'] : null;
      if (items is! List || items.isEmpty) return _cache[query] = null;

      final normalizedQuery = query.toLowerCase();
      int? fallbackId;
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final id = item['billId'];
        if (id is! int) continue;
        fallbackId ??= id;
        final shortTitle = (item['shortTitle'] as String?)?.toLowerCase();
        if (shortTitle == normalizedQuery) return _cache[query] = id;
      }
      return _cache[query] = fallbackId;
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return _cache[query] = null;
    }
  }

  /// Searches for bills matching [query], returning the raw API items.
  Future<List<Map<String, dynamic>>> searchBills(
    String query, {
    int take = 20,
  }) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: <String, String>{
        'SearchTerm': trimmed,
        'Take': take.toString(),
      },
    );
    final response = await _client.getTimed(
      uri,
      headers: {'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      throw Exception(
        'Bill search failed (HTTP ${response.statusCode}).',
      );
    }
    final body = json.decode(response.body);
    final items = (body is Map<String, dynamic>) ? body['items'] : null;
    if (items is! List) return const [];
    return items.whereType<Map<String, dynamic>>().toList();
  }

  /// Fetches the list of bill types (e.g. Government Bill, Private Bill).
  Future<List<Map<String, dynamic>>> fetchBillTypes() async {
    final cached = _billTypesCache;
    if (cached != null) return cached;

    final uri = Uri.parse('https://bills-api.parliament.uk/api/v1/BillTypes');
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body);
      final items = (body is Map<String, dynamic>) ? body['items'] : null;
      if (items is! List) return const [];
      final list = items.whereType<Map<String, dynamic>>().toList();
      _billTypesCache = list;
      return list;
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  /// Fetches the most recently updated bills, newest first. Empty on failure.
  Future<List<Map<String, dynamic>>> fetchRecentBills({int skip = 0, int take = 40}) async {
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: <String, String>{
        'SortOrder': 'DateUpdatedDescending',
        'Skip': skip.toString(),
        'Take': take.toString(),
      },
    );
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body);
      final items = (body is Map<String, dynamic>) ? body['items'] : null;
      if (items is! List) return const [];
      return items.whereType<Map<String, dynamic>>().toList();
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  /// Fetches full detail for the bill identified by [id], or `null` on failure.
  Future<Map<String, dynamic>?> fetchBillDetail(int id) async {
    final uri = Uri.parse('$_baseUrl/$id');
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body);
      return body is Map<String, dynamic> ? body : null;
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return null;
    }
  }

  /// Fetches a bill's stage history (1st reading, 2nd reading, …) in the order
  /// the API returns them (chronological). Empty on failure.
  Future<List<Map<String, dynamic>>> fetchBillStages(
    int id, {
    int take = 30,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id/Stages').replace(
      queryParameters: <String, String>{'Take': take.toString()},
    );
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body);
      final items = (body is Map<String, dynamic>) ? body['items'] : null;
      if (items is! List) return const [];
      return items.whereType<Map<String, dynamic>>().toList();
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  /// Fetches recent news articles / updates for a bill, newest first. Empty on
  /// failure.
  Future<List<Map<String, dynamic>>> fetchBillNews(
    int id, {
    int take = 20,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id/NewsArticles').replace(
      queryParameters: <String, String>{'Take': take.toString()},
    );
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body);
      final items = (body is Map<String, dynamic>) ? body['items'] : null;
      if (items is! List) return const [];
      return items.whereType<Map<String, dynamic>>().toList();
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  /// Fetches upcoming bill sittings from `DateFrom` (defaults to today).
  Future<List<Map<String, dynamic>>> fetchComingUpSittings({
    String? dateFrom,
    int skip = 0,
    int take = 50,
  }) async {
    final start = dateFrom ?? DateTime.now().toIso8601String().split('T')[0];
    final uri = Uri.parse('https://bills-api.parliament.uk/api/v1/Sittings')
        .replace(
      queryParameters: <String, String>{
        'DateFrom': start,
        'Take': take.toString(),
      },
    );
    try {
      final response = await _client.getTimed(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body);
      final items = (body is Map<String, dynamic>) ? body['items'] : null;
      if (items is! List) return const [];
      return items.whereType<Map<String, dynamic>>().toList();
    } catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
  }

  void dispose() => _client.close();
}

/// Exception thrown when a Hansard API request fails.
class HansardApiException implements Exception {
  final String message;
  const HansardApiException(this.message);

  @override
  String toString() => 'HansardApiException: $message';
}

/// Exception thrown when a boundary API request fails.
class BoundaryApiException implements Exception {
  final String message;
  const BoundaryApiException(this.message);

  @override
  String toString() => 'BoundaryApiException: $message';
}

/// Low-level HTTP client for UK boundary GeoJSON from ONS ArcGIS services.
class BoundaryApiService {
  static const String _constituencyServiceUrl =
      'https://services1.arcgis.com/ESMARspQHYMw9BZ9/arcgis/rest/services/'
      'Westminster_Parliamentary_Constituencies_July_2024_Boundaries_UK_BFE/'
      'FeatureServer';
  static const String _councilServiceUrl =
      'https://services1.arcgis.com/ESMARspQHYMw9BZ9/arcgis/rest/services/'
      'Local_Authority_Districts_December_2024_Boundaries_UK_BFC/FeatureServer';

  final http.Client _client;

  BoundaryApiService({http.Client? client})
      : _client = client ?? http.Client();

  Future<Map<String, dynamic>> fetchConstituencyBoundaries() => _fetchBoundaries(
        _constituencyServiceUrl,
        // ONS Westminster constituency code + name fields.
        outFields: 'PCON24CD,PCON24NM',
        // Constituencies are small areas, so the default 220 m tolerance still
        // looked blocky when zoomed in. ~55 m gives crisp borders; the payload
        // grows but parses off-isolate and renders fine at this count.
        maxAllowableOffset: _constituencyMaxAllowableOffset,
      );

  Future<Map<String, dynamic>> fetchCouncilBoundaries() => _fetchBoundaries(
        _councilServiceUrl,
        // ONS local-authority-district code + name fields.
        outFields: 'LAD24CD,LAD24NM',
      );

  /// Cap on features requested per page. The server advertises a far larger
  /// maxRecordCount (2000), but asking for that many detailed geometries in one
  /// request makes the gateway exceed our timeout. A few island-heavy seats
  /// (e.g. the Scottish isles) are so detailed that a single one takes ~30s to
  /// simplify and serialise server-side regardless of page size, so we keep
  /// pages small to bound how many heavy features can land in one request.
  static const int _maxPageSize = 50;

  /// How many pages to fetch at once. Kept low: the shared ArcGIS gateway slows
  /// every in-flight request under load, which can push a heavy page past the
  /// timeout, so modest parallelism buys speed without starving the slow ones.
  static const int _pageConcurrency = 3;

  /// Douglas–Peucker simplification tolerance (in `outSR` degrees) applied
  /// server-side. Higher is blockier and lighter, lower is smoother and
  /// heavier. ~0.002° ≈ 220 m keeps borders smooth without jagged stair-steps;
  /// 0.01 (~1.1 km) made constituency outlines visibly blocky. The gateway's
  /// per-page time is dominated by fixed simplification cost, not output size,
  /// so finer detail here costs payload (parsed off-isolate) but not latency.
  /// Councils use this default — but note the hosted council layer *ignores*
  /// this parameter with `f=geojson` and returns full-resolution coastline
  /// (~30 MB); `BoundaryService` re-simplifies client-side after parsing, so
  /// this is best-effort payload reduction only.
  static const double _defaultMaxAllowableOffset = 0.002;

  /// Finer tolerance for constituencies (~55 m). They are small subdivisions
  /// with far fewer vertices each than councils, so this sharpens their outlines
  /// without the cache/render cost that the same value would impose on councils.
  static const double _constituencyMaxAllowableOffset = 0.0005;

  Future<Map<String, dynamic>> _fetchBoundaries(
    String serviceUrl, {
    required String outFields,
    double maxAllowableOffset = _defaultMaxAllowableOffset,
  }) async {
    final layerUrl = '$serviceUrl/0';
    // Order by the first requested field (the unique area code) so that
    // resultOffset paging is stable.
    final orderBy = outFields.split(',').first;
    final serverMax = await _fetchMaxRecordCount(layerUrl);
    final pageSize = math.min(serverMax, _maxPageSize);
    final total = await _fetchCount(layerUrl);

    final offsets = [for (var o = 0; o < total; o += pageSize) o];
    final allFeatures = <Map<String, dynamic>>[];
    // Fetch in concurrency-limited batches; offsets are ascending and
    // Future.wait preserves order, so features stay correctly sequenced.
    for (var i = 0; i < offsets.length; i += _pageConcurrency) {
      final batch = offsets.skip(i).take(_pageConcurrency);
      final pages = await Future.wait([
        for (final offset in batch)
          _fetchPage(
            layerUrl,
            offset: offset,
            pageSize: pageSize,
            outFields: outFields,
            orderBy: orderBy,
            maxAllowableOffset: maxAllowableOffset,
          ),
      ]);
      for (final page in pages) {
        allFeatures.addAll(page);
      }
    }
    return {
      'type': 'FeatureCollection',
      'features': allFeatures,
    };
  }

  /// Status codes worth retrying: ArcGIS's shared gateway returns these
  /// intermittently under load, especially 504 on the larger geometry pages.
  static const Set<int> _transientStatus = {429, 500, 502, 503, 504};
  static const int _maxAttempts = 4;
  // Generous: a handful of island-heavy constituencies take ~30s to render
  // server-side even in a 50-feature page, so 30s timed them out. 60s gives
  // those pages first-attempt headroom; the retry loop covers genuine stalls.
  static const Duration _requestTimeout = Duration(seconds: 60);

  /// GETs [uri], retrying transient gateway failures and network/timeouts with
  /// exponential backoff. Permanent responses (e.g. 200, 404) return straight
  /// away so callers can interpret them; only repeated transient failures throw.
  Future<http.Response> _get(Uri uri) async {
    Object? lastError;
    for (var attempt = 1; attempt <= _maxAttempts; attempt++) {
      try {
        final response = await _client
            .get(uri, headers: {'Accept': 'application/json'})
            .timeout(_requestTimeout);
        if (!_transientStatus.contains(response.statusCode)) {
          return response;
        }
        lastError = BoundaryApiException(
          'Boundary request failed (${response.statusCode}).',
        );
      } on TimeoutException {
        lastError = const BoundaryApiException('Boundary request timed out.');
      } on http.ClientException catch (e) {
        lastError = BoundaryApiException('Boundary request failed: ${e.message}');
      }
      if (attempt < _maxAttempts) {
        // 0.5s, 1s, 2s between attempts.
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (1 << (attempt - 1))),
        );
      }
    }
    throw lastError is BoundaryApiException
        ? lastError
        : BoundaryApiException('Boundary request failed: $lastError');
  }

  Future<int> _fetchMaxRecordCount(String layerUrl) async {
    final uri = Uri.parse('$layerUrl?f=pjson');
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw BoundaryApiException(
        'Boundary layer metadata failed (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    return (body['maxRecordCount'] as num?)?.toInt() ?? 2000;
  }

  Future<int> _fetchCount(String layerUrl) async {
    final uri = Uri.parse('$layerUrl/query').replace(
      queryParameters: const {
        'where': '1=1',
        'returnCountOnly': 'true',
        'f': 'json',
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw BoundaryApiException(
        'Boundary count query failed (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final count = body['count'];
    if (count is! num) {
      throw const FormatException('Boundary count response is invalid.');
    }
    return count.toInt();
  }

  Future<List<Map<String, dynamic>>> _fetchPage(
    String layerUrl, {
    required int offset,
    required int pageSize,
    required String outFields,
    required String orderBy,
    required double maxAllowableOffset,
  }) async {
    final uri = Uri.parse('$layerUrl/query').replace(
      queryParameters: {
        'where': '1=1',
        'outFields': outFields,
        'returnGeometry': 'true',
        'orderByFields': orderBy,
        'f': 'geojson',
        'outSR': '4326',
        'resultOffset': offset.toString(),
        'resultRecordCount': pageSize.toString(),
        'geometryPrecision': '5',
        'maxAllowableOffset': maxAllowableOffset.toString(),
      },
    );
    final response = await _get(uri);
    if (response.statusCode != 200) {
      throw BoundaryApiException(
        'Boundary query failed (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final features = body['features'];
    if (features is! List) {
      throw const FormatException('Boundary query returned invalid features.');
    }
    return features.whereType<Map<String, dynamic>>().toList();
  }

  void dispose() => _client.close();
}

/// Thrown when the OpenCouncilData control table cannot be fetched.
class CouncilControlApiException implements Exception {
  final String message;
  const CouncilControlApiException(this.message);

  @override
  String toString() => 'CouncilControlApiException: $message';
}

/// Fetches political control of every GB local authority from OpenCouncilData.
///
/// There is no Parliament API for council control; OpenCouncilData publishes it
/// as an HTML table at `councils.php`, which we scrape into council → control.
class CouncilControlApiService {
  static const String _url =
      'https://opencouncildata.co.uk/councils.php?model=&y=0';

  final http.Client _client;

  CouncilControlApiService({http.Client? client})
      : _client = client ?? http.Client();

  Future<List<Council>> fetchCouncils({int? year}) async {
    final Uri uri;
    if (year != null && year > 0) {
      if (year >= 2016) {
        uri = Uri.parse('https://opencouncildata.co.uk/historyYear16.php?y=$year');
      } else {
        uri = Uri.parse('https://opencouncildata.co.uk/historyYear73.php?y=$year');
      }
    } else {
      uri = Uri.parse(_url);
    }
    final response = await _client.getTimed(
      uri,
      headers: {
        'Accept': 'text/html',
        'User-Agent': 'open-hansard/1.0',
      },
    );
    if (response.statusCode != 200) {
      throw CouncilControlApiException(
        'Council control fetch failed (${response.statusCode}).',
      );
    }
    final List<Council> councils;
    if (year != null && year > 0) {
      if (year >= 2016) {
        councils = parseHistoricalCouncils16(response.body);
      } else {
        councils = parseHistoricalCouncils73(response.body);
      }
    } else {
      councils = parseCouncils(response.body);
    }
    if (councils.isEmpty) {
      throw const CouncilControlApiException(
        'Council control table was empty or unparseable.',
      );
    }
    return councils;
  }

  void dispose() => _client.close();
}

/// Thrown when the OpenCouncilData councillors CSV cannot be fetched.
class CouncillorApiException implements Exception {
  final String message;
  const CouncillorApiException(this.message);

  @override
  String toString() => 'CouncillorApiException: $message';
}

/// Fetches every UK councillor (name, ward, party) from OpenCouncilData's free
/// annual CSV at `csv2.php?y=<year>`.
///
/// The snapshot is published shortly after each May election, so early in a
/// year the current-year file may not exist yet — we fall back one year.
class CouncillorApiService {
  static String _url(int year) =>
      'https://opencouncildata.co.uk/csv2.php?y=$year';

  final http.Client _client;

  CouncillorApiService({http.Client? client})
      : _client = client ?? http.Client();

  Future<List<Councillor>> fetchCouncillors({int? year}) async {
    final wanted = year ?? DateTime.now().toUtc().year;
    // Try the requested year, then the previous one if it isn't published yet.
    for (final y in {wanted, wanted - 1}) {
      final councillors = await _fetchYear(y);
      if (councillors.isNotEmpty) return councillors;
    }
    throw const CouncillorApiException(
      'Councillor CSV was empty or unavailable.',
    );
  }

  Future<List<Councillor>> _fetchYear(int year) async {
    final http.Response response;
    try {
      response = await _client.getTimed(
        Uri.parse(_url(year)),
        headers: {
          'Accept': 'text/csv',
          'User-Agent': 'open-hansard/1.0',
        },
      );
    } on Object catch (e, st) {
      _reportSilentFailure(e, st);
      return const [];
    }
    if (response.statusCode != 200) return const [];
    return parseCouncillors(response.body);
  }

  void dispose() => _client.close();
}

/// One elected person in a council's Democracy Club ballots — the join row
/// between an OpenCouncilData councillor and a DC person id (and so a photo).
class DcElectedCandidate {
  final int personId;
  final String name;
  final String ward;
  final String party;

  const DcElectedCandidate({
    required this.personId,
    required this.name,
    required this.ward,
    required this.party,
  });

  Map<String, dynamic> toJson() => {
        'personId': personId,
        'name': name,
        'ward': ward,
        'party': party,
      };

  factory DcElectedCandidate.fromJson(Map<String, dynamic> json) =>
      DcElectedCandidate(
        personId: (json['personId'] as num?)?.toInt() ?? 0,
        name: (json['name'] as String?) ?? '',
        ward: (json['ward'] as String?) ?? '',
        party: (json['party'] as String?) ?? '',
      );
}

/// Read-only client for Democracy Club's Candidates API (CC BY 4.0).
///
/// DC has no person-name search, so we reach a councillor's photo via their
/// council's local-election ballots: list the elected people per `election_id`,
/// then fetch the matched person for their image and contact details.
class DemocracyClubApiService {
  static const String _baseUrl =
      'https://candidates.democracyclub.org.uk/api/next';

  /// Cap on ballot pages per election to bound a cold roster build.
  static const int _maxBallotPages = 6;

  final http.Client _client;

  DemocracyClubApiService({http.Client? client})
      : _client = client ?? http.Client();

  /// Every person recorded as elected across [slug]'s recent local elections,
  /// deduplicated by person id. Councils that elect by thirds appear under
  /// several election dates, so we union them all. Returns an empty list on
  /// failure — enrichment is best-effort.
  Future<List<DcElectedCandidate>> fetchElectedForCouncil(String slug) async {
    final byPerson = <int, DcElectedCandidate>{};
    for (final date in kLocalElectionDates) {
      await _collectElected('local.$slug.$date', byPerson);
    }
    return byPerson.values.toList();
  }

  Future<void> _collectElected(
    String electionId,
    Map<int, DcElectedCandidate> out,
  ) async {
    var uri = Uri.parse(
      '$_baseUrl/ballots/?format=json&page_size=200&election_id=$electionId',
    );
    for (var page = 0; page < _maxBallotPages; page++) {
      final Map<String, dynamic> body;
      try {
        final response = await _client.getTimed(uri);
        if (response.statusCode != 200) return;
        body = jsonDecode(response.body) as Map<String, dynamic>;
      } on Object catch (e, st) {
        _reportSilentFailure(e, st);
        return;
      }
      for (final ballot in (body['results'] as List<dynamic>? ?? const [])) {
        if (ballot is! Map<String, dynamic>) continue;
        final ward = ((ballot['post'] as Map<String, dynamic>?)?['label']
                as String?) ??
            '';
        for (final c
            in (ballot['candidacies'] as List<dynamic>? ?? const [])) {
          if (c is! Map<String, dynamic> || c['elected'] != true) continue;
          final person = c['person'] as Map<String, dynamic>?;
          final id = (person?['id'] as num?)?.toInt();
          if (id == null) continue;
          out[id] = DcElectedCandidate(
            personId: id,
            name: (person?['name'] as String?) ?? '',
            ward: ward,
            party: (c['party_name'] as String?) ?? '',
          );
        }
      }
      final next = body['next'] as String?;
      if (next == null || next.isEmpty) return;
      uri = Uri.parse(next);
    }
  }

  /// Fetches a single person's profile (photo, email, links, election history),
  /// or null on failure.
  Future<CouncillorProfile?> fetchPerson(int personId) async {
    try {
      final response = await _client
          .getTimed(Uri.parse('$_baseUrl/people/$personId/?format=json'));
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return CouncillorProfile.fromPersonJson(body);
    } on Object catch (e, st) {
      _reportSilentFailure(e, st);
      return null;
    }
  }

  void dispose() => _client.close();
}
