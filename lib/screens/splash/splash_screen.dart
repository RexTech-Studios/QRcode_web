import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({
    super.key,
    required this.next,
    this.init,
    this.minDuration = const Duration(milliseconds: 2800),
  });

  final WidgetBuilder next;
  final Future<void> Function()? init;
  final Duration minDuration;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Staggered entrance
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2000),
  );

  // Continuous gentle float on the icon
  late final AnimationController _float = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  );

  // Full-screen fade-out
  late final AnimationController _outro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );

  @override
  void initState() {
    super.initState();
    _intro.forward();
    // Start float loop after icon lands (~700 ms)
    Future.delayed(const Duration(milliseconds: 700), () {
      if (mounted) _float.repeat(reverse: true);
    });
    _boot();
  }

  Future<void> _boot() async {
    await Future.wait<void>([
      Future<void>.delayed(widget.minDuration),
      if (widget.init != null) widget.init!(),
    ]);
    if (!mounted) return;
    _float.stop();
    await _outro.forward();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        pageBuilder: (c, a1, a2) => widget.next(c),
        transitionsBuilder: (ctx, a1, a2, child) => child,
      ),
    );
  }

  @override
  void dispose() {
    _intro.dispose();
    _float.dispose();
    _outro.dispose();
    super.dispose();
  }

  Animation<double> _iv(
    double begin,
    double end, [
    Curve curve = Curves.easeOutCubic,
  ]) =>
      CurvedAnimation(
        parent: _intro,
        curve: Interval(begin, end, curve: curve),
      );

  @override
  Widget build(BuildContext context) {
    final outroOpacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _outro, curve: Curves.easeInCubic),
    );

    // Float: icon bobs ±6 px vertically
    final floatOffset = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0, -0.035),
    ).animate(CurvedAnimation(parent: _float, curve: Curves.easeInOut));

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.white,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: FadeTransition(
          opacity: outroOpacity,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(flex: 3),

                    // ── Icon ──────────────────────────────────────────────
                    AnimatedBuilder(
                      animation: Listenable.merge([_intro, _float]),
                      builder: (ctx, child) => FadeTransition(
                        opacity: _iv(0.0, 0.55, Curves.easeIn),
                        child: SlideTransition(
                          position: floatOffset,
                          child: child,
                        ),
                      ),
                      child: _AppIcon(),
                    ),

                    const SizedBox(height: 36),

                    // ── ReviewQR wordmark ─────────────────────────────────
                    AnimatedBuilder(
                      animation: _intro,
                      builder: (ctx, child) => FadeTransition(
                        opacity: _iv(0.25, 0.70, Curves.easeIn),
                        child: child,
                      ),
                      child: RichText(
                        text: const TextSpan(
                          style: TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1.8,
                            height: 1.0,
                          ),
                          children: [
                            TextSpan(
                              text: 'Review',
                              style: TextStyle(color: Color(0xFF18214D)),
                            ),
                            TextSpan(
                              text: 'QR',
                              style: TextStyle(color: Color(0xFF16A34A)),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Tagline ───────────────────────────────────────────
                    AnimatedBuilder(
                      animation: _intro,
                      builder: (ctx, child) => FadeTransition(
                        opacity: _iv(0.40, 0.85, Curves.easeIn),
                        child: child,
                      ),
                      child: const Text(
                        'Smart Google Review Management\nfor Your Business',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 17,
                          height: 1.5,
                          color: Color(0xFF5B6472),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),

                    const Spacer(flex: 3),

                    // ── Loader ────────────────────────────────────────────
                    AnimatedBuilder(
                      animation: _intro,
                      builder: (ctx, child) => FadeTransition(
                        opacity: _iv(0.65, 1.0, Curves.easeIn),
                        child: child,
                      ),
                      child: const _Loader(),
                    ),

                    const SizedBox(height: 60),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Loader extends StatelessWidget {
  const _Loader();

  @override
  Widget build(BuildContext context) {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          height: 36,
          child: CircularProgressIndicator(
            strokeWidth: 3.5,
            backgroundColor: Color(0xFFDCF5E4),
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF16A34A)),
          ),
        ),
        SizedBox(height: 14),
        Text(
          'Loading…',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B7280),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _AppIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // OverflowBox lets the image render larger than its layout slot so the
    // transparent padding baked into the PNG is cropped away visually.
    return SizedBox(
      width: 168,
      height: 168,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: Color(0x47169A3A), // rgba(22,163,74,0.28)
              blurRadius: 40,
              offset: Offset(0, 20),
            ),
          ],
        ),
        child: OverflowBox(
          maxWidth: 210,
          maxHeight: 210,
          child: Image.asset(
            'assets/images/splashscreenicon.png',
            width: 210,
            height: 210,
            fit: BoxFit.contain,
          ),
        ),
      ),
    );
  }
}
