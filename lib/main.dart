import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'services/parliamentary_data_service.dart';
import 'services/saved_speeches_service.dart';
import 'services/startup_prefetch_service.dart';
import 'services/theme_service.dart';
import 'services/party_service.dart';
import 'utils/map_tiles.dart';
import 'views/date_selector_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load();
  final sentryDsn = dotenv.env['SENTRY_DSN'] ?? '';

  final rootDirectory = await getApplicationSupportDirectory();
  await FMTCObjectBoxBackend().initialise(
    rootDirectory: rootDirectory.path,
  );
  await const FMTCStore(cartoLightCacheName).manage.create();
  await const FMTCStore(cartoBaseCacheName).manage.create();
  await const FMTCStore(cartoLabelsCacheName).manage.create();

  final themeService = ThemeService();
  await themeService.load();
  final savedSpeechesService = SavedSpeechesService();
  await savedSpeechesService.load();
  final startupPrefetchService = StartupPrefetchService();
  await startupPrefetchService.load();

  if (sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        // Capture all transactions in debug, 20 % in production.
        options.tracesSampleRate = kDebugMode ? 1.0 : 0.2;
        options.environment = kDebugMode ? 'debug' : 'production';
        options.sendDefaultPii = false;
      },
      appRunner: () => _startApp(
        themeService: themeService,
        savedSpeechesService: savedSpeechesService,
        startupPrefetchService: startupPrefetchService,
      ),
    );
  } else {
    // No DSN configured — run without Sentry (local development).
    _startApp(
      themeService: themeService,
      savedSpeechesService: savedSpeechesService,
      startupPrefetchService: startupPrefetchService,
    );
  }
}

/// Launches the widget tree and kicks off optional startup prefetch.
void _startApp({
  required ThemeService themeService,
  required SavedSpeechesService savedSpeechesService,
  required StartupPrefetchService startupPrefetchService,
}) {
  runApp(OpenHansardApp(
    themeService: themeService,
    savedSpeechesService: savedSpeechesService,
    startupPrefetchService: startupPrefetchService,
  ));
  if (startupPrefetchService.prefetchOnStartup) {
    unawaited(_prefetchLatestContent().catchError((error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'startup prefetch',
        ),
      );
    }));
  }
}

/// Root widget for Open Hansard.
///
/// The app is structured around a local-first data strategy:
///  - Member profiles are cached in 'members.db' and refreshed every 30 days.
///  - Sitting transcripts are cached per-day in 'sitting_YYYY-MM-DD.db' files
///    and never re-fetched after the initial download.
///
/// See [ParliamentaryDataService] for full data-layer documentation.
class OpenHansardApp extends StatelessWidget {
  final ThemeService themeService;
  final SavedSpeechesService savedSpeechesService;
  final StartupPrefetchService startupPrefetchService;

  const OpenHansardApp({
    super.key,
    required this.themeService,
    required this.savedSpeechesService,
    required this.startupPrefetchService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider.value(value: savedSpeechesService),
        ChangeNotifierProvider.value(value: startupPrefetchService),
        Provider<ParliamentaryDataService>(
          create: (_) => ParliamentaryDataService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<PartyService>(
          create: (_) => PartyService(),
        ),
      ],
      child: Consumer<ThemeService>(
        builder: (context, theme, _) => MaterialApp(
          title: 'Open Parliament',
          debugShowCheckedModeBanner: false,
          themeMode: theme.themeMode,
          navigatorObservers: [
            SentryNavigatorObserver(),
          ],
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF006B3C),
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 2,
            ),
          ),
          darkTheme: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF006B3C),
              brightness: Brightness.dark,
            ),
            useMaterial3: true,
            appBarTheme: const AppBarTheme(
              centerTitle: true,
              elevation: 2,
            ),
          ),
          home: const DateSelectorView(),
        ),
      ),
    );
  }
}

Future<void> _prefetchLatestContent() async {
  final service = ParliamentaryDataService();
  try {
    await Future.wait(
      [
        service.fetchRecentBills(skip: 0),
        _prefetchLatestDebates(service),
      ],
      eagerError: false,
    );
  } finally {
    service.dispose();
  }
}

Future<void> _prefetchLatestDebates(ParliamentaryDataService service) async {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final todayKey = _formatDate(today);
  final hasToday = await service.hasSittingData(todayKey);
  if (hasToday) {
    await service.getSpeeches(todayKey);
    return;
  }
  final previous = await service.getPreviousSittingDate(todayKey);
  if (previous == null) return;
  await service.getSpeeches(_formatDate(previous));
}

String _formatDate(DateTime day) {
  final y = day.year.toString().padLeft(4, '0');
  final m = day.month.toString().padLeft(2, '0');
  final d = day.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}