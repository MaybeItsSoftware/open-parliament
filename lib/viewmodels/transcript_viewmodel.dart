import 'package:flutter/foundation.dart';

import '../models/member.dart';
import '../models/speech.dart';
import '../services/parliamentary_data_service.dart';

/// Represents a unique speaker and the index of their first speech in the
/// current transcript list (used for Jump-to-Member scrolling).
class SpeakerEntry {
  final String name;
  final int? memberId;
  final int firstSpeechIndex;

  const SpeakerEntry({
    required this.name,
    required this.memberId,
    required this.firstSpeechIndex,
  });
}

/// View-model for [TranscriptView].
///
/// Loads speeches for a given sitting date, and exposes:
///  - the full ordered list of [Speech] objects for the SliverList.
///  - a deduplicated [speakers] list for the Jump-to-Member drawer.
///  - per-member profile data (portrait URL, party) from the local members DB.
class TranscriptViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;
  final String date;

  TranscriptViewModel(this._service, {required this.date});

  List<Speech> _speeches = [];
  Map<int, Member> _memberCache = {};
  List<SpeakerEntry> _speakers = [];
  bool _isLoading = false;
  String? _error;

  List<Speech> get speeches => List.unmodifiable(_speeches);
  Map<int, Member> get memberCache => Map.unmodifiable(_memberCache);
  List<SpeakerEntry> get speakers => List.unmodifiable(_speakers);
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Loads speeches for [date] from the local cache or network.
  Future<void> loadSpeeches() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _speeches = await _service.getSpeeches(date);
      _buildSpeakersIndex();
      await _loadMemberProfiles();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Returns the [Member] associated with [memberId], or `null` if unknown.
  Member? memberFor(int? memberId) {
    if (memberId == null) return null;
    return _memberCache[memberId];
  }

  // ─── Private helpers ──────────────────────────────────────────────────────

  /// Builds the sorted [_speakers] list from [_speeches].
  void _buildSpeakersIndex() {
    final seen = <String>{};
    final result = <SpeakerEntry>[];

    for (int i = 0; i < _speeches.length; i++) {
      final s = _speeches[i];
      final key = s.memberName.isNotEmpty ? s.memberName : s.attributedTo;
      if (key.isNotEmpty && !seen.contains(key)) {
        seen.add(key);
        result.add(
          SpeakerEntry(
            name: key,
            memberId: s.memberId,
            firstSpeechIndex: i,
          ),
        );
      }
    }

    // Sort alphabetically for the drawer list.
    result.sort((a, b) => a.name.compareTo(b.name));
    _speakers = result;
  }

  /// Pre-fetches [Member] records for all member IDs in [_speeches].
  Future<void> _loadMemberProfiles() async {
    final ids = _speeches
        .map((s) => s.memberId)
        .whereType<int>()
        .toSet();

    for (final id in ids) {
      if (!_memberCache.containsKey(id)) {
        final member = await _service.getMemberById(id);
        if (member != null) {
          _memberCache[id] = member;
        }
      }
    }
  }
}
