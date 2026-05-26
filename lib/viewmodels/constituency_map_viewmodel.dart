import 'package:flutter/material.dart';

import '../models/boundary.dart';
import '../models/council.dart';
import '../models/councillor.dart';
import '../models/member.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/area_match.dart';
import '../utils/party_colors.dart' as party_util;

enum MapMode { constituency, council }

/// One boundary polygon ready to draw, coloured by political control and
/// carrying a human-readable label for tap identification.
class MapArea {
  final BoundaryPolygon polygon;
  final Color fill;
  final Color border;

  /// The area's name (constituency or council).
  final String name;

  /// Who controls it: an MP + party, a council control string, or a fallback.
  final String controller;

  /// The full council record in council mode (enables the detail page); null
  /// for constituencies.
  final Council? council;

  /// The sitting MP in constituency mode (enables the member page); null for
  /// councils or constituencies with no current MP.
  final Member? member;

  const MapArea({
    required this.polygon,
    required this.fill,
    required this.border,
    required this.name,
    required this.controller,
    this.council,
    this.member,
  });
}

class ConstituencyMapViewModel extends ChangeNotifier {
  final ParliamentaryDataService _service;

  bool _isLoading = false;
  String? _error;
  MapMode _mode = MapMode.constituency;
  final Map<MapMode, List<MapArea>> _areasByMode = {};

  /// The national councillor list, fetched once and shared across council pages.
  Future<List<Councillor>>? _allCouncillors;

  ConstituencyMapViewModel(this._service);

  bool get isLoading => _isLoading;
  String? get error => _error;
  MapMode get mode => _mode;
  List<MapArea> get areas => _areasByMode[_mode] ?? const [];

  Future<void> load(MapMode mode) async {
    _mode = mode;
    if (_areasByMode.containsKey(mode)) {
      notifyListeners();
      return;
    }
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _areasByMode[mode] = switch (mode) {
        MapMode.constituency => await _loadConstituencyAreas(),
        MapMode.council => await _loadCouncilAreas(),
      };
    } catch (e) {
      _error = e.toString();
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<List<MapArea>> _loadConstituencyAreas() async {
    // Boundaries and members are independent; fetch them concurrently.
    final (boundaries, members) = await (
      _service.fetchConstituencyBoundaries(),
      _service.getMembers(),
    ).wait;
    final byConstituency = <String, Member>{
      for (final m in members)
        if (m.constituency.isNotEmpty) normaliseName(m.constituency): m,
    };

    return [
      for (final boundary in boundaries)
        _constituencyArea(boundary, byConstituency[normaliseName(boundary.name)]),
    ];
  }

  MapArea _constituencyArea(BoundaryPolygon boundary, Member? member) {
    if (member == null) {
      return _greyArea(boundary, 'No sitting MP');
    }
    final color = party_util.partyColor(
      member.partyAbbreviation.isNotEmpty
          ? member.partyAbbreviation
          : member.party,
    );
    final party = member.party.isNotEmpty ? member.party : 'Unknown party';
    return MapArea(
      polygon: boundary,
      fill: color.withValues(alpha: 0.6),
      border: color,
      name: boundary.name,
      controller: '${member.name} ($party)',
      member: member,
    );
  }

  Future<List<MapArea>> _loadCouncilAreas() async {
    // Boundaries and control data are independent; fetch them concurrently.
    final (boundaries, councils) = await (
      _service.fetchCouncilBoundaries(),
      _service.fetchCouncils(),
    ).wait;
    final byCouncil = <String, Council>{
      for (final c in councils) normaliseCouncilName(c.name): c,
    };

    return [
      for (final boundary in boundaries)
        _councilArea(boundary, byCouncil[normaliseCouncilName(boundary.name)]),
    ];
  }

  MapArea _councilArea(BoundaryPolygon boundary, Council? council) {
    if (council == null) {
      return _greyArea(boundary, 'No control data');
    }
    final color = party_util.controlColor(council.control);
    return MapArea(
      polygon: boundary,
      fill: color.withValues(alpha: 0.6),
      border: color,
      name: boundary.name,
      controller: council.control,
      council: council,
    );
  }

  /// All boundary polygons making up the area with the given [name] (a council
  /// can span several islands rendered as separate areas).
  List<BoundaryPolygon> polygonsForName(String name) =>
      [for (final a in areas) if (a.name == name) a.polygon];

  /// Councillors belonging to the council named [councilName], matched on the
  /// same normalised name used to join boundaries to control data. The national
  /// list is loaded once and reused across council pages.
  Future<List<Councillor>> councillorsForCouncil(String councilName) async {
    final all = await (_allCouncillors ??= _service.fetchCouncillors());
    final key = normaliseCouncilName(councilName);
    return [
      for (final c in all)
        if (normaliseCouncilName(c.council) == key) c,
    ];
  }

  MapArea _greyArea(BoundaryPolygon boundary, String label) => MapArea(
        polygon: boundary,
        fill: party_util.noControlColor.withValues(alpha: 0.25),
        border: party_util.noControlColor,
        name: boundary.name,
        controller: label,
      );
}
