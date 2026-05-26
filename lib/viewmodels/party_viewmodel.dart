import 'package:flutter/foundation.dart';
import '../models/party_stats.dart';
import '../services/party_service.dart';

class PartyViewModel extends ChangeNotifier {
  final PartyService _service;
  final String partyName;

  PartyStats? _stats;
  PartyStats? get stats => _stats;

  bool _isLoadingCurrent = false;
  bool get isLoadingCurrent => _isLoadingCurrent;

  bool _isLoadingHistorical = false;
  bool get isLoadingHistorical => _isLoadingHistorical;

  String? _error;
  String? get error => _error;

  PartyViewModel(this._service, {required this.partyName});

  Future<void> load() async {
    _isLoadingCurrent = true;
    _error = null;
    notifyListeners();

    try {
      _stats = await _service.loadCurrentStats(partyName);
      _isLoadingCurrent = false;
      notifyListeners();

      // Start loading historical trends in the background
      await _loadHistorical();
    } catch (e) {
      _error = e.toString();
      _isLoadingCurrent = false;
      notifyListeners();
    }
  }

  Future<void> _loadHistorical() async {
    if (_stats == null || _stats!.partyToken.isEmpty) return;

    _isLoadingHistorical = true;
    notifyListeners();

    try {
      final trends = await _service.loadHistoricalTrends(_stats!.partyToken);
      _stats = _stats!.copyWith(
        mpTrend: trends['mps'],
        lordTrend: trends['lords'],
        councilsControlledTrend: trends['councils'],
      );
    } catch (_) {
      // Historical trends are best-effort; don't set global error if they fail
    } finally {
      _isLoadingHistorical = false;
      notifyListeners();
    }
  }
}
