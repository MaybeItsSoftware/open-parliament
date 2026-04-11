// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';

import 'package:open_hansard/main.dart';

void main() {
  testWidgets('Landing page renders redesigned main view', (tester) async {
    await tester.pumpWidget(const OpenHansardApp());
    await tester.pumpAndSettle();

    expect(find.text('ParliamentPulse'), findsOneWidget);
    expect(find.text('Chamber Activity Pulse'), findsOneWidget);
    expect(find.text('Today’s Key Debates'), findsOneWidget);
  });
}
