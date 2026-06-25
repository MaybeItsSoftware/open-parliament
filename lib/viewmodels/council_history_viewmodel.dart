import 'package:flutter/foundation.dart';

import '../models/council.dart';
import '../services/parliamentary_data_service.dart';

/// One year's political control snapshot for a council.
class CouncilYearControl {
  final int year;
  final Council council;

  const CouncilYearControl({required this.year, required this.council});
}

/// Loads a council's control/seat-split for recent years, newest first, paging
/// further back on demand. Data comes from OpenCouncilData's per-year
/// composition tables via [ParliamentaryDataService.fetchCouncilForYear].
class CouncilHistoryViewModel extends ChangeNotifier {
  /// How many years are fetched per batch (initial load and each "load older").
  static const int batchSize = 10;

  /// OpenCouncilData's composition archive starts in 1973; don't scan past it.
  static const int floorYear = 1973;

  final ParliamentaryDataService _service;
  final String councilName;
  final int _fromYear;

  bool _isLoading = true;
  bool _isLoadingOlder = false;
  String? _error;
  final List<CouncilYearControl> _history = [];

  /// The oldest year already scanned (whether or not it had data).
  late int _earliestScanned;
  bool _disposed = false;

  CouncilHistoryViewModel(
    this._service, {
    required this.councilName,
    int? fromYear,
  }) : _fromYear = fromYear ?? DateTime.now().year {
    _earliestScanned = _fromYear + 1; // nothing scanned yet
  }

  bool get isLoading => _isLoading;
  bool get isLoadingOlder => _isLoadingOlder;
  String? get error => _error;
  List<CouncilYearControl> get history => List.unmodifiable(_history);

  /// Whether there are older years left to scan (above the archive floor).
  bool get canLoadOlder => _earliestScanned - 1 >= floorYear;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _safeNotify();
    try {
      await _scanBatch();
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    _safeNotify();
  }

  /// Fetches the next [batchSize] older years and appends any with data.
  /// No-ops while a fetch is in flight or once the floor is reached.
  Future<void> loadOlder() async {
    if (_isLoadingOlder || _isLoading || !canLoadOlder) return;
    _isLoadingOlder = true;
    _safeNotify();
    try {
      await _scanBatch();
    } catch (_) {
      // Leave already-loaded history intact on a paging failure.
    }
    _isLoadingOlder = false;
    _safeNotify();
  }

  /// Scans the next batch of years downward from [_earliestScanned], fetching
  /// each year concurrently and appending those that returned data.
  Future<void> _scanBatch() async {
    final top = _earliestScanned - 1; // newest year not yet scanned
    final bottom = (top - batchSize + 1).clamp(floorYear, top);
    final years = [for (var y = top; y >= bottom; y--) y];
    final councils = await Future.wait(
      years.map((y) => _service.fetchCouncilForYear(councilName, y)),
    );
    for (var i = 0; i < years.length; i++) {
      final council = councils[i];
      if (council != null) {
        _history.add(CouncilYearControl(year: years[i], council: council));
      }
    }
    _earliestScanned = bottom;
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
