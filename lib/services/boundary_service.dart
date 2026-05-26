import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/boundary.dart';
import '../utils/geojson_boundaries.dart';
import 'api_services.dart';

enum BoundaryType { constituency, council }

/// Loads and caches boundary polygons for the national map.
class BoundaryService {
  static const Duration _cacheTtl = Duration(days: 180);

  final BoundaryApiService _api;

  BoundaryService({BoundaryApiService? api})
      : _api = api ?? BoundaryApiService();

  Future<List<BoundaryPolygon>> loadBoundaries(BoundaryType type) async {
    final file = await _cacheFile(type);
    final now = DateTime.now().toUtc();
    if (file.existsSync()) {
      final modified = file.lastModifiedSync().toUtc();
      if (now.difference(modified) < _cacheTtl) {
        final cached = await file.readAsString();
        try {
          // Decode + parse on a background isolate; the files are several MB
          // and doing this on the UI isolate freezes the map while it loads.
          return await compute(
            parseGeoJsonString,
            GeoJsonParseRequest(cached, _nameKey(type)),
          );
        } on FormatException {
          // Fall through to refresh the cache.
        }
      }
    }

    final fresh = await _fetchRemote(type);
    final encoded = jsonEncode(fresh);
    await file.parent.create(recursive: true);
    await file.writeAsString(encoded);
    return compute(
      parseGeoJsonString,
      GeoJsonParseRequest(encoded, _nameKey(type)),
    );
  }

  String _nameKey(BoundaryType type) => switch (type) {
        BoundaryType.constituency => 'PCON24NM',
        BoundaryType.council => 'LAD24NM',
      };

  Future<Map<String, dynamic>> _fetchRemote(BoundaryType type) {
    return switch (type) {
      BoundaryType.constituency => _api.fetchConstituencyBoundaries(),
      BoundaryType.council => _api.fetchCouncilBoundaries(),
    };
  }

  Future<File> _cacheFile(BoundaryType type) async {
    final directory = await getApplicationSupportDirectory();
    // v2 filenames: the original cache stored geometry without area names.
    // v3: re-fetched at a finer simplification offset (~220 m vs ~1.1 km) for
    // smoother borders. constituencies_v4: finer still (~55 m) since the small
    // seats still looked blocky when zoomed in. Each bump supersedes the older,
    // blockier cache.
    final filename = switch (type) {
      BoundaryType.constituency => 'constituencies_v4.geojson',
      BoundaryType.council => 'councils_v3.geojson',
    };
    return File(p.join(directory.path, 'boundary_cache', filename));
  }

  /// Deletes the cached boundary GeoJSON files, forcing a re-fetch on next
  /// load. Leaves sibling caches (council control, councillors) untouched.
  /// Returns the number of files removed.
  Future<int> clearCache() async {
    final directory = await getApplicationSupportDirectory();
    final dir = Directory(p.join(directory.path, 'boundary_cache'));
    if (!dir.existsSync()) return 0;
    var count = 0;
    await for (final entity in dir.list()) {
      if (entity is File && p.extension(entity.path) == '.geojson') {
        await entity.delete();
        count++;
      }
    }
    return count;
  }

  void dispose() => _api.dispose();
}
