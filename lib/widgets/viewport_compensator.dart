import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/viewport_info_service.dart';

/// Wraps [child] so it renders at a readable size even when a mobile browser
/// is in "Request Desktop Site" mode.
///
/// That mode widens the page's layout viewport (what Flutter's `MediaQuery`
/// sees as `size.width`, typically jumping to ~980px) and then the browser
/// zooms the whole rendered page out so it still fits the real screen --
/// shrinking every widget, font and button uniformly. Flutter has no way to
/// opt out of that: it only ever sees the widened logical size.
///
/// This widget detects the mismatch by comparing that logical size against
/// `window.screen.width` (the real, physical display width, which "Request
/// Desktop Site" does not change) and, when found, does the inverse: it
/// builds [child] against a `MediaQuery` override sized to the *real* screen
/// (so phone breakpoints and the 90-94%-width card sizing in `ReviewScreen`
/// kick in as they would normally) and then pre-inflates that render with
/// `Transform.scale` by exactly the ratio the browser is about to shrink it
/// back down by. The two cancel out, so the final on-screen result looks
/// like ordinary mobile rendering instead of a tiny desktop page.
///
/// On a real desktop browser, or normal mobile browsing (no desktop-site
/// override), the logical and physical widths roughly agree, so this is a
/// no-op passthrough -- [child] is laid out exactly as before.
class ViewportCompensator extends StatelessWidget {
  final Widget child;

  const ViewportCompensator({super.key, required this.child});

  /// How much wider the logical (`MediaQuery`) width has to be than the
  /// physical screen width before this is treated as a faked desktop
  /// viewport rather than just browser-chrome rounding noise.
  static const double _fakeViewportRatioThreshold = 1.35;

  /// Physical screen widths at or above this are treated as an actual
  /// desktop/tablet display, never as "mobile in desktop-site mode".
  static const double _maxPhysicalMobileWidth = 600;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final logicalSize = mq.size;
    final physicalWidth = physicalScreenWidth();

    final isFakedDesktopOnMobile = physicalWidth != null &&
        physicalWidth > 0 &&
        physicalWidth < _maxPhysicalMobileWidth &&
        logicalSize.width > physicalWidth * _fakeViewportRatioThreshold;

    if (!isFakedDesktopOnMobile) {
      return child;
    }

    final scaleFactor =
        (logicalSize.width / physicalWidth).clamp(1.0, 3.0);
    final effectiveSize = Size(
      logicalSize.width / scaleFactor,
      logicalSize.height / scaleFactor,
    );

    if (kDebugMode) {
      debugPrint(
        '[ViewportCompensator] desktop-site-on-mobile detected -- '
        'viewport(logical) width=${logicalSize.width.toStringAsFixed(1)}, '
        'physical screen width=${physicalWidth.toStringAsFixed(1)}, '
        'compensated layout width=${effectiveSize.width.toStringAsFixed(1)}, '
        'scale=${scaleFactor.toStringAsFixed(2)}',
      );
    }

    return Transform.scale(
      scale: scaleFactor,
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: effectiveSize.width,
        height: effectiveSize.height,
        child: MediaQuery(
          data: mq.copyWith(size: effectiveSize),
          child: child,
        ),
      ),
    );
  }
}
