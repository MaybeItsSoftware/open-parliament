import '../models/party_stats.dart';
import '../utils/party_tokens.dart';
import 'api_services.dart';
import 'council_control_service.dart';
import 'councillor_service.dart';

/// Orchestrates fetching current and historical stats for a political party.
class PartyService {
  final MembersApiService _membersApi;
  final CouncilControlService _councilControl;
  final CouncillorService _councillorService;
  final CouncilControlApiService _councilApi;

  PartyService({
    MembersApiService? membersApi,
    CouncilControlService? councilControl,
    CouncillorService? councillorService,
    CouncilControlApiService? councilApi,
  })  : _membersApi = membersApi ?? MembersApiService(),
        _councilControl = councilControl ?? CouncilControlService(),
        _councillorService = councillorService ?? CouncillorService(),
        _councilApi = councilApi ?? CouncilControlApiService();

  /// Loads current aggregate statistics for a party.
  Future<PartyStats> loadCurrentStats(String partyName) async {
    final token = canonicalPartyToken(partyName);
    if (token == null) return PartyStats(partyName: partyName, partyToken: '');

    // 1. Parliament Stats (Current)
    final now = DateTime.now();
    final commons = await _membersApi.fetchStateOfTheParties('Commons', now);
    final lords = await _membersApi.fetchStateOfTheParties('Lords', now);

    int mpCount = 0;
    int lordCount = 0;

    for (final p in commons) {
      final party = (p['party'] as Map<String, dynamic>?) ?? {};
      if (canonicalPartyToken(party['name'] ?? '') == token ||
          canonicalPartyToken(party['abbreviation'] ?? '') == token) {
        mpCount = (p['total'] as num?)?.toInt() ?? 0;
        break;
      }
    }
    for (final p in lords) {
      final party = (p['party'] as Map<String, dynamic>?) ?? {};
      if (canonicalPartyToken(party['name'] ?? '') == token ||
          canonicalPartyToken(party['abbreviation'] ?? '') == token) {
        lordCount = (p['total'] as num?)?.toInt() ?? 0;
        break;
      }
    }

    // 2. Local Council Stats (Current)
    final councils = await _councilControl.loadCouncils();
    final councillors = await _councillorService.loadCouncillors();

    int councilsControlled = 0;
    for (final c in councils) {
      if (canonicalPartyToken(c.control) == token) {
        councilsControlled++;
      }
    }

    int councillorCount = 0;
    for (final c in councillors) {
      if (canonicalPartyToken(c.party) == token) {
        councillorCount++;
      }
    }

    return PartyStats(
      partyName: partyName,
      partyToken: token,
      mpCount: mpCount,
      lordCount: lordCount,
      councillorCount: councillorCount,
      councilsControlled: councilsControlled,
    );
  }

  /// Fetches historical trends for the last 5 years.
  Future<Map<String, HistoricalTrend>> loadHistoricalTrends(
    String partyToken,
  ) async {
    final currentYear = DateTime.now().year;
    final years = List.generate(5, (i) => currentYear - i).reversed.toList();

    final mpPoints = <HistoricalDataPoint>[];
    final lordPoints = <HistoricalDataPoint>[];
    final councilPoints = <HistoricalDataPoint>[];

    for (final year in years) {
      // Parliament (roughly May of each year for consistency with local elections)
      final date = DateTime(year, 5, 1);
      final commons = await _membersApi.fetchStateOfTheParties('Commons', date);
      final lords = await _membersApi.fetchStateOfTheParties('Lords', date);

      int mps = 0;
      for (final p in commons) {
        final party = (p['party'] as Map<String, dynamic>?) ?? {};
        if (canonicalPartyToken(party['name'] ?? '') == partyToken ||
            canonicalPartyToken(party['abbreviation'] ?? '') == partyToken) {
          mps = (p['total'] as num?)?.toInt() ?? 0;
          break;
        }
      }
      mpPoints.add(HistoricalDataPoint(year: year, value: mps));

      int lds = 0;
      for (final p in lords) {
        final party = (p['party'] as Map<String, dynamic>?) ?? {};
        if (canonicalPartyToken(party['name'] ?? '') == partyToken ||
            canonicalPartyToken(party['abbreviation'] ?? '') == partyToken) {
          lds = (p['total'] as num?)?.toInt() ?? 0;
          break;
        }
      }
      lordPoints.add(HistoricalDataPoint(year: year, value: lds));

      // Local Councils
      try {
        final councils = await _councilApi.fetchCouncils(year: year);
        int controlled = 0;
        for (final c in councils) {
          if (canonicalPartyToken(c.control) == partyToken) {
            controlled++;
          }
        }
        councilPoints.add(HistoricalDataPoint(year: year, value: controlled));
      } catch (_) {
        // Skip years where data isn't available
      }
      
      // Councillors (this might be slow if we fetch all councillors for every year)
      // For now, let's just do council control as it's a smaller payload.
    }

    return {
      'mps': HistoricalTrend(label: 'MPs', points: mpPoints),
      'lords': HistoricalTrend(label: 'Lords', points: lordPoints),
      'councils': HistoricalTrend(label: 'Councils', points: councilPoints),
    };
  }
}
