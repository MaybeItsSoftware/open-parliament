import 'package:flutter/foundation.dart';

import '../services/parliamentary_data_service.dart';

/// A lightweight bill entry for the recent-bills list.
class BillListItem {
  final int id;
  final String title;
  final String house;
  final String? stageDescription;
  final DateTime? lastUpdate;
  final DateTime? nextSitting;

  const BillListItem({
    required this.id,
    required this.title,
    required this.house,
    this.stageDescription,
    this.lastUpdate,
    this.nextSitting,
  });

  factory BillListItem.fromJson(Map<String, dynamic> json) {
    final currentStage = json['currentStage'] as Map<String, dynamic>?;
    final lastRaw = json["lastUpdate"] as String?;
    final nextRaw = json["_nextSittingDate"] as String?;
    return BillListItem(
      id: (json['billId'] as num?)?.toInt() ?? 0,
      title: (json['shortTitle'] as String?) ?? '',
      house: (json['currentHouse'] as String?) ?? '',
      stageDescription: currentStage?['description'] as String?,
      lastUpdate: lastRaw != null ? DateTime.tryParse(lastRaw) : null,
      nextSitting: nextRaw != null ? DateTime.tryParse(nextRaw) : null,
    );
  }
}

/// Loads the most recently updated bills for the recent-bills screen.
class BillsListViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _disposed = false;
  String? _error;
  bool _showComingUp = false;
  List<BillListItem> _bills = [];

  BillsListViewModel(this._service);

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  bool get showComingUp => _showComingUp;
  List<BillListItem> get bills => _bills;

  void toggleComingUp(bool value) {
    _showComingUp = value;
    load();
  }

  Future<void> load() async {
    _isLoading = true;
    _hasMore = true;
    _error = null;
    _safeNotify();

    try {
      final raw = _showComingUp
          ? await _service.fetchComingUpBills(skip: 0)
          : await _service.fetchRecentBills(skip: 0);
      _bills = raw
          .map((json) {
            try {
              return BillListItem.fromJson(json);
            } catch (_) {
              return null;
            }
          })
          .whereType<BillListItem>()
          .where((b) => b.id != 0 && b.title.isNotEmpty)
          .toList();
      _hasMore = raw.length >= (_showComingUp ? 50 : 40);
      if (_bills.isEmpty) {
        _error = _showComingUp
            ? "No upcoming bill sittings found."
            : "Could not load recent bills.";
      }
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    _safeNotify();
  }

  Future<void> loadMore() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    _safeNotify();

    try {
      final skip = _bills.length;
      final raw = _showComingUp
          ? await _service.fetchComingUpBills(skip: skip)
          : await _service.fetchRecentBills(skip: skip);

      final more = raw
          .map((json) {
            try {
              return BillListItem.fromJson(json);
            } catch (_) {
              return null;
            }
          })
          .whereType<BillListItem>()
          .where((b) => b.id != 0 && b.title.isNotEmpty)
          .toList();

      _bills.addAll(more);
      _hasMore = raw.length >= (_showComingUp ? 50 : 40);
    } catch (e) {
      // Silently fail on load more, or maybe add a message.
    }

    _isLoadingMore = false;
    _safeNotify();
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
