// Temporary perf probe for the Control Map fix — not part of the app.
// Runs the real map on macOS, performs timed drags, and reports frame
// timings + point counts. Delete after verification.
// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:open_hansard/services/parliamentary_data_service.dart';
import 'package:open_hansard/utils/map_tiles.dart';
import 'package:open_hansard/views/constituency_map_view.dart';

final GlobalKey _shotKey = GlobalKey();

Future<void> _saveShot(String name) async {
  final boundary =
      _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final dir = Platform.environment['MAP_PROBE_OUT'] ?? '/tmp';
  final file = File('$dir/$name.png');
  await file.writeAsBytes(bytes!.buffer.asUint8List());
  print('--- screenshot: ${file.path} (${bytes.lengthInBytes} bytes) ---');
}

class _Timings {
  final List<FrameTiming> frames = [];
  late final TimingsCallback _cb = frames.addAll;
  void start() => SchedulerBinding.instance.addTimingsCallback(_cb);
  void stop() => SchedulerBinding.instance.removeTimingsCallback(_cb);

  void report(String label) {
    if (frames.isEmpty) {
      print('--- $label: no frames captured ---');
      return;
    }
    final totalsMs = frames
        .map((f) => f.totalSpan.inMicroseconds / 1000.0)
        .toList()
      ..sort();
    final buildsMs = frames
        .map((f) => f.buildDuration.inMicroseconds / 1000.0)
        .toList()
      ..sort();
    double p(List<double> xs, double q) => xs[(xs.length * q).floor().clamp(0, xs.length - 1)];
    final avg = totalsMs.reduce((a, b) => a + b) / totalsMs.length;
    final over32 = totalsMs.where((t) => t > 32).length;
    print('--- $label: ${frames.length} frames | total avg ${avg.toStringAsFixed(1)}ms '
        'p95 ${p(totalsMs, 0.95).toStringAsFixed(1)}ms max ${totalsMs.last.toStringAsFixed(1)}ms | '
        'build max ${buildsMs.last.toStringAsFixed(1)}ms | ${over32}x >32ms ---');
  }
}

int _totalPolygonPoints(WidgetTester tester) {
  var points = 0;
  var polygons = 0;
  for (final w in tester.widgetList(
    find.byWidgetPredicate((w) => w is PolygonLayer),
  )) {
    final layer = w as PolygonLayer;
    polygons += layer.polygons.length;
    for (final p in layer.polygons) {
      points += p.points.length;
      for (final h in p.holePointsList ?? const <List<Object>>[]) {
        points += h.length;
      }
    }
  }
  print('--- polygons on map: $polygons, total points: $points ---');
  return points;
}

Future<void> _waitForPolygons(WidgetTester tester) async {
  final sw = Stopwatch()..start();
  while (sw.elapsed < const Duration(minutes: 3)) {
    await tester.pump(const Duration(milliseconds: 500));
    if (find.byWidgetPredicate((w) => w is PolygonLayer).evaluate().isNotEmpty) {
      print('--- polygons appeared after ${sw.elapsed.inMilliseconds}ms ---');
      // Let tiles/labels settle a little.
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      return;
    }
  }
  fail('Polygon layer never appeared');
}

Future<void> _dragAbout(WidgetTester tester, Finder map) async {
  // A sequence of real-speed drags in different directions, like a user
  // panning around the country.
  const moves = [
    Offset(-140, -90),
    Offset(120, 60),
    Offset(0, 140),
    Offset(-80, -120),
  ];
  for (final move in moves) {
    await tester.timedDrag(map, move, const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('control map pan/zoom performance probe', (tester) async {
    final rootDirectory = await getApplicationSupportDirectory();
    await FMTCObjectBoxBackend().initialise(rootDirectory: rootDirectory.path);
    await const FMTCStore(cartoLightCacheName).manage.create();
    await const FMTCStore(cartoBaseCacheName).manage.create();
    await const FMTCStore(cartoLabelsCacheName).manage.create();

    final service = ParliamentaryDataService();

    await tester.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: Provider<ParliamentaryDataService>.value(
          value: service,
          child: const MaterialApp(home: ConstituencyMapView()),
        ),
      ),
    );

    // ---- Constituency mode ----
    final loadWatch = Stopwatch()..start();
    await _waitForPolygons(tester);
    print('--- constituency mode ready in ${loadWatch.elapsedMilliseconds}ms ---');
    _totalPolygonPoints(tester);

    final map = find.byType(FlutterMap);
    final constituencyTimings = _Timings()..start();
    await _dragAbout(tester, map);
    await tester.pump(const Duration(seconds: 1));
    constituencyTimings.stop();
    constituencyTimings.report('constituency drag');

    // Tap somewhere over England (south-east of the initial UK-centre view)
    // and expect the selection drawer to slide up.
    final center = tester.getCenter(map);
    await tester.tapAt(center + const Offset(50, 110));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final drawerShown = find.text('MP details').evaluate().isNotEmpty ||
        find.text('Constituency').evaluate().isNotEmpty;
    print('--- selection drawer shown: $drawerShown ---');
    await _saveShot('map_constituency_selected');

    // Panning with the drawer open must not rebuild the base layer either.
    final selectedTimings = _Timings()..start();
    await tester.timedDrag(map, const Offset(-100, -60), const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));
    selectedTimings.stop();
    selectedTimings.report('drag with selection open');

    // ---- Council mode ----
    await tester.tap(find.text('Councils'));
    final councilWatch = Stopwatch()..start();
    await _waitForPolygons(tester);
    print('--- council mode ready in ${councilWatch.elapsedMilliseconds}ms ---');
    _totalPolygonPoints(tester);

    final councilTimings = _Timings()..start();
    await _dragAbout(tester, map);
    await tester.pump(const Duration(seconds: 1));
    councilTimings.stop();
    councilTimings.report('council drag');
    await _saveShot('map_council');

    service.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
