import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/debate.dart';
import '../models/member.dart';
import '../models/parliament_live_event.dart';
import '../models/speech.dart';

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
      final response = await _client.get(
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
      final response = await _client.get(
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
    } catch (_) {
      return null;
    }
  }

  /// Fetches extended detail for a single member (constituency, house, start date).
  ///
  /// Returns the unwrapped `value` object from the API, or null on failure.
  Future<Map<String, dynamic>?> fetchMemberDetail(int id) async {
    final uri = Uri.parse('$_baseUrl/$id');
    try {
      final response = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['value'] as Map<String, dynamic>?) ?? body;
    } catch (_) {
      return null;
    }
  }

  /// Fetches the biography for a member (government/opposition posts, party history).
  ///
  /// Returns the unwrapped `value` object from the API, or null on failure.
  Future<Map<String, dynamic>?> fetchMemberBiography(int id) async {
    final uri = Uri.parse('$_baseUrl/$id/Biography');
    try {
      final response = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return (body['value'] as Map<String, dynamic>?) ?? body;
    } catch (_) {
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
      final response = await _client.get(
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
    } catch (_) {
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
      final sectionsResponse = await _client.get(
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
        final treeResponse = await _client.get(
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
    final response = await _client.get(
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
      final response = await _client.get(
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
      final response = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final results = (body['Results'] as List<dynamic>?) ?? [];
      return results.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
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
      final response = await _client.get(uri);
      if (response.statusCode != 200) return const [];
      final events = parseSearchHtml(response.body);
      _cache[date] = events;
      return events;
    } catch (_) {
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
      final response = await _client.get(uri);
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
    } catch (_) {
      return _cache[query] = null;
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
      final response = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body);
      final items = (body is Map<String, dynamic>) ? body['items'] : null;
      if (items is! List) return const [];
      return items.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetches full detail for the bill identified by [id], or `null` on failure.
  Future<Map<String, dynamic>?> fetchBillDetail(int id) async {
    final uri = Uri.parse('$_baseUrl/$id');
    try {
      final response = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return null;
      final body = json.decode(response.body);
      return body is Map<String, dynamic> ? body : null;
    } catch (_) {
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
      final response = await _client.get(
        uri,
        headers: {'Accept': 'application/json'},
      );
      if (response.statusCode != 200) return const [];
      final body = json.decode(response.body);
      final items = (body is Map<String, dynamic>) ? body['items'] : null;
      if (items is! List) return const [];
      return items.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return const [];
    }
  }

  /// Fetches recent news articles / updates for a bill, newest first. Empty on
  /// failure.
  Future<List<Map<String, dynamic>>> fetchBillNews(int id, {int take = 20}) async { final uri = Uri.parse("$_baseUrl/$id/NewsArticles").replace(queryParameters: <String, String>{"Take": take.toString()}); try { final response = await _client.get(uri, headers: {"Accept": "application/json"}); if (response.statusCode != 200) return const []; final body = json.decode(response.body); final items = (body is Map<String, dynamic>) ? body["items"] : null; if (items is! List) return const []; return items.whereType<Map<String, dynamic>>().toList(); } catch (_) { return const []; } }

  /// Fetches upcoming bill sittings from `DateFrom` (defaults to today).
  Future<List<Map<String, dynamic>>> fetchComingUpSittings({String? dateFrom, int skip = 0, int take = 50}) async { final start = dateFrom ?? DateTime.now().toIso8601String().split("T")[0]; final uri = Uri.parse("https://bills-api.parliament.uk/api/v1/Sittings").replace(queryParameters: <String, String>{"DateFrom": start, "Take": take.toString()}); try { final response = await _client.get(uri, headers: {"Accept": "application/json"}); if (response.statusCode != 200) return const []; final body = json.decode(response.body); final items = (body is Map<String, dynamic>) ? body["items"] : null; if (items is! List) return const []; return items.whereType<Map<String, dynamic>>().toList(); } catch (_) { return const []; } }

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

  Future<Map<String, dynamic>> fetchConstituencyBoundaries() =>
      _fetchBoundaries(_constituencyServiceUrl);

  Future<Map<String, dynamic>> fetchCouncilBoundaries() =>
      _fetchBoundaries(_councilServiceUrl);

  Future<Map<String, dynamic>> _fetchBoundaries(String serviceUrl) async {
    final layerUrl = '$serviceUrl/0';
    final pageSize = await _fetchMaxRecordCount(layerUrl);
    final total = await _fetchCount(layerUrl);
    final allFeatures = <Map<String, dynamic>>[];
    int offset = 0;
    while (offset < total) {
      final page = await _fetchPage(
        layerUrl,
        offset: offset,
        pageSize: pageSize,
      );
      allFeatures.addAll(page);
      offset += page.length;
      if (page.isEmpty) break;
    }
    return {
      'type': 'FeatureCollection',
      'features': allFeatures,
    };
  }

  Future<int> _fetchMaxRecordCount(String layerUrl) async {
    final uri = Uri.parse('$layerUrl?f=pjson');
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
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
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
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
  }) async {
    final uri = Uri.parse('$layerUrl/query').replace(
      queryParameters: {
        'where': '1=1',
        'outFields': 'OBJECTID',
        'returnGeometry': 'true',
        'orderByFields': 'OBJECTID',
        'f': 'geojson',
        'outSR': '4326',
        'resultOffset': offset.toString(),
        'resultRecordCount': pageSize.toString(),
        'geometryPrecision': '5',
        'maxAllowableOffset': '0.01',
      },
    );
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );
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
