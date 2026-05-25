import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/boundary.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/map_tiles.dart';
import '../viewmodels/constituency_map_viewmodel.dart';
import 'app_drawer.dart';

/// National map view for constituency or council control.
class ConstituencyMapView extends StatefulWidget {
  const ConstituencyMapView({super.key});

  @override
  State<ConstituencyMapView> createState() => _ConstituencyMapViewState();
}

class _ConstituencyMapViewState extends State<ConstituencyMapView> {
  static const LatLng _ukCenter = LatLng(54.6, -3.4);
  static const double _initialZoom = 5.3;

  late ConstituencyMapViewModel _vm;

  @override
  void initState() {
    super.initState();
    _vm = ConstituencyMapViewModel(
      context.read<ParliamentaryDataService>(),
    );
    unawaited(_vm.load(MapMode.constituency));
  }

  @override
  void dispose() {
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<ConstituencyMapViewModel>(
        builder: (context, vm, _) {
          final theme = Theme.of(context);
          final accent = vm.mode == MapMode.council
              ? theme.colorScheme.tertiary
              : theme.colorScheme.primary;
          final polygons = _toPolygons(
            vm.boundaries,
            fill: accent.withValues(alpha: 0.08),
            stroke: accent.withValues(alpha: 0.85),
          );
          return Scaffold(
            appBar: AppBar(
              title: const Text('Constituency Map'),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: SegmentedButton<MapMode>(
                    segments: const [
                      ButtonSegment(
                        value: MapMode.constituency,
                        label: Text('Constituencies'),
                        icon: Icon(Icons.how_to_vote_outlined),
                      ),
                      ButtonSegment(
                        value: MapMode.council,
                        label: Text('Councils'),
                        icon: Icon(Icons.account_balance_outlined),
                      ),
                    ],
                    selected: {vm.mode},
                    showSelectedIcon: false,
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      unawaited(_vm.load(selection.first));
                    },
                  ),
                ),
              ),
            ),
            drawer: const AppDrawer(current: AppDestination.map),
            body: Stack(
              children: [
                FlutterMap(
                  options: const MapOptions(
                    initialCenter: _ukCenter,
                    initialZoom: _initialZoom,
                    minZoom: 4,
                    maxZoom: 18,
                  ),
                  children: [
                    buildCartoLightTileLayer(),
                    if (polygons.isNotEmpty)
                      PolygonLayer(
                        polygons: polygons,
                      ),
                  ],
                ),
                if (vm.isLoading && polygons.isEmpty)
                  const Center(child: CircularProgressIndicator()),
                if (vm.error != null)
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        vm.error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

List<Polygon> _toPolygons(
  List<BoundaryPolygon> boundaries, {
  required Color fill,
  required Color stroke,
}) {
  return [
    for (final boundary in boundaries)
      Polygon(
        points: boundary.outer,
        holePointsList: boundary.holes.isNotEmpty ? boundary.holes : null,
        color: fill,
        borderColor: stroke,
        borderStrokeWidth: 1,
      ),
  ];
}
