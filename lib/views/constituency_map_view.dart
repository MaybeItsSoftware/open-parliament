import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/council.dart';
import '../services/parliamentary_data_service.dart';
import '../utils/area_match.dart';
import '../utils/council_control.dart';
import '../utils/map_tiles.dart';
import '../utils/party_colors.dart' as party_util;
import '../viewmodels/constituency_map_viewmodel.dart';
import 'app_drawer.dart';
import 'constituency_view.dart';
import 'council_view.dart';
import 'member_view.dart';

/// National map showing political control: constituencies coloured by the
/// sitting MP's party, councils by their controlling party.
class ConstituencyMapView extends StatefulWidget {
  const ConstituencyMapView({super.key});

  @override
  State<ConstituencyMapView> createState() => _ConstituencyMapViewState();
}

class _ConstituencyMapViewState extends State<ConstituencyMapView>
    with SingleTickerProviderStateMixin {
  static const LatLng _ukCenter = LatLng(54.6, -3.4);
  static const double _initialZoom = 5.3;
  static final LatLngBounds _ukBounds = LatLngBounds.fromPoints(
    const [
      LatLng(49.6, -8.9),
      LatLng(61.0, 2.3),
    ],
  );

  late ConstituencyMapViewModel _vm;
  final MapController _mapController = MapController();

  // Drives smooth camera flights between the current and target view.
  late final AnimationController _flight = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );
  LatLng _flightFromCenter = _ukCenter;
  LatLng _flightToCenter = _ukCenter;
  double _flightFromZoom = _initialZoom;
  double _flightToZoom = _initialZoom;

  /// The area whose drawer is currently open, or null when none is.
  MapArea? _selected;

  /// The last non-null selection, kept so the drawer keeps showing its content
  /// while it slides back down after being dismissed.
  MapArea? _lastArea;

  /// The base polygon layer, cached as a widget *instance* and rebuilt only
  /// when the view-model hands us a different area list (mode switch/reload).
  /// Passing the identical instance across rebuilds makes Flutter skip the
  /// element update, so flutter_map keeps its projection/simplification
  /// caches — its `didUpdateWidget` clears them unconditionally, which
  /// re-projects every polygon on the UI thread and janks the whole map.
  Widget? _baseLayer;
  List<MapArea>? _baseLayerAreas;

  @override
  void initState() {
    super.initState();
    _vm = ConstituencyMapViewModel(
      context.read<ParliamentaryDataService>(),
    );
    unawaited(_vm.load(MapMode.constituency));

    _flight.addListener(() {
      final t = Curves.easeInOutCubic.transform(_flight.value);
      _mapController.move(
        LatLng(
          _flightFromCenter.latitude +
              (_flightToCenter.latitude - _flightFromCenter.latitude) * t,
          _flightFromCenter.longitude +
              (_flightToCenter.longitude - _flightFromCenter.longitude) * t,
        ),
        _flightFromZoom + (_flightToZoom - _flightFromZoom) * t,
      );
    });
  }

  /// Smoothly flies the camera from its current view to [center]/[zoom].
  void _flyTo(LatLng center, double zoom) {
    final cam = _mapController.camera;
    _flightFromCenter = cam.center;
    _flightFromZoom = cam.zoom;
    _flightToCenter = center;
    _flightToZoom = zoom;
    _flight.forward(from: 0);
  }

  /// Resets the map to point north without changing position or zoom.
  void _reorient() {
    _mapController.rotate(0);
  }

  @override
  void dispose() {
    _flight.dispose();
    _vm.dispose();
    super.dispose();
  }

  void _openCouncil(MapArea area) {
    final council = area.council;
    if (council == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CouncilView(
          council: council,
          boundaries: _vm.polygonsForName(area.name),
          councillors: _vm.councillorsForCouncil(council.name),
        ),
      ),
    );
  }

  void _openMp(MapArea area) {
    final member = area.member;
    if (member == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemberView(member: member)),
    );
  }

  void _openConstituency(MapArea area) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ConstituencyView(
          constituencyName: area.name,
          member: area.member,
          boundaries: _vm.polygonsForName(area.name),
        ),
      ),
    );
  }

  void _handleTap(LatLng point) {
    // Topmost match wins; areas are small so a linear scan is fine.
    MapArea? hit;
    for (final area in _vm.areas) {
      if (boundaryContainsPoint(area.polygon, point)) {
        hit = area;
        break;
      }
    }
    setState(() {
      _selected = hit;
      if (hit != null) _lastArea = hit;
    });
    if (hit != null) _zoomToArea(hit);
  }

  /// Frames the camera on every polygon belonging to [area] (a council can
  /// span several islands). Extra bottom padding keeps it clear of the drawer.
  void _zoomToArea(MapArea area) {
    final points = [
      for (final polygon in _vm.polygonsForName(area.name)) ...polygon.outer,
    ];
    if (points.isEmpty) return;
    final target = CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(points),
      padding: const EdgeInsets.fromLTRB(48, 48, 48, 280),
    ).fit(_mapController.camera);
    _flyTo(target.center, target.zoom);
  }

  /// Simplification for polygon rendering, in logical pixels: near-lossless,
  /// and constant — changing it forces flutter_map to re-simplify everything.
  static const double _polygonTolerance = 0.5;

  /// Returns the cached base layer, rebuilding it only for a new area list.
  Widget _basePolygonLayerFor(List<MapArea> areas) {
    if (!identical(_baseLayerAreas, areas)) {
      _baseLayerAreas = areas;
      _baseLayer = PolygonLayer(
        polygons: _toPolygons(areas),
        polygonCulling: true,
        simplificationTolerance: _polygonTolerance,
      );
    }
    return _baseLayer!;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Consumer<ConstituencyMapViewModel>(
        builder: (context, vm, _) {
          final theme = Theme.of(context);
          final selectionPolygons = _selected == null
              ? const <Polygon>[]
              : _selectionPolygons(vm.areas, _selected!.name);
          return Scaffold(
            appBar: AppBar(
              title: const Text('Control Map'),
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
                      setState(() => _selected = null);
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
                  mapController: _mapController,
                  options: MapOptions(
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all),
                    initialCenter: _ukCenter,
                    initialZoom: _initialZoom,
                    minZoom: 4,
                    maxZoom: 18,
                    // containCenter (not contain): the UK box is smaller than
                    // the viewport at these zooms, so `contain` is unsatisfiable
                    // and trips flutter_map's constraint assertion on rebuild.
                    // Keeping the centre in-bounds stops the map drifting away
                    // while staying always-satisfiable.
                    cameraConstraint:
                        CameraConstraint.containCenter(bounds: _ukBounds),
                    onTap: (_, point) => _handleTap(point),
                  ),
                  children: [
                    buildCartoBaseTileLayer(context),
                    if (vm.areas.isNotEmpty) _basePolygonLayerFor(vm.areas),
                    // The selection highlight lives in its own tiny layer so
                    // tapping never rebuilds (and re-projects) the base layer.
                    if (selectionPolygons.isNotEmpty)
                      PolygonLayer(
                        polygons: selectionPolygons,
                        simplificationTolerance: _polygonTolerance,
                      ),
                    // Labels sit above the fills so place names stay legible.
                    buildCartoLabelsTileLayer(context),
                  ],
                ),
                if (vm.isLoading && vm.areas.isEmpty)
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
                Positioned(
                  top: 12,
                  right: 12,
                  child: _CompassButton(
                    controller: _mapController,
                    onTap: _reorient,
                  ),
                ),
                if (!vm.isLoading && vm.error == null)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: _Legend(mode: vm.mode),
                  ),
                // A single, stable drawer subtree that slides in/out. Keeping
                // one subtree (rather than swapping with AnimatedSwitcher)
                // avoids hit-testing a child mid-layout while it animates.
                if (_lastArea != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: _selected == null,
                      child: AnimatedSlide(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        offset:
                            _selected == null ? const Offset(0, 1) : Offset.zero,
                        child: _AreaDrawer(
                          area: _selected ?? _lastArea!,
                          onClose: () => setState(() => _selected = null),
                          onOpenCouncil: (_selected ?? _lastArea!).council == null
                              ? null
                              : () => _openCouncil(_selected ?? _lastArea!),
                          onOpenMp: (_selected ?? _lastArea!).member == null
                              ? null
                              : () => _openMp(_selected ?? _lastArea!),
                          // Constituencies (no council) get a detail page; the
                          // name is enough to look up the election result.
                          onOpenConstituency:
                              (_selected ?? _lastArea!).council != null ||
                                      (_selected ?? _lastArea!).name.isEmpty
                                  ? null
                                  : () => _openConstituency(_selected ?? _lastArea!),
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

List<Polygon> _toPolygons(List<MapArea> areas) {
  return [
    for (final area in areas)
      Polygon(
        points: area.polygon.outer,
        holePointsList:
            area.polygon.holes.isNotEmpty ? area.polygon.holes : null,
        color: area.fill,
        borderColor: area.border.withValues(alpha: 0.85),
        borderStrokeWidth: 0.6,
        disableHolesBorder: true,
      ),
  ];
}

/// Bold copies of every polygon named [name] (a council can span several
/// islands), drawn in an overlay layer above the base fills.
List<Polygon> _selectionPolygons(List<MapArea> areas, String name) {
  return [
    for (final area in areas)
      if (area.name == name)
        Polygon(
          points: area.polygon.outer,
          holePointsList:
              area.polygon.holes.isNotEmpty ? area.polygon.holes : null,
          color: area.border.withValues(alpha: 0.45),
          borderColor: area.border,
          borderStrokeWidth: 2.5,
          disableHolesBorder: true,
        ),
  ];
}

/// A small compass whose needle tracks the map's bearing; tap to reset north
/// and recentre on the UK.
class _CompassButton extends StatefulWidget {
  final MapController controller;
  final VoidCallback onTap;

  const _CompassButton({required this.controller, required this.onTap});

  @override
  State<_CompassButton> createState() => _CompassButtonState();
}

class _CompassButtonState extends State<_CompassButton> {
  StreamSubscription<MapEvent>? _sub;
  double _rotation = 0; // map bearing in degrees

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.mapEventStream.listen((_) {
      final r = widget.controller.camera.rotation;
      if (r == _rotation) return;
      // Defer: map events fire during layout/pointer handling, and calling
      // setState then trips the mouse_tracker's `!_debugDuringDeviceUpdate`
      // assertion. A post-frame callback rebuilds safely after the update.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _rotation = r);
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      shape: const CircleBorder(),
      color: theme.colorScheme.surface,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Transform.rotate(
            // Counter-rotate so the needle keeps pointing at true north.
            angle: -_rotation * math.pi / 180,
            child: Icon(
              Icons.navigation,
              size: 22,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom drawer that slides up to detail the tapped area: who controls it,
/// and — for councils — the seat composition plus a link to the full page.
class _AreaDrawer extends StatelessWidget {
  final MapArea area;
  final VoidCallback onClose;

  /// Opens the council detail page; null when the area has no page (e.g. a
  /// constituency).
  final VoidCallback? onOpenCouncil;

  /// Opens the sitting MP's page; null when the area has no MP (a council, or a
  /// constituency with a vacant seat).
  final VoidCallback? onOpenMp;

  /// Opens the constituency detail page; null for councils.
  final VoidCallback? onOpenConstituency;

  const _AreaDrawer({
    required this.area,
    required this.onClose,
    this.onOpenCouncil,
    this.onOpenMp,
    this.onOpenConstituency,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final council = area.council;
    final controller = council != null
        ? controlDisplayName(council.control)
        : area.controller;

    return Material(
      elevation: 8,
      color: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 14,
                        height: 14,
                        margin: const EdgeInsets.only(top: 4, right: 12),
                        decoration: BoxDecoration(
                          color: area.border,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              area.name.isNotEmpty ? area.name : 'Unknown area',
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              controller,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        iconSize: 20,
                        onPressed: onClose,
                      ),
                    ],
                  ),
                  if (council != null) ...[
                    const SizedBox(height: 12),
                    _CouncilSummary(council: council),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.tonalIcon(
                        onPressed: onOpenCouncil,
                        icon: const Icon(Icons.open_in_new, size: 18),
                        label: const Text('Full details'),
                      ),
                    ),
                  ],
                  if (onOpenConstituency != null || onOpenMp != null) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (onOpenConstituency != null)
                          FilledButton.tonalIcon(
                            onPressed: onOpenConstituency,
                            icon: const Icon(Icons.how_to_vote_outlined,
                                size: 18),
                            label: const Text('Constituency'),
                          ),
                        if (onOpenMp != null)
                          FilledButton.tonalIcon(
                            onPressed: onOpenMp,
                            icon: const Icon(Icons.person_outline, size: 18),
                            label: const Text('MP details'),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact seat breakdown for a council, shown inside the drawer.
class _CouncilSummary extends StatelessWidget {
  final Council council;
  const _CouncilSummary({required this.council});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final held = council.heldSeats;
    final vacant = council.seats.entries
        .where((e) => e.key.toLowerCase() == 'vacant')
        .fold<int>(0, (sum, e) => sum + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.account_balance_outlined,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              council.type.isNotEmpty ? council.type : 'Local authority',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(width: 16),
            Icon(Icons.event_seat_outlined,
                size: 16, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              '${council.total} seats',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        if (council.total > 0) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final e in held)
                    Expanded(
                      flex: e.value,
                      child: ColoredBox(color: party_util.partyColor(e.key)),
                    ),
                  if (vacant > 0)
                    Expanded(
                      flex: vacant,
                      child: const ColoredBox(color: party_util.noControlColor),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              for (final e in held)
                _SeatChip(
                  label: e.key,
                  seats: e.value,
                  color: party_util.partyColor(e.key),
                ),
              if (vacant > 0)
                _SeatChip(
                  label: 'Vacant',
                  seats: vacant,
                  color: party_util.noControlColor,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// One party's colour swatch, name and seat count in the drawer breakdown.
class _SeatChip extends StatelessWidget {
  final String label;
  final int seats;
  final Color color;

  const _SeatChip({
    required this.label,
    required this.seats,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 6),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text('$label ', style: theme.textTheme.bodySmall),
        Text(
          '$seats',
          style: theme.textTheme.bodySmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// Compact legend of the parties shown on the current map.
class _Legend extends StatelessWidget {
  final MapMode mode;
  const _Legend({required this.mode});

  // The parties worth labelling; minor/local parties fall back to grey.
  static const List<(String, String)> _entries = [
    ('Labour', 'Lab'),
    ('Conservative', 'Con'),
    ('Lib Dem', 'LD'),
    ('SNP', 'SNP'),
    ('Green', 'Green'),
    ('Reform', 'Reform'),
    ('Plaid Cymru', 'Plaid Cymru'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (label, token) in _entries)
              _LegendRow(label: label, color: party_util.partyColor(token)),
            _LegendRow(
              label: mode == MapMode.council ? 'No overall control' : 'Other',
              color: party_util.noControlColor,
            ),
          ],
        ),
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final String label;
  final Color color;
  const _LegendRow({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 12,
            height: 12,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(label, style: Theme.of(context).textTheme.labelSmall),
        ],
      ),
    );
  }
}
