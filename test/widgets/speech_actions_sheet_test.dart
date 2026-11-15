import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_parliament/models/saved_speech.dart';
import 'package:open_parliament/services/saved_speeches_service.dart';
import 'package:open_parliament/widgets/speech_actions_sheet.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _speech = SavedSpeech(
  speechId: 's1',
  date: '2026-05-25',
  displayDate: '25 May 2026',
  debateId: 'deb-1',
  debateTitle: 'Finance Bill',
  speakerName: 'Jane Smith',
  speechText: 'I beg to move.',
  savedAt: DateTime(2026, 5, 25, 12),
);

Future<void> _openSheet(
  WidgetTester tester, {
  VoidCallback? onWatchFromHere,
  String? watchFromHereLabel,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider(
      create: (_) => SavedSpeechesService(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed:
                      () => showSpeechActionsSheet(
                        context,
                        speech: _speech,
                        onWatchFromHere: onWatchFromHere,
                        watchFromHereLabel: watchFromHereLabel,
                      ),
                  child: const Text('open'),
                ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('hides "Watch from here" when no callback is supplied', (
    tester,
  ) async {
    await _openSheet(tester);

    expect(find.text('Copy text'), findsOneWidget);
    expect(find.text('Watch from here'), findsNothing);
  });

  testWidgets('shows "Watch from here" with label and invokes the callback', (
    tester,
  ) async {
    var calls = 0;
    await _openSheet(
      tester,
      onWatchFromHere: () => calls++,
      watchFromHereLabel: 'Parliament Live from about 14:32',
    );

    expect(find.text('Watch from here'), findsOneWidget);
    expect(find.text('Parliament Live from about 14:32'), findsOneWidget);

    await tester.tap(find.text('Watch from here'));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byType(SpeechActionsSheet), findsNothing);
  });
}
