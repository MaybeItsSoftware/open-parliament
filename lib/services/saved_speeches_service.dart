import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/saved_speech.dart';

const _kSavedSpeechesKey = 'saved_speeches';

/// App-wide store of bookmarked speeches, persisted to `shared_preferences`.
///
/// Exposed at the top of the widget tree like `ThemeService` because saved
/// speeches are global state, not scoped to a single transcript.
class SavedSpeechesService extends ChangeNotifier {
  /// Newest-first, keyed by [SavedSpeech.speechId].
  final Map<String, SavedSpeech> _byId = {};

  /// Saved speeches, newest first.
  List<SavedSpeech> get saved {
    final list = _byId.values.toList()
      ..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return List.unmodifiable(list);
  }

  bool isSaved(String speechId) => _byId.containsKey(speechId);

  /// Loads persisted bookmarks. Call once at startup before `runApp`.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kSavedSpeechesKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _byId.clear();
      for (final entry in decoded) {
        if (entry is Map<String, dynamic>) {
          final speech = SavedSpeech.fromJson(entry);
          if (speech.speechId.isNotEmpty) _byId[speech.speechId] = speech;
        }
      }
    } on FormatException {
      // Corrupt payload — start clean rather than crash on launch.
    }
  }

  /// Toggles the bookmark for [speech]. Returns the new saved state.
  Future<bool> toggle(SavedSpeech speech) async {
    final nowSaved = !_byId.containsKey(speech.speechId);
    if (nowSaved) {
      _byId[speech.speechId] = speech;
    } else {
      _byId.remove(speech.speechId);
    }
    notifyListeners();
    await _persist();
    return nowSaved;
  }

  Future<void> remove(String speechId) async {
    if (_byId.remove(speechId) == null) return;
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode([for (final s in saved) s.toJson()]);
    await prefs.setString(_kSavedSpeechesKey, payload);
  }
}
