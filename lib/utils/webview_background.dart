import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Sets the WebView background color only on platforms where the underlying
/// implementation supports it.
///
/// `webview_flutter_wkwebview` calls `setOpaque(false)` as part of
/// `setBackgroundColor`, and `setOpaque` is unimplemented on macOS. Desktop
/// and web shells are development conveniences; skipping the call there keeps
/// them from crashing while mobile (iOS/Android) still gets the transparent
/// background needed for themed surfaces.
Future<void> setWebViewBackgroundColor(
  WebViewController controller,
  Color color,
) async {
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android) {
    await controller.setBackgroundColor(color);
  }
}

/// Injects a minimal reset so the embedded Parliament Live page fills the
/// WebView and hides any default white browser chrome.
///
/// The standalone player page can leave the <body> background white and centre
/// its content, which shows as a white bar on the sides (especially on macOS,
/// where the WebView background cannot be made transparent). This resets the
/// page to a black full-bleed container so the video sits flush.
Future<void> injectWebViewPageStyles(WebViewController controller) async {
  const css =
      'html,body{margin:0!important;padding:0!important;width:100%!important;'
      'height:100%!important;background:#000!important;overflow:hidden!important}'
      '.player-content,.redbee-player-container,#video-wrapper{'
      'width:100%!important;height:100%!important;max-width:none!important;'
      'margin:0 auto!important}'
      '.player-content>*,#video-wrapper>*,.redbee-player-media-container{'
      'width:100%!important;height:100%!important}'
      'video,.theoPlayer,iframe{object-fit:cover!important;width:100%!important;'
      'height:100%!important}';
  await controller.runJavaScript(
    "var style = document.createElement('style');"
    "style.innerHTML = '$css';"
    "(document.head || document.documentElement).appendChild(style);",
  );
}
