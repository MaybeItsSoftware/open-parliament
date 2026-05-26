import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/council.dart';
import 'api_services.dart';

/// Loads and caches council political makeup from OpenCouncilData.
///
/// Control only changes at local elections, so a 30-day cache is ample and
/// keeps the national map offline-friendly like the rest of the app.
class CouncilControlService {
  static const Duration _cacheTtl = Duration(days: 30);

  final CouncilControlApiService _api;

  CouncilControlService({CouncilControlApiService? api})
      : _api = api ?? CouncilControlApiService();

  Future<List<Council>> loadCouncils() async {
    final file = await _cacheFile();
    final now = DateTime.now().toUtc();
    if (file.existsSync()) {
      final modified = file.lastModifiedSync().toUtc();
      if (now.difference(modified) < _cacheTtl) {
        try {
          final decoded = jsonDecode(await file.readAsString()) as List;
          return decoded
              .map((e) => Council.fromJson(e as Map<String, dynamic>))
              .toList();
        } on FormatException {
          // Fall through to refresh the cache.
        }
      }
    }

    final fresh = await _api.fetchCouncils();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([for (final c in fresh) c.toJson()]));
    return fresh;
  }

  Future<File> _cacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'boundary_cache', 'councils.json'));
  }

  /// Deletes the cached council control table. Returns 1 if a cache was
  /// removed, else 0.
  Future<int> clearCache() async {
    final file = await _cacheFile();
    if (!file.existsSync()) return 0;
    await file.delete();
    return 1;
  }

  void dispose() => _api.dispose();
}
