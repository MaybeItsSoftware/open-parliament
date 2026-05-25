import 'package:flutter/material.dart';

import '../models/boundary.dart';
import '../services/parliamentary_data_service.dart';

enum MapMode { constituency, council }

class ConstituencyMapViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;

  bool _isLoading = false;
  String? _error;
  MapMode _mode = MapMode.constituency;
  final Map<MapMode, List<BoundaryPolygon>> _boundariesByMode = {};

  ConstituencyMapViewModel(this._service);

  bool get isLoading => _isLoading;
  String? get error => _error;
  MapMode get mode => _mode;
  List<BoundaryPolygon> get boundaries =>
      _boundariesByMode[_mode] ?? const [];

  Future<void> load(MapMode mode) async {
    _mode = mode;
    if (_boundariesByMode.containsKey(mode)) {
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final boundaries = switch (mode) {
        MapMode.constituency => await _service.fetchConstituencyBoundaries(),
        MapMode.council => await _service.fetchCouncilBoundaries(),
      };
      _boundariesByMode[mode] = boundaries;
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }
}
