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
/// Primary:  https://hansard-api.parliament.uk/v1/sittings/{date}.json
/// Fallback: https://hansard-api.parliament.uk/v1/debates/debate/{id}.json
class HansardApiService {
  static const String _baseUrl = 'https://hansard-api.parliament.uk/v1';

  final http.Client _client;

  HansardApiService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetches the list of debate sections for [date] (YYYY-MM-DD).
  ///
  /// Uses the primary endpoint `/v1/sittings/{date}.json` as specified.
  /// If [house] is provided it is appended as a path segment to scope the
  /// results (e.g. `Commons` or `Lords`), which is the common real-world
  /// format.  Omit [house] to use the bare spec URL.
  ///
  /// The sittings endpoint returns a list of top-level debate sections, each
  /// with an `ExternalId` used to fetch full speech content.
  Future<List<Debate>> fetchSittingDebates(
    String date, {
    String? house,
  }) async {
    final path = house != null
        ? '$_baseUrl/sittings/$house/$date.json'
        : '$_baseUrl/sittings/$date.json';
    final uri = Uri.parse(path);
    final response = await _client.get(
      uri,
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw HansardApiException(
        'Failed to fetch sittings for $date: HTTP ${response.statusCode}',
      );
    }

    final dynamic raw = jsonDecode(response.body);

    // The endpoint may return a JSON array or a wrapped object.
    final List<dynamic> items;
    if (raw is List<dynamic>) {
      items = raw;
    } else if (raw is Map<String, dynamic>) {
      items = (raw['Response'] as List<dynamic>?) ?? [];
    } else {
      items = [];
    }

    final debates = <Debate>[];
    for (int i = 0; i < items.length; i++) {
      try {
        debates.add(
          Debate.fromApiJson(items[i] as Map<String, dynamic>, orderIndex: i),
        );
      } catch (_) {
        // Skip malformed debate entries.
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

    if (response.statusCode != 200) {
      throw HansardApiException(
        'Failed to fetch debate $debateId: HTTP ${response.statusCode}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;

    // Speeches are in an `Items` array at the top level or nested under
    // `Overview` / `Contributions` depending on API version.
    final List<dynamic> items = (body['Items'] as List<dynamic>?) ??
        (body['items'] as List<dynamic>?) ??
        [];

    final speeches = <Speech>[];
    for (int i = 0; i < items.length; i++) {
      try {
        speeches.add(
          Speech.fromApiJson(
            items[i] as Map<String, dynamic>,
            debateId: debateId,
            debateTitle: debateTitle,
            orderIndex: i,
          ),
        );
      } catch (_) {
        // Skip malformed individual contributions.
      }
    }
    return speeches;
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
