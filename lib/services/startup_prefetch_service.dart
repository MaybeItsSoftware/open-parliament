import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kStartupPrefetchKey = 'startup_prefetch_latest';

/// Persists whether the app should prefetch the latest content on launch.
class StartupPrefetchService extends ChangeNotifier {
  bool _prefetchOnStartup = false;

  bool get prefetchOnStartup => _prefetchOnStartup;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _prefetchOnStartup = prefs.getBool(_kStartupPrefetchKey) ?? false;
  }

  Future<void> setPrefetchOnStartup(bool value) async {
    if (value == _prefetchOnStartup) return;
    _prefetchOnStartup = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kStartupPrefetchKey, value);
  }
}
