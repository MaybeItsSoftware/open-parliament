import 'package:flutter/foundation.dart';

import '../services/parliamentary_data_service.dart';

/// Backs the settings screen. Settings has no observable state of its own
/// (theme is managed by `ThemeService`), so this is essentially a typed
/// action sink that keeps the view from importing services directly.
class SettingsViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;

  SettingsViewModel(this._service);

  /// Deletes all cached sitting databases. Returns the number wiped.
  Future<int> clearCachedDebates() => _service.wipeDebateCache();
}
