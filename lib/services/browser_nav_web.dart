// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Pushes a dummy history entry on top of the current one so that a single
/// back gesture (browser back button, Android back, swipe) fires a
/// `popstate` event instead of leaving this page for whatever came before it
/// in browser history.
void pushHistoryGuard() {
  html.window.history.pushState(null, html.document.title, html.window.location.href);
}

/// Fires [callback] whenever the user attempts to navigate backwards.
///
/// Registered once per screen. The callback is expected to immediately
/// re-push a history guard (see [pushHistoryGuard]) so the user is held on
/// the current page instead of leaving it.
void onPopState(void Function() callback) {
  html.window.onPopState.listen((_) => callback());
}

/// Fires [callback] when the tab becomes visible again (covers returning
/// from an external app/link such as Google Maps via `pageshow` and the
/// Page Visibility API, both of which browsers fire on resume).
void onReturnVisible(void Function() callback) {
  html.window.addEventListener('pageshow', (_) => callback());
  html.document.addEventListener('visibilitychange', (_) {
    if (html.document.visibilityState == 'visible') callback();
  });
}
