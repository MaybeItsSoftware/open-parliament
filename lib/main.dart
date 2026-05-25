import 'package:flutter/material.dart';
import 'package:flutter_map_tile_caching/flutter_map_tile_caching.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'services/parliamentary_data_service.dart';
import 'services/saved_speeches_service.dart';
import 'services/theme_service.dart';
import 'utils/map_tiles.dart';
import 'views/date_selector_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final rootDirectory = await getApplicationSupportDirectory();
  await FMTCObjectBoxBackend().initialise(
    rootDirectory: rootDirectory.path,
  );
  await const FMTCStore(cartoLightCacheName).manage.create();

  final themeService = ThemeService();
  await themeService.load();
  final savedSpeechesService = SavedSpeechesService();
  await savedSpeechesService.load();
  runApp(OpenHansardApp(
    themeService: themeService,
    savedSpeechesService: savedSpeechesService,
  ));
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

  const OpenHansardApp({
    super.key,
    required this.themeService,
    required this.savedSpeechesService,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeService),
        ChangeNotifierProvider.value(value: savedSpeechesService),
        Provider<ParliamentaryDataService>(
          create: (_) => ParliamentaryDataService(),
          dispose: (_, service) => service.dispose(),
        ),
      ],
      child: Consumer<ThemeService>(
        builder: (context, theme, _) => MaterialApp(
          title: 'Open Hansard',
          debugShowCheckedModeBanner: false,
          themeMode: theme.themeMode,
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