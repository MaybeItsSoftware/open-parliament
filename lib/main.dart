import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'services/parliamentary_data_service.dart';
import 'views/date_selector_view.dart';

void main() {
  runApp(const OpenHansardApp());
}

/// Root widget for Open Hansard.
///
/// The app is structured around a local-first data strategy:
///  - Member profiles are cached in `members.db` and refreshed every 30 days.
///  - Sitting transcripts are cached per-day in `sitting_YYYY-MM-DD.db` files
///    and never re-fetched after the initial download.
///
/// See [ParliamentaryDataService] for full data-layer documentation.
class OpenHansardApp extends StatelessWidget {
  const OpenHansardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Provider<ParliamentaryDataService>(
      create: (_) => ParliamentaryDataService(),
      dispose: (_, service) => service.dispose(),
      child: MaterialApp(
        title: 'Open Hansard',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            // Parliamentary green – echoes the traditional colour of the
            // House of Commons benches.
            seedColor: const Color(0xFF006B3C),
          ),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 2,
          ),
        ),
        home: const DateSelectorView(),
      ),
    );
  }
}
