import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/councillor.dart';
import 'api_services.dart';

/// Loads and caches the national councillor list from OpenCouncilData.
///
/// The source is a fixed annual snapshot refreshed after each May election, so
/// a 30-day cache matches the data's cadence and keeps the app offline-friendly
/// like the council control layer it sits alongside.
class CouncillorService {
  static const Duration _cacheTtl = Duration(days: 30);

  final CouncillorApiService _api;

  CouncillorService({CouncillorApiService? api})
      : _api = api ?? CouncillorApiService();

  Future<List<Councillor>> loadCouncillors() async {
    final file = await _cacheFile();
    final now = DateTime.now().toUtc();
    if (file.existsSync()) {
      final modified = file.lastModifiedSync().toUtc();
      if (now.difference(modified) < _cacheTtl) {
        try {
          final decoded = jsonDecode(await file.readAsString()) as List;
          return decoded
              .map((e) => Councillor.fromJson(e as Map<String, dynamic>))
              .toList();
        } on FormatException {
          // Fall through to refresh the cache.
        }
      }
    }

    final fresh = await _api.fetchCouncillors();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([for (final c in fresh) c.toJson()]));
    return fresh;
  }

  Future<File> _cacheFile() async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'boundary_cache', 'councillors.json'));
  }

  /// Deletes the cached councillor list. Returns 1 if a cache was removed, else 0.
  Future<int> clearCache() async {
    final file = await _cacheFile();
    if (!file.existsSync()) return 0;
    await file.delete();
    return 1;
  }

  void dispose() => _api.dispose();
}
