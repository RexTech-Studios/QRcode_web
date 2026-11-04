// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// The device's real screen width in CSS pixels, from `window.screen.width`.
///
/// Unlike `window.innerWidth` (what Flutter's `MediaQuery` is built from),
/// this reflects the physical display and is unaffected by a mobile browser's
/// "Request Desktop Site" mode, which widens the page's layout viewport
/// (`innerWidth`) to ~980px and then zooms the whole render out to fit the
/// real screen -- shrinking every widget uniformly. Comparing the two lets a
/// screen detect that faked-desktop-on-mobile case and compensate.
double? physicalScreenWidth() => html.window.screen?.width?.toDouble();
