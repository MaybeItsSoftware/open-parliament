import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/member.dart';
import '../services/api_services.dart';

/// A recent Hansard contribution fetched from the search API.
class MemberContribution {
  final String debateTitle;
  final String debateSectionId;
  final DateTime sittingDate;
  final String house;
  final String text;

  const MemberContribution({
    required this.debateTitle,
    required this.debateSectionId,
    required this.sittingDate,
    required this.house,
    required this.text,
  });

  factory MemberContribution.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['SittingDate'] as String?) ?? '';
    final date = DateTime.tryParse(rawDate) ?? DateTime(1970);
    final rawText = (json['Contribution'] as String?) ?? '';
    return MemberContribution(
      debateTitle: (json['DebateSection'] as String?) ?? '',
      debateSectionId: (json['DebateSectionExtId'] as String?) ??
          (json['DebateSectionId'] as String?) ??
          '',
      sittingDate: DateTime(date.year, date.month, date.day),
      house: (json['House'] as String?) ?? '',
      text: _stripHtml(rawText),
    );
  }

  static String _stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&mdash;', '—')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }
}

/// A government or opposition post held by a member.
class BiographyPost {
  final String name;
  final DateTime? startDate;
  final DateTime? endDate;

  bool get isCurrent => endDate == null;

  const BiographyPost({
    required this.name,
    this.startDate,
    this.endDate,
  });
}

/// Loads member profile detail, biography posts, and recent contributions.
class MemberViewModel extends ChangeNotifier {
  final Member member;
  final MembersApiService _membersApi;
  final HansardApiService _hansardApi;

  bool _isLoading = true;
  String? _error;
  String? _constituency;
  int? _house; // 1 = Commons, 2 = Lords
  DateTime? _membershipStartDate;
  LatLng? _constituencyLatLng;
  List<MemberContribution> _contributions = const [];
  List<BiographyPost> _governmentPosts = const [];
  List<BiographyPost> _oppositionPosts = const [];

  MemberViewModel({required this.member})
      : _membersApi = MembersApiService(),
        _hansardApi = HansardApiService();

  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get constituency => _constituency;
  int? get house => _house;
  DateTime? get membershipStartDate => _membershipStartDate;
  LatLng? get constituencyLatLng => _constituencyLatLng;
  List<MemberContribution> get contributions => _contributions;
  List<BiographyPost> get governmentPosts => _governmentPosts;
  List<BiographyPost> get oppositionPosts => _oppositionPosts;
  bool get isLord => _house == 2;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // Fire all three requests in parallel.
      final detailFuture = _membersApi.fetchMemberDetail(member.id);
      final biographyFuture = _membersApi.fetchMemberBiography(member.id);
      final contributionsFuture = _hansardApi.fetchMemberContributions(member.id);

      final detail = await detailFuture;
      final biography = await biographyFuture;
      final rawContributions = await contributionsFuture;

      if (detail != null) {
        final membership =
            detail['latestHouseMembership'] as Map<String, dynamic>?;
        _constituency = membership?['membershipFrom'] as String?;
        _house = (membership?['house'] as num?)?.toInt();
        final startRaw = membership?['membershipStartDate'] as String?;
        if (startRaw != null) {
          final parsed = DateTime.tryParse(startRaw);
          _membershipStartDate =
              parsed != null ? DateTime(parsed.year, parsed.month, parsed.day) : null;
        }
      }

      if (biography != null) {
        _governmentPosts = _parsePosts(
          biography['governmentPosts'] as List<dynamic>? ?? const [],
        );
        _oppositionPosts = _parsePosts(
          biography['oppositionPosts'] as List<dynamic>? ?? const [],
        );
      }

      _contributions = rawContributions
          .map((json) {
            try {
              return MemberContribution.fromJson(json);
            } catch (_) {
              return null;
            }
          })
          .whereType<MemberContribution>()
          .where((c) => c.debateTitle.isNotEmpty)
          .toList();

      // Geocode constituency for Commons MPs only.
      if (_house == 1 && _constituency != null && _constituency!.isNotEmpty) {
        final coords = await _membersApi.geocodeConstituency(_constituency!);
        if (coords != null) {
          _constituencyLatLng = LatLng(coords[0], coords[1]);
        }
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  List<BiographyPost> _parsePosts(List<dynamic> posts) {
    return posts
        .whereType<Map<String, dynamic>>()
        .map((post) {
          final name = (post['name'] as String?) ?? '';
          if (name.isEmpty) return null;
          final startRaw = post['startDate'] as String?;
          final endRaw = post['endDate'] as String?;
          return BiographyPost(
            name: name,
            startDate: startRaw != null ? DateTime.tryParse(startRaw) : null,
            endDate: endRaw != null ? DateTime.tryParse(endRaw) : null,
          );
        })
        .whereType<BiographyPost>()
        .toList();
  }

  @override
  void dispose() {
    _membersApi.dispose();
    _hansardApi.dispose();
    super.dispose();
  }
}
