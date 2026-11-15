// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:open_parliament/models/member.dart';
import 'package:open_parliament/services/parliamentary_data_service.dart';
import 'package:open_parliament/services/party_service.dart';
import 'package:open_parliament/services/saved_speeches_service.dart';
import 'package:open_parliament/services/startup_prefetch_service.dart';
import 'package:open_parliament/services/theme_service.dart';
import 'package:open_parliament/views/home_shell.dart';
import 'package:open_parliament/views/member_view.dart';
import 'package:open_parliament/views/transcript_view.dart';

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
                    'Open Parliament',
                    style: TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Every word said in Parliament.\nFree, no ads, open source.',
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


/// Westminster green, the app's seed colour (lib/main.dart).
const Color _brandGreen = Color(0xFF006B3C);

/// One store screenshot: a headline over the real app screen, which is laid
/// out at the full device size and scaled down into a rounded "phone".
class _MarketingFrame extends StatelessWidget {
  final String headline;
  final String subhead;
  final Size device;
  final Widget screen;

  const _MarketingFrame({
    required this.headline,
    required this.subhead,
    required this.device,
    required this.screen,
  });

  @override
  Widget build(BuildContext context) {
    // Scale type and spacing off the narrower of width and a share of the
    // height, so tablets (wide, relatively short) don't get giant headlines.
    final w = device.width < device.height * 0.46
        ? device.width
        : device.height * 0.46;
    final mq = MediaQuery.of(context);
    return Container(
      width: device.width,
      height: device.height,
      color: _brandGreen,
      padding: EdgeInsets.fromLTRB(w * 0.07, w * 0.12, w * 0.07, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            headline,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: w * 0.082,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          SizedBox(height: w * 0.03),
          Text(
            subhead,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: w * 0.042,
              height: 1.3,
            ),
          ),
          SizedBox(height: w * 0.07),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.35),
                    width: w * 0.012,
                  ),
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(w * 0.09),
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(w * 0.08),
                  ),
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      width: device.width,
                      height: device.height,
                      child: MediaQuery(
                        data: mq.copyWith(
                          size: device,
                          padding: EdgeInsets.only(top: w * 0.06),
                          viewPadding: EdgeInsets.only(top: w * 0.06),
                        ),
                        child: screen,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The closing screenshot: the free / no ads / open source pitch.
class _PitchFrame extends StatelessWidget {
  final Size device;

  const _PitchFrame({required this.device});

  @override
  Widget build(BuildContext context) {
    // Scale type and spacing off the narrower of width and a share of the
    // height, so tablets (wide, relatively short) don't get giant headlines.
    final w = device.width < device.height * 0.46
        ? device.width
        : device.height * 0.46;
    Widget point(IconData icon, String title, String body) {
      return Padding(
        padding: EdgeInsets.only(bottom: w * 0.07),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: w * 0.15,
              height: w * 0.15,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(w * 0.04),
              ),
              child: Icon(icon, color: Colors.white, size: w * 0.08),
            ),
            SizedBox(width: w * 0.05),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: w * 0.062,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: w * 0.01),
                  Text(
                    body,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: w * 0.04,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: device.width,
      height: device.height,
      color: _brandGreen,
      padding: EdgeInsets.symmetric(horizontal: w * 0.09),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(w * 0.06),
            child: Image.asset(
              'assets/branding/icon.png',
              width: w * 0.26,
              height: w * 0.26,
            ),
          ),
          SizedBox(height: w * 0.07),
          Text(
            'Parliament belongs to everyone. So does this app.',
            style: TextStyle(
              color: Colors.white,
              fontSize: w * 0.08,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          SizedBox(height: w * 0.1),
          point(Icons.money_off_rounded, 'Free',
              'Every feature, no subscriptions or paywalls.'),
          point(Icons.block_rounded, 'No ads',
              'No adverts and no account needed.'),
          point(Icons.code_rounded, 'Open source',
              'MIT-licensed code, public on GitHub.'),
        ],
      ),
    );
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final targets = [
    // --- iOS (deliver) ---
    // 6.7" iPhone (iPhone 14/15/16 Pro Max) - en-GB (using logical size to render correctly)
    for (var i = 1; i <= 6; i++)
      ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone67_$i', width: 430, height: 932, pixelRatio: 3.0),

    // 6.1" iPhone (iPhone 12/13/14/15/16 Pro) - en-GB
    for (var i = 1; i <= 6; i++)
      ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone61_$i', width: 390, height: 844, pixelRatio: 3.0),

    // 6.5" iPhone (iPhone 12/13 Pro Max, 14 Plus) - en-GB
    for (var i = 1; i <= 6; i++)
      ScreenshotTarget(path: 'fastlane/screenshots/en-GB/iphone65_$i', width: 428, height: 926, pixelRatio: 3.0),

    // 12.9" iPad Pro - en-GB
    for (var i = 1; i <= 6; i++)
      ScreenshotTarget(path: 'fastlane/screenshots/en-GB/ipadPro129_$i', width: 1024, height: 1366, pixelRatio: 2.0),

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
    // Warm the bills caches (30-minute in-memory TTL in the data service) so
    // the Bills screenshot isn't captured mid-load on every device size.
    await Future.wait([
      service.fetchRecentBills(skip: 0).catchError((_) => <Map<String, dynamic>>[]),
      service.fetchComingUpBills().catchError((_) => <Map<String, dynamic>>[]),
    ]);
    print('--- Hero debate: ${hero.heroDebateId} on ${hero.dateKey}, '
        'member: ${hero.heroMember.name} ---');

    Widget buildApp(Widget home, GlobalKey key) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: ThemeService()),
          ChangeNotifierProvider.value(value: SavedSpeechesService()),
          ChangeNotifierProvider.value(value: StartupPrefetchService()),
          Provider<ParliamentaryDataService>.value(value: service),
          Provider<PartyService>(create: (_) => PartyService()),
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

      final device = Size(target.width, target.height);
      Widget view;
      var isSearch = false;
      if (target.path.contains('featureGraphic')) {
        view = const FeatureGraphicView();
      } else {
        // Same six screens, in the same order, for every device: indexed by
        // the trailing _N (iOS) or /N (Android).
        final index = int.parse(
          RegExp(r'[_/](\d+)$').firstMatch(target.path)!.group(1)!,
        );
        Widget frame(String headline, String subhead, Widget screen) =>
            _MarketingFrame(
              headline: headline,
              subhead: subhead,
              device: device,
              screen: screen,
            );
        switch (index) {
          case 1:
            view = frame(
              'Every word said in Parliament',
              'Commons and Lords debates, word for word from Hansard',
              const HomeShell(),
            );
          case 2:
            view = frame(
              'See exactly who said what',
              'Speaker photos, parties and roles on every contribution',
              TranscriptView(
                date: hero.dateKey,
                displayDate: hero.displayDate,
                initialDebateId: hero.heroDebateId,
              ),
            );
          case 3:
            view = frame(
              'Check how your MP votes',
              'Profiles, speeches and voting records for every MP and peer',
              MemberView(member: hero.heroMember),
            );
          case 4:
            view = frame(
              'Follow every bill into law',
              'Every stage, all the way to Royal Assent',
              const HomeShell(initialIndex: 2),
            );
          case 5:
            view = frame(
              'Find anything in one search',
              'Debates, MPs, bills, constituencies and councils',
              const HomeShell(initialIndex: 1),
            );
            isSearch = true;
          default:
            view = _PitchFrame(device: device);
        }
      }

      await tester.pumpWidget(buildApp(view, boundaryKey));
      await tester.pump();

      if (isSearch) {
        // A topical query that hits MPs' debates, bills and councils alike.
        // Type a real query and wait past the viewmodel's debounce so the
        // screenshot shows genuine search results, not an empty state.
        await tester.enterText(find.byType(TextField), 'housing');
        await tester.pump(const Duration(milliseconds: 400));
        // Dismiss the on-screen keyboard so it doesn't shrink the Scaffold
        // body (resizeToAvoidBottomInset) or cover the results in the shot.
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump(const Duration(milliseconds: 300));
      }

      // Network-backed views (search, member profile, bills list, ...) show
      // a CircularProgressIndicator while loading — poll for it to clear
      // instead of guessing a fixed duration, bounded to avoid hanging.
      // Network searches (Hansard-wide) can take a while, so allow up to 60s.
      for (var i = 0; i < 120; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
        await tester.pump(const Duration(milliseconds: 500));
        if (find.byType(CircularProgressIndicator).evaluate().isEmpty &&
            find.byType(LinearProgressIndicator).evaluate().isEmpty) {
          break;
        }
      }
      // Let images (portraits) decode before capturing.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 800)),
      );
      await tester.pump();

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
