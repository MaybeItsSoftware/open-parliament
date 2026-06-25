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

  /// Loads council control. With no [year] this returns the current table;
  /// pass a year to load that year's historical composition (each year is
  /// cached in its own file so the current table is never overwritten).
  Future<List<Council>> loadCouncils({int? year}) async {
    final file = await _cacheFile(year);
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

    final fresh = await _api.fetchCouncils(year: year);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([for (final c in fresh) c.toJson()]));
    return fresh;
  }

  Future<File> _cacheFile([int? year]) async {
    final directory = await getApplicationSupportDirectory();
    final name =
        year != null && year > 0 ? 'councils_$year.json' : 'councils.json';
    return File(p.join(directory.path, 'boundary_cache', name));
  }

  /// Deletes the cached council control tables (current + any per-year history
  /// snapshots). Returns the number of files removed.
  Future<int> clearCache() async {
    final directory = await getApplicationSupportDirectory();
    final dir = Directory(p.join(directory.path, 'boundary_cache'));
    if (!dir.existsSync()) return 0;
    var count = 0;
    await for (final entity in dir.list()) {
      final base = p.basename(entity.path);
      if (entity is File &&
          (base == 'councils.json' ||
              RegExp(r'^councils_\d+\.json$').hasMatch(base))) {
        await entity.delete();
        count++;
      }
    }
    return count;
  }

  void dispose() => _api.dispose();
}
