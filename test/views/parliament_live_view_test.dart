import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import 'package:open_hansard/views/parliament_live_view.dart';

void main() {
  testWidgets(
    'ParliamentLiveView builds on macOS without throwing UnimplementedError',
    (tester) async {
      final previousPlatformOverride = debugDefaultTargetPlatformOverride;
      final previousInstance = WebViewPlatform.instance;

      // Force the app-facing webview to use the WebKit implementation and
      // make it believe it is running on macOS, where setOpaque is
      // unimplemented.
      WebViewPlatform.instance = WebKitWebViewPlatform();
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;

      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ParliamentLiveView(
              url: Uri.parse('https://parliamentlive.tv/event/index/12345'),
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(ParliamentLiveView), findsOneWidget);
      } finally {
        if (previousInstance != null) {
          WebViewPlatform.instance = previousInstance;
        }
        debugDefaultTargetPlatformOverride = previousPlatformOverride;
      }
    },
  );
}
