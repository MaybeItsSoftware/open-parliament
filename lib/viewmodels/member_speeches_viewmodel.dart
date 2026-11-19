import 'package:flutter/foundation.dart';

import '../models/member.dart';
import '../models/member_contribution.dart';
import '../services/parliamentary_data_service.dart';

/// Every recorded spoken contribution by one member, newest first, loaded a
/// page at a time as the list is scrolled.
class MemberSpeechesViewModel extends ChangeNotifier {
  final Member member;
  final ParliamentaryDataService _service;

  static const int pageSize = 20;

  final List<MemberContribution> _speeches = [];
  final Set<String> _seen = {};
  int _fetched = 0; // raw rows requested so far — the API skip offset
  int _total = 0;
  bool _isLoading = false;
  bool _hasMore = true;
  bool _failed = false;
  bool _disposed = false;

  MemberSpeechesViewModel(this._service, {required this.member});

  List<MemberContribution> get speeches => List.unmodifiable(_speeches);
  int get total => _total;
  bool get isLoading => _isLoading;
  bool get hasMore => _hasMore;

  /// True when the last page request came back empty with nothing on record,
  /// which the API also returns when offline.
  bool get failed => _failed;

  /// Loads the first page, discarding anything already loaded.
  Future<void> refresh() async {
    _speeches.clear();
    _seen.clear();
    _fetched = 0;
    _total = 0;
    _hasMore = true;
    _failed = false;
    await loadMore(force: true);
  }

  /// Appends the next page. No-ops while a page is in flight or once the
  /// history is exhausted, so it is safe to call from a scroll listener.
  Future<void> loadMore({bool force = false}) async {
    if (_isLoading || (!_hasMore && !force)) return;
    _isLoading = true;
    _notify();
    try {
      final page = await _service.fetchMemberContributions(
        member.id,
        skip: _fetched,
        take: pageSize,
      );
      _fetched += page.items.length;
      if (page.total > 0) _total = page.total;
      _failed = page.items.isEmpty && _speeches.isEmpty && page.total == 0;
      for (final c in parseMemberContributions(page.items)) {
        // Pages can shift by a row if Hansard publishes mid-scroll.
        final key = c.speechId.isNotEmpty
            ? c.speechId
            : '${c.debateSectionId}|${c.text.hashCode}';
        if (_seen.add(key)) _speeches.add(c);
      }
      _hasMore = page.items.length == pageSize && _fetched < _total;
    } catch (_) {
      _hasMore = false;
      _failed = _speeches.isEmpty;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
