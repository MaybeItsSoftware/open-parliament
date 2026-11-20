import 'package:flutter/foundation.dart';

import '../models/amendment.dart';
import '../models/boundary.dart';
import '../models/member.dart';
import '../models/member_contribution.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/amendment_ref.dart';

/// How a member was recorded in a division.
enum VotePosition { aye, no, teller, absent }

/// A single recorded division (vote) for a member.
class MemberVote {
  final int divisionId;
  final String title;
  final DateTime date;
  final VotePosition position;
  final int? ayeCount;
  final int? noCount;

  const MemberVote({
    required this.divisionId,
    required this.title,
    required this.date,
    required this.position,
    this.ayeCount,
    this.noCount,
  });

  /// Parses the unwrapped `value` object from the Members API Voting endpoint.
  ///
  /// The vote is flat in the object — there is no nested division wrapper.
  factory MemberVote.fromJson(Map<String, dynamic> json) {
    final rawDate = (json['date'] as String?) ?? '';
    final date = DateTime.tryParse(rawDate) ?? DateTime(1970);
    final teller = (json['actedAsTeller'] as bool?) ?? false;
    final aye = (json['inAffirmativeLobby'] as bool?) ?? false;
    final no = (json['inNegativeLobby'] as bool?) ?? false;
    return MemberVote(
      divisionId: (json['id'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',
      date: DateTime(date.year, date.month, date.day),
      position: teller
          ? VotePosition.teller
          : aye
              ? VotePosition.aye
              : no
                  ? VotePosition.no
                  : VotePosition.absent,
      ayeCount: (json['numberInFavour'] as num?)?.toInt(),
      noCount: (json['numberAgainst'] as num?)?.toInt(),
    );
  }
}

/// A set of divisions that belong to the same bill or topic, newest first.
class VoteGroup {
  final String title;
  final List<MemberVote> votes;

  const VoteGroup({required this.title, required this.votes});
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
  final ParliamentaryDataService _service;

  bool _isLoading = true;
  bool _disposed = false;
  String? _error;
  String? _constituency;
  int? _house; // 1 = Commons, 2 = Lords
  DateTime? _membershipStartDate;
  List<BoundaryPolygon> _constituencyBoundaries = const [];
  List<MemberContribution> _contributions = const [];
  int _contributionsTotal = 0;
  List<BiographyPost> _governmentPosts = const [];
  List<BiographyPost> _oppositionPosts = const [];
  final List<MemberVote> _votes = [];
  final Map<String, int?> _voteGroupBillIds = {};
  final Map<int, Future<DivisionAmendment>> _amendments = {};

  // Voting history is paged (20 per API page, 1-indexed) and loaded lazily as
  // the profile is scrolled.
  static const int _votesPageSize = 20;
  int _votesPage = 0; // highest page fetched so far
  bool _isLoadingMoreVotes = false;
  bool _hasMoreVotes = true;

  MemberViewModel(this._service, {required this.member});

  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get constituency => _constituency;
  int? get house => _house;
  DateTime? get membershipStartDate => _membershipStartDate;
  /// The Commons seat's outline for the profile map; empty for peers or when
  /// the boundary couldn't be fetched.
  List<BoundaryPolygon> get constituencyBoundaries => _constituencyBoundaries;
  /// The few most recent speeches shown on the profile; the full, paged list
  /// lives on its own screen (`MemberSpeechesView`).
  List<MemberContribution> get contributions => _contributions;

  /// How many spoken contributions Hansard holds for this member.
  int get contributionsTotal => _contributionsTotal;

  /// Speeches previewed on the profile before "All speeches".
  static const int contributionsPreviewCount = 5;
  List<BiographyPost> get governmentPosts => _governmentPosts;
  List<BiographyPost> get oppositionPosts => _oppositionPosts;
  List<MemberVote> get votes => List.unmodifiable(_votes);
  bool get isLoadingMoreVotes => _isLoadingMoreVotes;
  bool get hasMoreVotes => _hasMoreVotes;
  bool get isLord => _house == 2;

  /// The loaded votes grouped by bill/topic, preserving newest-first order.
  ///
  /// The group key is the part of the division title before the first colon
  /// (e.g. "Victims and Courts Bill: motion to disagree with Lords Amendment 6"
  /// groups under "Victims and Courts Bill"); titles without a colon form their
  /// own single-division group.
  List<VoteGroup> get voteGroups {
    final order = <String>[];
    final byKey = <String, List<MemberVote>>{};
    for (final vote in _votes) {
      final key = vote.title.split(':').first.trim();
      final bucket = byKey.putIfAbsent(key, () {
        order.add(key);
        return [];
      });
      bucket.add(vote);
    }
    return [
      for (final key in order) VoteGroup(title: key, votes: byKey[key]!),
    ];
  }

  /// Resolves the bill id (if any) for a vote-group title, caching results.
  Future<int?> findBillIdForVoteGroup(String title) async {
    final key = title.trim();
    if (key.isEmpty) return null;
    if (_voteGroupBillIds.containsKey(key)) return _voteGroupBillIds[key];
    final id = await _service.findBillId(key);
    _voteGroupBillIds[key] = id;
    return id;
  }

  /// Whether tapping [vote] can show what was voted on. Lords divisions
  /// always carry motion notes; Commons ones only when the title names a
  /// numbered amendment.
  bool canShowAmendment(MemberVote vote) =>
      isLord || parseCommonsDivisionTitle(vote.title) != null;

  /// The amendment (and, for the Lords, the motion text) behind [vote].
  /// Memoised per division; a failed lookup is dropped so it can be retried.
  Future<DivisionAmendment> amendmentFor(MemberVote vote) {
    return _amendments.putIfAbsent(vote.divisionId, () async {
      try {
        return await _service.fetchDivisionAmendment(
          divisionId: vote.divisionId,
          house: _house ?? 1,
          title: vote.title,
          date: vote.date,
        );
      } catch (_) {
        _amendments.remove(vote.divisionId);
        rethrow;
      }
    });
  }

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _safeNotify();

    try {
      // Fire all three requests in parallel.
      final detailFuture = _service.fetchMemberDetail(member.id);
      final biographyFuture = _service.fetchMemberBiography(member.id);
      final contributionsFuture = _service.fetchMemberContributions(
        member.id,
        take: contributionsPreviewCount,
      );

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

      // Commons MPs only. Runs alongside the voting-history fetch below.
      final constituency = _constituency;
      final boundaryFuture =
          _house == 1 && constituency != null && constituency.isNotEmpty
              ? _service.fetchConstituencyBoundary(constituency)
              : Future.value(const <BoundaryPolygon>[]);

      _contributions = parseMemberContributions(rawContributions.items);
      _contributionsTotal = rawContributions.total;

      // Voting history is scoped to the member's house; only fetch the first
      // page once the house has been resolved from the detail response.
      // Subsequent pages are pulled lazily via [loadMoreVotes] while scrolling.
      _votes.clear();
      _votesPage = 0;
      _hasMoreVotes = true;
      await _fetchNextVotesPage();

      _constituencyBoundaries = await boundaryFuture;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    _safeNotify();
  }

  /// Fetches the next page of voting history and appends it, deduping by
  /// division id. Notifies listeners and toggles [isLoadingMoreVotes].
  ///
  /// Safe to call repeatedly (e.g. from a scroll listener) — it no-ops while a
  /// fetch is in flight or once the history is exhausted.
  Future<void> loadMoreVotes() async {
    if (_isLoadingMoreVotes || !_hasMoreVotes) return;
    _isLoadingMoreVotes = true;
    _safeNotify();
    try {
      await _fetchNextVotesPage();
    } finally {
      _isLoadingMoreVotes = false;
      _safeNotify();
    }
  }

  Future<void> _fetchNextVotesPage() async {
    final raw = await _service.fetchMemberVoting(
      member.id,
      house: _house ?? 1,
      page: _votesPage + 1,
    );
    _votesPage++;
    if (raw.length < _votesPageSize) _hasMoreVotes = false;

    final seen = _votes.map((v) => v.divisionId).toSet();
    for (final json in raw) {
      MemberVote? vote;
      try {
        vote = MemberVote.fromJson(json);
      } catch (_) {
        vote = null;
      }
      if (vote == null || vote.title.isEmpty) continue;
      if (!seen.add(vote.divisionId)) continue;
      _votes.add(vote);
    }
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

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
