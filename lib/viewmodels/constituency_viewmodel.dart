import 'package:flutter/foundation.dart';

import '../models/election_result.dart';
import '../models/member.dart';
import '../services/parliamentary_data_service.dart';

/// Loads the latest general-election result for a single constituency.
class ConstituencyViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;

  /// The constituency name, as shown on the national map / member profile.
  final String constituencyName;

  /// The sitting MP, when navigated from a context that already has it.
  final Member? member;

  bool _isLoading = true;
  String? _error;
  ConstituencyElectionResult? _result;
  bool _disposed = false;

  ConstituencyViewModel(
    this._service, {
    required this.constituencyName,
    this.member,
  });

  bool get isLoading => _isLoading;
  String? get error => _error;
  ConstituencyElectionResult? get result => _result;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    _safeNotify();
    try {
      final result = await _service.fetchConstituencyResult(constituencyName);
      if (result == null) {
        _error = 'No election result available for this constituency.';
      } else {
        _result = result;
      }
    } catch (e) {
      _error = e.toString();
    }
    _isLoading = false;
    _safeNotify();
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
