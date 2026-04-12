import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/debate.dart';
import '../models/member.dart';
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

      skip += pageSize;

      final totalResults = (body['totalResults'] as num?)?.toInt() ?? 0;
      if (skip >= totalResults) {
        break;
      }
    }

    return members;
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

          final rootSection = _extractRootSectionNode(treeItem);
          if (rootSection == null) {
            continue;
          }

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
              house: currentHouse,
              orderIndex: orderIndex++,
            ),
          );
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

  void dispose() => _client.close();

  Map<String, dynamic>? _extractRootSectionNode(Map<String, dynamic> treeItem) {
    final sectionTreeItems = treeItem['SectionTreeItems'];
    if (sectionTreeItems is! List<dynamic> || sectionTreeItems.isEmpty) {
      return null;
    }

    for (final item in sectionTreeItems) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final parentId = item['ParentId'];
      final externalId = item['ExternalId'] ?? item['externalId'];
      if (parentId == null && externalId is String && externalId.isNotEmpty) {
        return item;
      }
    }

    // Fallback to the first node that has an ExternalId.
    for (final item in sectionTreeItems) {
      if (item is! Map<String, dynamic>) {
        continue;
      }
      final externalId = item['ExternalId'] ?? item['externalId'];
      if (externalId is String && externalId.isNotEmpty) {
        return item;
      }
    }
    return null;
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

/// Exception thrown when a Hansard API request fails.
class HansardApiException implements Exception {
  final String message;
  const HansardApiException(this.message);

  @override
  String toString() => 'HansardApiException: $message';
}
