import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/councillor.dart';
import '../models/councillor_profile.dart';
import '../utils/dc_match.dart';
import 'api_services.dart';

/// Enriches OpenCouncilData councillors with Democracy Club photos and contact
/// details, joining the two sources via a council's local-election ballots.
///
/// Two cache layers live under `boundary_cache/dc/`: one roster file per
/// council (elected people + their DC person ids) and one file per resolved
/// person profile. Both use a 30-day TTL — councillor membership and photos
/// change slowly. Everything degrades to null on miss or failure so the
/// councillor page always renders.
class CouncillorEnrichmentService {
  static const Duration _cacheTtl = Duration(days: 30);

  final DemocracyClubApiService _api;

  CouncillorEnrichmentService({DemocracyClubApiService? api})
      : _api = api ?? DemocracyClubApiService();

  /// Resolves [councillor] to a Democracy Club profile, or null when no match
  /// is found (unknown council slug, name mismatch, or DC has no record).
  Future<CouncillorProfile?> profileFor(Councillor councillor) async {
    final roster = await _roster(councillor.council);
    if (roster.isEmpty) return null;

    final match = _bestMatch(councillor, roster);
    if (match == null) return null;

    return _profile(match.personId);
  }

  /// Picks the roster entry whose name matches, preferring one in the same ward
  /// to disambiguate councils with two people sharing a name.
  DcElectedCandidate? _bestMatch(
    Councillor councillor,
    List<DcElectedCandidate> roster,
  ) {
    final byName =
        roster.where((e) => namesMatch(e.name, councillor.name)).toList();
    if (byName.isEmpty) return null;
    if (byName.length == 1) return byName.first;
    final ward = councillor.ward.toLowerCase().trim();
    for (final e in byName) {
      if (e.ward.toLowerCase().trim() == ward) return e;
    }
    return byName.first;
  }

  Future<List<DcElectedCandidate>> _roster(String councilName) async {
    final slug = dcCouncilSlug(councilName);
    if (slug.isEmpty) return const [];

    final file = await _cacheFile('roster_$slug.json');
    final cached = await _readFresh(file);
    if (cached != null) {
      return (jsonDecode(cached) as List)
          .map((e) => DcElectedCandidate.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    final fresh = await _api.fetchElectedForCouncil(slug);
    // Cache even an empty result to avoid re-querying a slug DC doesn't know.
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode([for (final e in fresh) e.toJson()]));
    return fresh;
  }

  Future<CouncillorProfile?> _profile(int personId) async {
    final file = await _cacheFile('person_$personId.json');
    final cached = await _readFresh(file);
    if (cached != null) {
      return CouncillorProfile.fromJson(
          jsonDecode(cached) as Map<String, dynamic>);
    }

    final fresh = await _api.fetchPerson(personId);
    if (fresh == null) return null;
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(fresh.toJson()));
    return fresh;
  }

  /// Returns the file's contents if it exists and is within the TTL, else null.
  Future<String?> _readFresh(File file) async {
    if (!file.existsSync()) return null;
    final age = DateTime.now().toUtc().difference(file.lastModifiedSync().toUtc());
    if (age >= _cacheTtl) return null;
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  Future<File> _cacheFile(String name) async {
    final directory = await getApplicationSupportDirectory();
    return File(p.join(directory.path, 'boundary_cache', 'dc', name));
  }

  void dispose() => _api.dispose();
}
