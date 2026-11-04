import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/shop_model.dart';
import '../../services/google_sheets_service.dart';
import '../../services/firebase_service.dart';
import '../../services/hive_service.dart';
import '../../services/browser_nav_service.dart';

/// Public, unauthenticated page opened when a customer scans a shop's QR
/// code. Collects a star rating + optional comment and saves feedback to
/// Firestore. High ratings (4–5) redirect to the Google review link so the
/// customer can leave a public review.
///
/// This screen owns a self-contained "premium" visual language that is kept
/// separate from the admin dashboard palette so it can evolve independently.
class ReviewScreen extends StatefulWidget {
  final String shopId;

  const ReviewScreen({super.key, required this.shopId});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

// ---------------------------------------------------------------------------
// Design system (scoped to the customer review experience)
// ---------------------------------------------------------------------------
class _Brand {
  _Brand._();

  static const Color primary = Color(0xFF087A43); // Deep green
  static const Color secondary = Color(0xFF20B76A); // Fresh green
  static const Color background = Color(0xFFF5F8F7); // Soft off-white
  static const Color card = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF172033); // Dark navy
  static const Color textSecondary = Color(0xFF788394); // Muted grey
  static const Color star = Color(0xFFFFB300); // Golden
  static const Color starTrack = Color(0xFFE8F3EC);
  static const Color inputBorder = Color(0xFFE4EAE7);

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF0A8A4C), Color(0xFF05603A)],
  );

  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Color(0xFF0A8A4C), Color(0xFF05603A)],
  );
}

class _ReviewScreenState extends State<ReviewScreen> {
  ShopModel? _shop;
  bool _loading = true;
  int _rating = 0;
  int _hoverRating = 0;
  final _commentController = TextEditingController();
  bool _submitted = false;
  bool _submitting = false;
  bool _wasLowRating = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _commentController.addListener(() => setState(() {}));
    _submitted = HiveService.isReviewSubmitted(widget.shopId);
    _loadShop();

    // Guard against the browser back button (and Android/swipe back) leaving
    // this page for whatever was open before the QR scan, and detect the
    // customer returning from the external Google Maps redirect.
    pushHistoryGuard();
    onPopState(_handleBackAttempt);
    onReturnVisible(_handleReturnVisible);
  }

  /// A back navigation consumed our history guard entry. Immediately re-push
  /// it so the customer is held on the current screen (review or thank-you)
  /// rather than leaving for the previous site/page or closing the tab.
  void _handleBackAttempt() {
    pushHistoryGuard();
  }

  void _handleReturnVisible() {
    final submitted = HiveService.isReviewSubmitted(widget.shopId);
    if (submitted && !_submitted) {
      setState(() => _submitted = true);
    }
    pushHistoryGuard();
  }

  Future<void> _loadShop() async {
    // Cache-first: if this device has seen the shop before, show it instantly
    // (no network wait) and then quietly refresh from Firestore in the
    // background so a renamed shop / updated review link stays current.
    final cached = HiveService.getShop(widget.shopId);
    if (cached != null) {
      setState(() {
        _shop = cached;
        _loading = false;
      });
      unawaited(_refreshShopInBackground());
      return;
    }

    final remote = await FirebaseService.fetchShop(widget.shopId);
    if (remote != null) {
      await HiveService.saveShop(remote);
    }
    if (!mounted) return;
    setState(() {
      _shop = remote;
      _loading = false;
    });
  }

  Future<void> _refreshShopInBackground() async {
    final remote = await FirebaseService.fetchShop(widget.shopId);
    if (remote == null) return;
    await HiveService.saveShop(remote);
    if (!mounted) return;
    setState(() => _shop = remote);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0 || _shop == null) return;
    setState(() {
      _submitting = true;
      _submitError = null;
    });

    final comment = _commentController.text.trim().isEmpty
        ? null
        : _commentController.text.trim();

    // Save feedback to Firestore regardless of rating. If this write fails
    // (offline, Firestore unreachable, etc.) the customer must see an error
    // and be able to retry -- never show Thank You / mark submitted for
    // feedback that was never actually saved.
    final saved = await FirebaseService.submitFeedback(
      shopId: _shop!.shopId,
      rating: _rating,
      comment: comment,
    );

    if (!saved) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _submitError = "We couldn't send your feedback. Please check your connection and try again.";
      });
      return;
    }

    if (_rating <= 3) {
      // 1–3 stars: save to the shop's Google Sheet tab
      await GoogleSheetsService.submitFeedback(
        shopName: _shop!.shopName,
        googleSheetsUrl: _shop!.googleSheetsUrl,
        rating: _rating,
        comment: comment,
      );
      await HiveService.markReviewSubmitted(widget.shopId);
      setState(() {
        _submitting = false;
        _submitted = true;
        _wasLowRating = true;
      });
    } else {
      // Perfect rating (5): mark submitted, then redirect to Google Maps
      await HiveService.markReviewSubmitted(widget.shopId);
      setState(() {
        _submitting = false;
        _submitted = true;
        _wasLowRating = false;
      });
      final uri = Uri.tryParse(_shop!.googleReviewUrl);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    // Breakpoints: phone < 600, tablet 600–1024, desktop > 1024. On phones
    // there's no fixed cap -- the card tracks the screen (see the
    // percentage-based margin in _buildContent) so it stays close to full
    // width on a 320px phone and on a 430px one alike, instead of a single
    // fixed maxWidth reading as comfortably wide on one and cramped on the
    // other.
    final maxWidth = width >= 1024 ? 560.0 : (width >= 600 ? 520.0 : width);

    // canPop: false blocks Flutter route popping for both the review and
    // thank-you states; the browser History API guard (initState) handles
    // the browser/Android hardware back button on web.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: _Brand.background,
        // Let the body shrink when the keyboard opens; the scroll view below
        // keeps every field reachable instead of the layout overflowing.
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          top: false,
          child: Center(
            child: SingleChildScrollView(
              // Dismiss the keyboard on scroll and leave room past the iOS
              // Safari bottom toolbar / home indicator so nothing is clipped.
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewPadding.bottom,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(80),
                        child: Center(
                          child: CircularProgressIndicator(
                            color: _Brand.primary,
                          ),
                        ),
                      )
                    : _shop == null
                    ? Padding(
                        padding: const EdgeInsets.all(28),
                        child: _buildNotFound(),
                      )
                    : _buildContent(_shop!, width),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ShopModel shop, double width) {
    final isWide = width >= 600;
    // On phones, a flat 18px margin reads as near-full-width on a 430px
    // screen but shaves off a disproportionate chunk on a 320px one. Scaling
    // the margin with the screen (clamped to a sane range) keeps the card at
    // roughly 90-94% of the available width across phone sizes instead.
    final horizontalMargin = isWide ? 28.0 : (width * 0.035).clamp(12.0, 20.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildHeader(shop, isWide),
        Transform.translate(
          offset: const Offset(0, -34),
          child: Padding(
            padding: EdgeInsets.fromLTRB(horizontalMargin, 0, horizontalMargin, 24),
            child: _submitted ? _buildThankYou(isWide) : _buildCard(shop, isWide),
          ),
        ),
      ],
    );
  }

  // --- Header -----------------------------------------------------------------
  Widget _buildHeader(ShopModel shop, bool isWide) {
    return ClipPath(
      clipper: _HeaderClipper(),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(24, isWide ? 60 : 44, 24, 60),
        decoration: const BoxDecoration(gradient: _Brand.headerGradient),
        child: Column(
          children: [
            // Storefront icon in a white rounded square
            Container(
              width: isWide ? 100 : 88,
              height: isWide ? 100 : 88,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Icon(
                Icons.storefront_rounded,
                color: _Brand.primary,
                size: isWide ? 52 : 46,
              ),
            ),
            const SizedBox(height: 18),
            // Brand name + verification badge
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    shop.shopName,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isWide ? 28 : 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: _Brand.secondary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              "We'd love to hear from you!",
              style: TextStyle(
                fontSize: 15.5,
                color: Colors.white.withValues(alpha: 0.9),
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Review card ------------------------------------------------------------
  Widget _buildCard(ShopModel shop, bool isWide) {
    final remaining = _commentController.text.characters.length;
    final canSubmit = _rating > 0 && !_submitting;

    return Container(
      padding: EdgeInsets.fromLTRB(isWide ? 30 : 22, 28, isWide ? 30 : 22, 24),
      decoration: BoxDecoration(
        color: _Brand.card,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _Brand.primary.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'How was your experience?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: _Brand.textPrimary,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap a star to rate',
            style: TextStyle(
              fontSize: 15,
              color: _Brand.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          _buildStars(),
          const SizedBox(height: 24),
          _buildFeedbackInput(remaining),
          if (_submitError != null) ...[
            const SizedBox(height: 16),
            _buildSubmitError(_submitError!),
          ],
          const SizedBox(height: 22),
          _buildSubmitButton(canSubmit),
          const SizedBox(height: 18),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildStars() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Size stars to the available width so all five always fit, even on a
        // 320px screen. Spacing shrinks with the stars so there's never
        // horizontal overflow; the upper clamp keeps them from getting huge
        // on wide layouts. No lower clamp — that was what pushed the fifth
        // star off the card on narrow phones.
        final gap = constraints.maxWidth < 340 ? 6.0 : 10.0;
        final raw = (constraints.maxWidth - gap * 4) / 5;
        final size = raw.clamp(40.0, 60.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(5, (i) {
            final active = i < (_hoverRating > 0 ? _hoverRating : _rating);
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: gap / 2),
              child: _StarButton(
                size: size,
                active: active,
                selected: i < _rating,
                onTap: () => setState(() => _rating = i + 1),
                onHover: (hovering) =>
                    setState(() => _hoverRating = hovering ? i + 1 : 0),
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildFeedbackInput(int count) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _Brand.inputBorder, width: 1.4),
      ),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 2),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: _Brand.secondary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _commentController,
                  maxLength: 250,
                  maxLines: 3,
                  minLines: 3,
                  cursorColor: _Brand.primary,
                  style: const TextStyle(
                    fontSize: 15.5,
                    color: _Brand.textPrimary,
                    height: 1.4,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    counterText: '',
                    border: InputBorder.none,
                    hintText: 'Share your feedback (optional)...',
                    hintStyle: TextStyle(
                      color: _Brand.textSecondary,
                      fontSize: 15.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '$count/250',
              style: const TextStyle(
                fontSize: 13,
                color: _Brand.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitError(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFDECEC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF5C2C2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Color(0xFFC0392B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFFC0392B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton(bool enabled) {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled || _submitting ? 1 : 0.45,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: _Brand.buttonGradient,
            borderRadius: BorderRadius.circular(20),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: _Brand.primary.withValues(alpha: 0.35),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: enabled ? _submit : null,
              child: Center(
                child: _submitting
                    ? const SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.6,
                        ),
                      )
                    : const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Submit Review',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(
          Icons.verified_user_rounded,
          color: _Brand.secondary,
          size: 18,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'Your feedback helps us serve you better!',
            style: TextStyle(
              fontSize: 13.5,
              color: _Brand.textSecondary.withValues(alpha: 0.9),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  // --- Thank-you state --------------------------------------------------------
  Widget _buildThankYou(bool isWide) {
    final isLow = _wasLowRating;
    final heading = isLow ? 'We hear you!' : 'Thank you for your review!';
    final body = isLow
        ? 'Thank you for sharing your experience. Your feedback has been sent directly to the team and we will work to make things right.'
        : "We're glad you had a great experience! We've opened Google Maps so you can share it with others.";

    return Container(
      padding: EdgeInsets.fromLTRB(
        isWide ? 36 : 26,
        40,
        isWide ? 36 : 26,
        40,
      ),
      decoration: BoxDecoration(
        color: _Brand.card,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _Brand.primary.withValues(alpha: 0.08),
            blurRadius: 40,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, value, child) =>
                Transform.scale(scale: value, child: child),
            child: _buildThankYouBadge(isLow),
          ),
          const SizedBox(height: 26),
          Text(
            heading,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isWide ? 28 : 24,
              fontWeight: FontWeight.w800,
              color: _Brand.textPrimary,
              letterSpacing: -0.6,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 16,
              color: _Brand.textSecondary,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 26),
          _buildSentPill(),
        ],
      ),
    );
  }

  /// Soft glowing badge: a heart for low ratings (empathy), a check for high.
  Widget _buildThankYouBadge(bool isLow) {
    return Container(
      width: 112,
      height: 112,
      decoration: BoxDecoration(
        color: _Brand.secondary.withValues(alpha: 0.12),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF35C06E), Color(0xFF0E7C40)],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: _Brand.primary.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Icon(
            isLow ? Icons.favorite_rounded : Icons.check_rounded,
            color: Colors.white,
            size: 40,
          ),
        ),
      ),
    );
  }

  Widget _buildSentPill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _Brand.secondary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(40),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.send_rounded, color: _Brand.primary, size: 18),
          SizedBox(width: 10),
          Text(
            'Feedback Sent Successfully',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: _Brand.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotFound() {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _Brand.card,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.storefront_outlined, color: _Brand.textSecondary, size: 44),
          SizedBox(height: 16),
          Text(
            "We couldn't find this shop. Please ask the business for a new QR code.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: _Brand.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Animated star button
// ---------------------------------------------------------------------------
class _StarButton extends StatelessWidget {
  final double size;
  final bool active;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onHover;

  const _StarButton({
    required this.size,
    required this.active,
    required this.selected,
    required this.onTap,
    required this.onHover,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFFFF4D6)
                : _Brand.starTrack,
            shape: BoxShape.circle,
          ),
          child: AnimatedScale(
            scale: selected ? 1.0 : (active ? 1.0 : 0.92),
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutBack,
            child: Icon(
              active ? Icons.star_rounded : Icons.star_outline_rounded,
              color: active ? _Brand.star : const Color(0xFFBFC7C2),
              size: size * 0.6,
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Curved header bottom edge
// ---------------------------------------------------------------------------
class _HeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 40);
    path.quadraticBezierTo(
      size.width * 0.25,
      size.height,
      size.width * 0.5,
      size.height - 24,
    );
    path.quadraticBezierTo(
      size.width * 0.78,
      size.height - 52,
      size.width,
      size.height - 16,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
