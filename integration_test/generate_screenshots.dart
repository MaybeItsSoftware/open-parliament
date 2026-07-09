// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:open_hansard/models/member.dart';
import 'package:open_hansard/services/parliamentary_data_service.dart';
import 'package:open_hansard/services/theme_service.dart';
import 'package:open_hansard/views/date_selector_view.dart';
import 'package:open_hansard/views/transcript_view.dart';
import 'package:open_hansard/views/bills_list_view.dart';
import 'package:open_hansard/views/house_seating_view.dart';
import 'package:open_hansard/views/member_view.dart';
import 'package:open_hansard/views/search_view.dart';

/// Human-readable date like "Monday, 6 July 2026" — matches the format used
/// throughout the real app (see DateSelectorView._friendlyDate).
String _friendlyDate(DateTime day) {
  const weekdays = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday',
  ];
  const months = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];
  return '${weekdays[day.weekday - 1]}, ${day.day} '
      '${months[day.month - 1]} ${day.year}';
}

String _formatDate(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// Fetches a real, recent sitting day's data (mirroring lib/main.dart's
/// startup prefetch) and picks the most substantial debate + a member who
/// actually spoke in it, so screenshots show genuine Hansard content rather
/// than placeholder text.
class _HeroContent {
  final String dateKey;
  final String displayDate;
  final String heroDebateId;
  final Member heroMember;

  const _HeroContent({
    required this.dateKey,
    required this.displayDate,
    required this.heroDebateId,
    required this.heroMember,
  });
}

Future<_HeroContent> _loadHeroContent(ParliamentaryDataService service) async {
  final now = DateTime.now();
  final todayKey = _formatDate(now);

  final hasToday = await service.hasSittingData(todayKey);
  String dateKey;
  if (hasToday) {
    dateKey = todayKey;
  } else {
    final previous = await service.getPreviousSittingDate(todayKey);
    dateKey = previous != null ? _formatDate(previous) : todayKey;
  }

  print('--- Using sitting date: $dateKey ---');
  final speeches = await service.getSpeeches(dateKey);
  final debates = await service.getDebatesForDate(dateKey);
  final members = await service.getMembers();
  print('--- Fetched ${speeches.length} speeches, ${debates.length} debates, ${members.length} members ---');

  // Pick the debate with the most speeches: the richest transcript to show.
  final speechCountByDebate = <String, int>{};
  for (final s in speeches) {
    speechCountByDebate[s.debateId] = (speechCountByDebate[s.debateId] ?? 0) + 1;
  }
  var heroDebateId = debates.isNotEmpty ? debates.first.id : '';
  var bestCount = -1;
  for (final entry in speechCountByDebate.entries) {
    if (entry.value > bestCount) {
      bestCount = entry.value;
      heroDebateId = entry.key;
    }
  }

  // Pick a member who actually spoke in that debate for the profile screenshot.
  Member? heroMember;
  for (final s in speeches) {
    if (s.debateId == heroDebateId && s.memberId != null) {
      heroMember = await service.getMemberById(s.memberId!);
      if (heroMember != null) break;
    }
  }
  heroMember ??= members.isNotEmpty ? members.first : null;

  return _HeroContent(
    dateKey: dateKey,
    displayDate: _friendlyDate(DateTime.parse(dateKey)),
    heroDebateId: heroDebateId,
    heroMember: heroMember ??
        const Member(id: 0, name: 'Unknown', party: '', partyAbbreviation: ''),
  );
}

class ScreenshotTarget {
  final String path;
  final double width;
  final double height;
  final double pixelRatio;

  const ScreenshotTarget({
    required this.path,
    required this.width,
    required this.height,
    required this.pixelRatio,
  });
}

/// Google Play "feature graphic" (1024x500), test-only — never navigated to
/// in the real app, exists purely to produce a store-listing marketing asset.
class FeatureGraphicView extends StatelessWidget {
  const FeatureGraphicView({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 1024,
      height: 500,
      child: Container(
        color: const Color(0xFF006B3C), // Westminster Green, matches lib/main.dart seed color
        padding: const EdgeInsets.symmetric(horizontal: 56),
        child: Row(
          children: [
            Image.asset('assets/branding/icon.png', width: 340, height: 340),
            const SizedBox(width: 48),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Open Hansard',
                    style: TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Read verbatim UK Parliamentary debates offline.',
                    style: TextStyle(color: Colors.white70, fontSize: 28),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final targets = [
    // --- iOS (deliver) ---
    // 6.7" iPhone (iPhone 14/15/16 Pro Max) - en-GB (using logical size to render correctly)
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone67_1', width: 430, height: 932, pixelRatio: 3.0),
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone67_2', width: 430, height: 932, pixelRatio: 3.0),
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone67_3', width: 430, height: 932, pixelRatio: 3.0),

    // 6.1" iPhone (iPhone 12/13/14/15/16 Pro) - en-GB
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone61_1', width: 390, height: 844, pixelRatio: 3.0),
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone61_2', width: 390, height: 844, pixelRatio: 3.0),
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone61_3', width: 390, height: 844, pixelRatio: 3.0),

    // 6.5" iPhone (iPhone 12/13 Pro Max, 14 Plus) - en-GB
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone65_1', width: 428, height: 926, pixelRatio: 3.0),
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone65_2', width: 428, height: 926, pixelRatio: 3.0),
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone65_3', width: 428, height: 926, pixelRatio: 3.0),

    // 12.9" iPad Pro - en-GB
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/ipadPro129_1', width: 1024, height: 1366, pixelRatio: 2.0),
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/ipadPro129_2', width: 1024, height: 1366, pixelRatio: 2.0),
    const ScreenshotTarget(path: 'fastlane/screenshots/en-GB/ipadPro129_3', width: 1024, height: 1366, pixelRatio: 2.0),

    // --- Android (supply) ---
    // Phone - en-GB (1080x1920, exact 9:16)
    for (var i = 1; i <= 6; i++)
      ScreenshotTarget(path: 'fastlane/metadata/android/en-GB/images/phoneScreenshots/$i', width: 360, height: 640, pixelRatio: 3.0),

    // 7" Tablet - en-GB (1620x2880, exact 9:16)
    for (var i = 1; i <= 6; i++)
      ScreenshotTarget(path: 'fastlane/metadata/android/en-GB/images/sevenInchScreenshots/$i', width: 810, height: 1440, pixelRatio: 2.0),

    // 10" Tablet - en-GB (2160x3840, exact 9:16)
    for (var i = 1; i <= 6; i++)
      ScreenshotTarget(path: 'fastlane/metadata/android/en-GB/images/tenInchScreenshots/$i', width: 1080, height: 1920, pixelRatio: 2.0),

    // Feature graphic - en-GB (1024x500, required exact size, no upscaling)
    const ScreenshotTarget(path: 'fastlane/metadata/android/en-GB/images/featureGraphic', width: 1024, height: 500, pixelRatio: 1.0),
  ];

  testWidgets('Generate App Screenshots via GPU rendering', (tester) async {
    final service = ParliamentaryDataService();
    addTearDown(service.dispose);
    final Map<String, String> screenshotMap = {};

    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exceptionAsString().contains('A RenderFlex overflowed')) {
        print('Ignored layout overflow: ${details.exception}');
        return;
      }
      originalOnError?.call(details);
    };

    // Fetch real, recent Hansard data up front so every view below hits a
    // warm cache (network + SQLite) instead of racing a live fetch per frame.
    final hero = await _loadHeroContent(service);
    print('--- Hero debate: ${hero.heroDebateId} on ${hero.dateKey}, '
        'member: ${hero.heroMember.name} ---');

    Widget buildApp(Widget home, GlobalKey key) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ThemeService()),
          Provider<ParliamentaryDataService>.value(value: service),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF006B3C), // Westminster Green, matches lib/main.dart
              brightness: Brightness.light,
            ),
          ),
          home: Scaffold(
            body: RepaintBoundary(
              key: key,
              child: home,
            ),
          ),
        ),
      );
    }

    for (final target in targets) {
      print('--- Capturing target: ${target.path} (${target.width}x${target.height}) ---');
      final boundaryKey = GlobalKey();

      // Force viewport surface size to emulate specific devices
      await binding.setSurfaceSize(Size(target.width, target.height));

      Widget view;
      var isSearch = false;
      if (target.path.contains('featureGraphic')) {
        view = const FeatureGraphicView();
      } else if (target.path.startsWith('fastlane/screenshots/')) {
        // iOS: 3 screens per device, indexed by trailing _N.
        final index = int.parse(RegExp(r'_(\d+)$').firstMatch(target.path)!.group(1)!);
        switch (index) {
          case 1:
            view = const DateSelectorView();
          case 2:
            view = TranscriptView(
              date: hero.dateKey,
              displayDate: hero.displayDate,
              initialDebateId: hero.heroDebateId,
            );
          default:
            view = const BillsListView();
        }
      } else {
        // Android: 6 screens per device category, indexed by trailing /N.
        final index = int.parse(RegExp(r'/(\d+)$').firstMatch(target.path)!.group(1)!);
        switch (index) {
          case 1:
            view = const HouseSeatingView();
          case 2:
            view = TranscriptView(
              date: hero.dateKey,
              displayDate: hero.displayDate,
              initialDebateId: hero.heroDebateId,
            );
          case 3:
            view = const DateSelectorView();
          case 4:
            view = const SearchView();
            isSearch = true;
          case 5:
            view = MemberView(member: hero.heroMember);
          default:
            view = const BillsListView();
        }
      }

      await tester.pumpWidget(buildApp(view, boundaryKey));
      await tester.pump();

      if (isSearch) {
        // Type a real query and wait past the viewmodel's debounce so the
        // screenshot shows genuine search results, not an empty state.
        await tester.enterText(find.byType(TextField), hero.heroMember.name);
        await tester.pump(const Duration(milliseconds: 400));
        // Dismiss the on-screen keyboard so it doesn't shrink the Scaffold
        // body (resizeToAvoidBottomInset) or cover the results in the shot.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Network-backed views (search, member profile, bills list, ...) show
      // a CircularProgressIndicator while loading — poll for it to clear
      // instead of guessing a fixed duration, bounded to avoid hanging.
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty) break;
      }

      // Render RepaintBoundary to PNG bytes
      final RenderRepaintBoundary boundary = boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final ui.Image image = await boundary.toImage(pixelRatio: target.pixelRatio);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final Uint8List pngBytes = byteData!.buffer.asUint8List();

      screenshotMap[target.path] = base64Encode(pngBytes);
    }

    // Report all captured screenshots at once to the driver
    binding.reportData = {
      'screenshots': screenshotMap,
    };

    // Restore original error handler
    FlutterError.onError = originalOnError;
  });
}
