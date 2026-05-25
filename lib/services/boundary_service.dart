import 'dart:convert';
import 'dart:io';

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
          final decoded = jsonDecode(cached) as Map<String, dynamic>;
          return parseGeoJsonBoundaries(decoded);
        } on FormatException {
          // Fall through to refresh the cache.
        }
      }
    }

    final fresh = await _fetchRemote(type);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(fresh));
    return parseGeoJsonBoundaries(fresh);
  }

  Future<Map<String, dynamic>> _fetchRemote(BoundaryType type) {
    return switch (type) {
      BoundaryType.constituency => _api.fetchConstituencyBoundaries(),
      BoundaryType.council => _api.fetchCouncilBoundaries(),
    };
  }

  Future<File> _cacheFile(BoundaryType type) async {
    final directory = await getApplicationSupportDirectory();
    final filename = switch (type) {
      BoundaryType.constituency => 'constituencies.geojson',
      BoundaryType.council => 'councils.geojson',
    };
    return File(p.join(directory.path, 'boundary_cache', filename));
  }

  void dispose() => _api.dispose();
}
