import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/l10n_ext.dart';
import '../../navigation/post_auth_navigation.dart';
import '../../services/auth_provider.dart';
import '../../services/session_storage.dart';
import '../../theme/defensys_tokens.dart';
import '../../theme/login_palette.dart';
import '../../toasts/feedback_toast.dart';
import '../../widgets/defensys_logo_mark.dart';
import '../../widgets/feedback/login_skeleton.dart'
    show LoginSkeletonScreen;
import '../../config/api_config.dart';
import '../../services/api_http.dart';
import '../common/about_screen.dart';
import '../common/privacy_screen.dart';
import '../common/terms_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.sessionMessage});

  final String? sessionMessage;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _rememberMe = false;
  bool _handledAutoRoute = false;
  bool _sessionBannerDismissed = false;
  bool _showGettingStarted = true;
  double _dragStartY = 0;
  double _dragDeltaY = 0;

  LoginPalette get _palette => LoginPalette.of(context);

  @override
  void initState() {
    super.initState();
    _loadInitialState();
  }

  Future<void> _loadInitialState() async {
    final value = await SessionStorage.loadRememberMeChoice();
    final hasSeen = await SessionStorage.hasSeenGettingStarted();
    if (mounted) {
      setState(() {
        _rememberMe = value;
        _showGettingStarted = !hasSeen;
      });
    }
  }

  Future<void> _dismissGettingStarted() async {
    await SessionStorage.setSeenGettingStarted(true);
    if (mounted) {
      setState(() {
        _showGettingStarted = false;
      });
    }
  }

  void _openGettingStarted() {
    setState(() {
      _showGettingStarted = true;
    });
  }

  Widget? _buildSessionBanner() {
    final msg = widget.sessionMessage;
    if (msg == null || msg.isEmpty || _sessionBannerDismissed) {
      return null;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _palette.warningBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _palette.warningBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: _palette.warningText, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: TextStyle(fontSize: 13, color: _palette.warningText),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Dismiss',
            onPressed: () => setState(() => _sessionBannerDismissed = true),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }

  Future<void> _showForgotPasswordDialog() async {
    final resetDone = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ForgotPasswordDialog(),
    );
    if (resetDone == true && mounted) {
      showSuccessToast(
        context,
        'Password reset successful! Please sign in with your new password.',
      );
    }
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    final username = _emailCtrl.text.trim();
    final pass = _passCtrl.text.trim();

    final success = await ref
        .read(authProvider.notifier)
        .login(username, pass, rememberMe: _rememberMe);
    if (!mounted) return;

    if (success) {
      final user = ref.read(authProvider).user!;
      await _navigateAfterAuth(user);
    } else {
      final error = ref.read(authProvider).error ?? 'Login Failed';
      showErrorToast(context, error);
    }
  }

  Future<void> _navigateAfterAuth(Map<String, dynamic> user) async {
    final role = _resolveRole(user);
    final baseRole = user['role'];
    final isWeb = kIsWeb;

    if (!isWeb && baseRole != 'student' && baseRole != 'faculty') {
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      showErrorToast(
        context,
        'The mobile app is for students and defense panelists only. '
        'Admins should use the web app.',
      );
      return;
    }

    if (!isWeb && baseRole == 'faculty' && _facultyNeedsWebApp(user)) {
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      showErrorToast(
        context,
        'Faculty management tools are available in the web app. Open DefenSYS in your browser.',
      );
      return;
    }

    await navigateToHomeAfterAuth(context, role: role, userData: user);
  }

  /// Faculty without the panelist hat need the web app (adviser, PIT lead, uploader, etc.).
  bool _facultyNeedsWebApp(Map<String, dynamic> user) {
    return user['is_panelist'] != true;
  }

  String _resolveRole(Map<String, dynamic> user) {
    final baseRole = user['role'];
    if (baseRole == 'admin') return 'Admin';
    if (baseRole == 'student') return 'Student';

    if (baseRole == 'faculty') {
      if (kIsWeb) return 'Faculty';
      if (user['is_panelist'] == true) return 'Panelist';
      return 'Faculty';
    }

    if (baseRole == 'guest_panelist') return 'Panelist';

    return 'Student';
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);

    ref.listen<AuthState>(authProvider, (previous, next) {
      if (_handledAutoRoute) return;
      if (kIsWeb) return;
      if (!next.isRestoring &&
          next.sessionRestored &&
          next.user != null &&
          next.token != null) {
        _handledAutoRoute = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _navigateAfterAuth(next.user!);
        });
      }
    });

    if (authState.isRestoring) {
      return const LoginSkeletonScreen();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final useWebLayout = kIsWeb && constraints.maxWidth >= 760;
        if (useWebLayout) {
          return _buildWebLayout(authState, constraints);
        }
        return _buildMobileLayout(authState);
      },
    );
  }

  Widget _buildWebLayout(AuthState authState, BoxConstraints constraints) {
    final isCompact = constraints.maxWidth < 980;

    return Scaffold(
      backgroundColor: _palette.background,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Side: Hero Event Carousel & White branding overlays (60%)
          Expanded(
            flex: isCompact ? 5 : 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _HeroCarousel(
                    height: double.infinity,
                    autoPlay: !authState.isLoading,
                  )),
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.15),
                            Colors.black.withValues(alpha: 0.65),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 48,
                  left: 48,
                  right: 48,
                  child: IgnorePointer(
                    child: _brandLockup(isCompact: isCompact, isDarkTheme: true,
                    ),
                  ),
                ),
                Positioned(
                  bottom: 64,
                  left: 48,
                  right: 48,
                  child: IgnorePointer(
                    child: _sloganPanel(isCompact: isCompact),
                  ),
                ),
              ],
            ),
          ),
          // Right Side: Centered Form Input with clean technical grid background (40%)
          Expanded(
            flex: isCompact ? 5 : 4,
            child: Stack(
              children: [
                // Clean slate background gradient
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          _palette.background,
                          _palette.panel],
                      ),
                    ),
                  ),
                ),
                // Centered Form Card with clean elevation & institutional styling
                Positioned.fill(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.symmetric(horizontal: isCompact ? 16 : 32, vertical: 24,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 650),
                          curve: Curves.easeOutCubic,
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(0, 20 * (1.0 - value)),
                              child: Opacity(
                                opacity: value.clamp(0.0, 1.0),
                                child: child,
                              ),
                            );
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Dedicated Institutional Co-Branded Header above the card
                              _buildInstitutionalHeader(),
                              const SizedBox(height: 20),
                              _buildWebLoginCard(authState, isCompact: isCompact),
                              const SizedBox(height: 24),
                              _buildWebFooter(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstitutionalHeader() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Image.asset(
              _palette.isDark
                  ? 'assets/logo-ustp-white.png'
                  : 'assets/logo-ustp-trans.png',
              height: 44,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 16),
            Container(
              width: 1,
              height: 32,
              color: _palette.inputBorder),
            const SizedBox(width: 16),
            SizedBox(
              height: 42,
              width: 42,
              child: Image.asset(
                'assets/logo-legacy.png',
                fit: BoxFit.contain),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'USTP OROQUIETA • DEPARTMENT OF IT',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _palette.label,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildWebFooter() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Department of Information Technology • USTP Oroquieta Campus © 2026',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Inter',
            color: _palette.secondaryText,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            _buildFooterLink('About', () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            }),
            _buildFooterLink('Terms of Service', () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TermsScreen()),
              );
            }),
            _buildFooterLink('Privacy Policy', () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyScreen()),
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildFooterLink(String label, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            color: _palette.secondaryText,
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            decoration: TextDecoration.underline,
            decorationColor: _palette.inputBorder,
          ),
        ),
      ),
    );
  }

  Widget _sloganPanel({required bool isCompact}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Empowering ',
                style: TextStyle(color: Colors.white),
              ),
              const TextSpan(
                text: 'Capstone Research.\n',
                style: TextStyle(color: DefensysTokens.gold),
              ),
              const TextSpan(
                text: 'Safeguarding ',
                style: TextStyle(color: Colors.white),
              ),
              const TextSpan(
                text: 'Academic Integrity.',
                style: TextStyle(color: DefensysTokens.gold),
              ),
            ],
          ),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: isCompact ? 30 : 42,
            fontWeight: FontWeight.w900,
            height: 1.18,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.5),
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: 90,
          height: 4,
          decoration: BoxDecoration(
            color: DefensysTokens.gold,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
        const SizedBox(height: 14),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Text(
            'The official academic portal for capstone milestones, panel rubric evaluations, and institutional repository archiving.',
            style: TextStyle(
              fontFamily: 'Poppins',
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: isCompact ? 13 : 15,
              fontWeight: FontWeight.w400,
              height: 1.45,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  offset: const Offset(0, 1),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _brandLockup({
    required bool isCompact,
    bool isDarkTheme = false,
    bool isMobile = false,
  }) {
    final markSize = isMobile ? 26.0 : (isCompact ? 42.0 : 52.0);
    final fontSize = isMobile ? 18.0 : (isCompact ? 28.0 : 34.0);
    final dividerH = isMobile ? 20.0 : (isCompact ? 36.0 : 46.0);
    final ustpHeight = isMobile ? 24.0 : (isCompact ? 44.0 : 54.0);
    final spacing = isMobile ? 8.0 : (isCompact ? 14.0 : 22.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // DefenSYS System Mark
        SizedBox(
          height: markSize,
          width: markSize,
          child: Image.asset(
            'assets/logo-web-mark-smooth.png',
            fit: BoxFit.contain,
          ),
        ),
        SizedBox(width: isMobile ? 8.0 : 14.0),
        // System Title
        Text(
          'DefenSYS',
          style: TextStyle(
            fontFamily: 'Poppins',
            color: Colors.white,
            fontSize: fontSize,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.6),
                offset: const Offset(0, 2),
                blurRadius: 8,
              ),
            ],
          ),
        ),
        SizedBox(width: spacing),
        // Elegant subtle vertical divider
        Container(
          width: 1.5,
          height: dividerH,
          color: Colors.white.withValues(alpha: 0.5),
        ),
        SizedBox(width: spacing),
        // USTP Monochrome White Logo
        Image.asset(
          'assets/logo-ustp-white.png',
          height: ustpHeight,
          fit: BoxFit.contain,
        ),
      ],
    );
  }

  Widget _buildWebLoginCard(AuthState authState, {required bool isCompact}) {
    final sessionBanner = _buildSessionBanner();

    return Container(
      key: const ValueKey('login_form_surface'),
      decoration: BoxDecoration(
        color: _palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _palette.border,
          width: 1.0),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(
              alpha: _palette.isDark ? 0.24 : 0.06,
            ),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          isCompact ? 24 : 36,
          34,
          isCompact ? 24 : 36,
          30,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Inline Compact Header Lockup (Option 02)
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 46,
                  height: 46,
                  child: Image.asset(
                    'assets/logo-web-mark-smooth.png',
                    fit: BoxFit.contain,
                    color: _palette.isDark ? _palette.link : null,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Welcome back',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: _palette.primaryText,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Sign in to manage defenses & records.',
                        style: TextStyle(
                          fontFamily: 'Poppins',
                          color: _palette.secondaryText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              height: 1,
              color: _palette.subtleSurface),
            const SizedBox(height: 18),
            if (sessionBanner != null) ...[
              sessionBanner,
              const SizedBox(height: 14),
            ],
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WebInputField(
                    controller: _emailCtrl,
                    label: 'Username or Institutional Email',
                    hintText: 'Enter your username or email',
                    prefixIcon: const Icon(Icons.person_outline, size: 20),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter your username'
                        : null,
                    onFieldSubmitted: (_) => _login(),
                  ),
                  const SizedBox(height: 14),
                  _WebInputField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    label: 'Password',
                    hintText: 'Enter your account password',
                    prefixIcon: const Icon(Icons.lock_outline, size: 20),
                    suffixIcon: IconButton(
                      tooltip: _obscure ? 'Show password' : 'Hide password',
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                      splashRadius: 18,
                    ),
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Enter your password'
                        : null,
                    onFieldSubmitted: (_) => _login(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: _rememberMe,
                        onChanged: (value) =>
                            setState(() => _rememberMe = value ?? false),
                        visualDensity: VisualDensity.compact,
                        activeColor: _palette.action,
                        side: BorderSide(color: _palette.muted, width: 1.5,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Remember me',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 13,
                        color: _palette.label,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: _showForgotPasswordDialog,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Text(
                      'Forgot password?',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        color: _palette.link,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _LoginButton(
              onPressed: authState.isLoading ? null : _login,
              isLoading: authState.isLoading,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 14,
                  color: _palette.muted,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Stay signed in only on trusted personal devices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Inter',
                      color: _palette.secondaryText,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(AuthState authState) {
    return Scaffold(
      backgroundColor: _palette.background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final totalH = constraints.maxHeight;
          final targetHeaderH = _showGettingStarted
              ? (totalH * 0.46).clamp(320.0, 440.0)
              : (totalH * 0.28).clamp(180.0, 240.0);

          return Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              _dragStartY = event.position.dy;
              _dragDeltaY = 0;
            },
            onPointerMove: (event) {
              _dragDeltaY = event.position.dy - _dragStartY;
            },
            onPointerUp: (event) {
              if (_showGettingStarted && _dragDeltaY < -28) {
                _dismissGettingStarted();
              } else if (!_showGettingStarted && _dragDeltaY > 48) {
                _openGettingStarted();
              }
            },
            child: Stack(
                  children: [
                    // 1. Top Section: Hero Header (Collage Carousel vs Single Hero Carousel)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeInOutCubic,
                      top: 0,
                      left: 0,
                      right: 0,
                      height: targetHeaderH,
                      child: _buildMobileHeroHeader(
                        autoPlay: !authState.isLoading,
                      ),
                    ),
                    // 2. Bottom Section: Tactile Curved Bottom Sheet
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeInOutCubic,
                      top: (targetHeaderH - 24.0).clamp(0.0, totalH),
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        key: const ValueKey('login_form_surface'),
                        decoration: BoxDecoration(
                          color: _palette.surface,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 20,
                              offset: const Offset(0, -6),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(28),
                          ),
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                            child: Column(
                              children: [
                                // Center grab handle bar
                                Center(
                                  child: GestureDetector(
                                    onTap: _showGettingStarted
                                        ? _dismissGettingStarted
                                        : _openGettingStarted,
                                    behavior: HitTestBehavior.opaque,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4,
                                      ),
                                      child: Container(
                                        width: 38,
                                        height: 4.5,
                                        decoration: BoxDecoration(
                                          color: _palette.inputBorder,
                                          borderRadius: BorderRadius.circular(3,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 260),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  child: _showGettingStarted
                                      ? _buildMobileGettingStartedView()
                                      : _buildMobileLoginFormView(authState),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMobileHeroHeader({required bool autoPlay}) {
    final topPadding = MediaQuery.of(context).padding.top;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Background Hero: Single full-bleed hero carousel with the 7 campus photos
        Positioned.fill(
          child: _HeroCarousel(
            key: const ValueKey('mobile_hero_carousel'),
            height: double.infinity,
            isMobile: true,
            autoPlay: autoPlay,
          ),
        ),
        // Top dark gradient scrim for status bar and branding legibility
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: topPadding + 68,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.65),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        // Top-Left Co-Branding Lockup (DefenSYS | USTP)
        Positioned(
          top: topPadding + 8,
          left: 16,
          child: IgnorePointer(
            child: _brandLockup(
              isCompact: true,
              isDarkTheme: true,
              isMobile: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileGettingStartedView() {
    return Column(
      key: const ValueKey('getting_started_view'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            DefensysLogoMark(
              size: 34,
              customColor: _palette.link),
            const SizedBox(width: 10),
            Text(
              'DefenSYS',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _palette.primaryText,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Empowering Capstone\n& PIT Research',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 21,
            fontWeight: FontWeight.w800,
            color: _palette.link,
            height: 1.25,
            letterSpacing: -0.3,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'USTP Oroquieta Campus Defense\n& Evaluation Portal',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: _palette.secondaryText,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _dismissGettingStarted,
            style: ElevatedButton.styleFrom(
              backgroundColor: _palette.action,
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: _palette.link.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    'Get Started / Sign In',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                Icon(Icons.arrow_forward, size: 18, color: Colors.white),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 20),
        Center(
          child: Text(
            'Department of Information Technology',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _palette.secondaryText,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            _buildLightFooterLink('About Us', () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AboutScreen()),
            ), color: _palette.secondaryText,
            ),
            _buildLightFooterDivider(color: _palette.inputBorder),
            _buildLightFooterLink('Privacy Policy', () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrivacyScreen()),
            ), color: _palette.secondaryText,
            ),
            _buildLightFooterDivider(color: _palette.inputBorder),
            _buildLightFooterLink('Terms', () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TermsScreen()),
            ), color: _palette.secondaryText,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMobileLoginFormView(AuthState authState) {
    return Column(
      key: const ValueKey('login_form_view'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            DefensysLogoMark(
              size: 26,
              customColor: _palette.link),
            SizedBox(width: 8),
            Text(
              'DefenSYS',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _palette.primaryText,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Welcome back',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: _palette.secondaryText,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Sign in',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 28,
            fontWeight: FontWeight.w800,
            color: _palette.primaryText,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 18),
        if (_buildSessionBanner() != null) _buildSessionBanner()!,
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Student ID or Email',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _palette.label,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _emailCtrl,
                keyboardType: TextInputType.text,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _palette.primaryText,
                ),
                decoration: InputDecoration(
                  hintText: 'Student ID or Username',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    color: _palette.muted,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: _palette.inputFill,
                  prefixIcon: Icon(
                    Icons.person_outline,
                    color: _palette.secondaryText,
                    size: 20,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _palette.inputBorder, width: 1.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _palette.link, width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _palette.danger, width: 1.0,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _palette.danger, width: 1.5,
                    ),
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? context.l10n.loginRequiredField
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                'Password',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _palette.label,
                ),
              ),
              const SizedBox(height: 6),
              TextFormField(
                controller: _passCtrl,
                obscureText: _obscure,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: _palette.primaryText,
                ),
                decoration: InputDecoration(
                  hintText: 'Password',
                  hintStyle: TextStyle(
                    fontFamily: 'Poppins',
                    color: _palette.muted,
                    fontSize: 14,
                  ),
                  filled: true,
                  fillColor: _palette.inputFill,
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: _palette.secondaryText,
                    size: 20,
                  ),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: _palette.secondaryText,
                      size: 20,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _palette.inputBorder, width: 1.0,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _palette.link, width: 1.5,
                    ),
                  ),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _palette.danger, width: 1.0,
                    ),
                  ),
                  focusedErrorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: _palette.danger, width: 1.5,
                    ),
                  ),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Enter your password'
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: Checkbox(
                    value: _rememberMe,
                    onChanged: (value) =>
                        setState(() => _rememberMe = value ?? false),
                    visualDensity: VisualDensity.compact,
                    activeColor: _palette.action,
                    side: BorderSide(color: _palette.secondaryText, width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Remember me',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 13,
                    color: _palette.label,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: _showForgotPasswordDialog,
              child: Text(
                'Forgot password?',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  color: _palette.link,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 22),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: authState.isLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: _palette.action,
              foregroundColor: Colors.white,
              elevation: 2,
              shadowColor: _palette.link.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: authState.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Text(
                    'Sign In',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(height: 24),
        Center(
          child: Text(
            'Department of Information Technology',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: _palette.secondaryText,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 4,
          children: [
            _buildLightFooterLink('About Us', () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const AboutScreen()),
            ), color: _palette.secondaryText,
            ),
            _buildLightFooterDivider(color: _palette.inputBorder),
            _buildLightFooterLink('Getting Started', _openGettingStarted, color: _palette.link,
            ),
            _buildLightFooterDivider(color: _palette.inputBorder),
            _buildLightFooterLink('Privacy Policy', () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const PrivacyScreen()),
            ), color: _palette.secondaryText,
            ),
            _buildLightFooterDivider(color: _palette.inputBorder),
            _buildLightFooterLink('Terms', () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TermsScreen()),
            ), color: _palette.secondaryText,
            ),
          ],
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildLightFooterLink(String label, VoidCallback onTap, {Color? color,
  }) {
    final textColor = color ?? const Color(0xFFFDE68A);
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildLightFooterDivider({Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '•',
        style: TextStyle(
          color: color ?? Colors.white54,
          fontSize: 12),
      ),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  }

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({
    super.key,
    required this.height,
    this.isMobile = false,
    this.autoPlay = true,
  });

  final double height;
  final bool isMobile;
  final bool autoPlay;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel>
    with WidgetsBindingObserver {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  static const _imageCount = 7;
  bool _isForeground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: 0);
  }

  void _startTimer() {
    _timer?.cancel();
    // Scaffold removes keyboard insets from the MediaQuery around its body.
    // Read the view directly so typing still pauses the header carousel.
    if (!widget.autoPlay || !_isForeground ||
        (widget.isMobile && View.of(context).viewInsets.bottom > 0) ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted || !_pageController.hasClients || !TickerMode.of(context)) return;
      final nextPage = (_currentPage + 1) % _imageCount;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant _HeroCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.autoPlay != widget.autoPlay) _startTimer();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;
    _startTimer();
  }

  @override
  void didChangeMetrics() {
    if (mounted && widget.isMobile) _startTimer();
  }

  void _goToNextPage() {
    if (!mounted || !_pageController.hasClients) return;
    _timer?.cancel();
    final nextPage = (_currentPage + 1) % _imageCount;
    _pageController.animateToPage(
      nextPage,
      duration: const Duration(milliseconds: 800),
      curve: Curves.easeInOutCubic,
    );
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: SizedBox(
      height: widget.height,
      width: double.infinity,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: _imageCount,
            itemBuilder: (context, index) {
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _goToNextPage,
                  behavior: HitTestBehavior.opaque,
                  child: Image.asset(
                    'assets/login/hero_${widget.isMobile ? 'mobile' : 'desktop'}_${index + 1}.webp',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: widget.isMobile ? 32 : 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _imageCount,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? (widget.isMobile ? Colors.white : DefensysTokens.maroon)
                        : (widget.isMobile
                            ? Colors.white.withValues(alpha: 0.45)
                            : Colors.white.withValues(alpha: 0.5)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ));
  }
}

class _LoginButton extends StatefulWidget {
  const _LoginButton({
    required this.onPressed,
    required this.isLoading});

  final VoidCallback? onPressed;
  final bool isLoading;

  @override
  State<_LoginButton> createState() => _LoginButtonState();
}

class _LoginButtonState extends State<_LoginButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final bool isEnabled = widget.onPressed != null && !widget.isLoading;
    final palette = LoginPalette.of(context);

    return MouseRegion(
      cursor: isEnabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: isEnabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _isHovered && isEnabled ? 1.02 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 48,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: isEnabled
                    ? [
                        palette.actionStart,
                        palette.action]
                    : [
                        palette.inputBorder,
                        palette.inputBorder],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: _isHovered && isEnabled
                  ? [
                      BoxShadow(
                        color: palette.action.withValues(alpha: 0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      )
                    ,
                    ]
                  : [
                      BoxShadow(
                        color: palette.action.withValues(alpha: 0.12),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      )
                    ,
                    ],
            ),
            child: widget.isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Sign In',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                      color: Colors.white,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _WebInputField extends StatefulWidget {
  const _WebInputField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.label,
    this.obscureText = false,
    this.validator,
    this.onFieldSubmitted,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String hintText;
  final String? label;
  final Widget prefixIcon;
  final bool obscureText;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;
  final Widget? suffixIcon;

  @override
  State<_WebInputField> createState() => _WebInputFieldState();
}

class _WebInputFieldState extends State<_WebInputField> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;
  String? _errorText;

  LoginPalette get _palette => LoginPalette.of(context);

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      if (mounted) {
        setState(() {
          _isFocused = _focusNode.hasFocus;
        });
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = _errorText != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.label != null) ...[
          Text(
            widget.label!,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: _palette.label,
            ),
          ),
          const SizedBox(height: 6),
        ],
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: _palette.inputFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasError
                  ? _palette.danger
                  : _isFocused
                      ? _palette.focus
                      : _palette.inputBorder,
              width: _isFocused ? 1.5 : 1.0,
            ),
            boxShadow: _isFocused && !hasError
                ? [
                    BoxShadow(
                      color: _palette.link.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focusNode,
            obscureText: widget.obscureText,
            onFieldSubmitted: widget.onFieldSubmitted,
            validator: (value) {
              if (widget.validator != null) {
                final err = widget.validator!(value);
                if (err != _errorText) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _errorText = err);
                  });
                }
                return err;
              }
              return null;
            },
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: _palette.primaryText,
            ),
            decoration: InputDecoration(
              filled: false,
              hintText: widget.hintText,
              hintStyle: TextStyle(
                color: _palette.muted,
                fontSize: 13.5,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: widget.prefixIcon,
              prefixIconColor: hasError
                  ? _palette.danger
                  : _isFocused
                      ? _palette.focus
                      : _palette.muted,
              suffixIcon: widget.suffixIcon,
              suffixIconColor: hasError
                  ? _palette.danger
                  : _isFocused
                      ? _palette.focus
                      : _palette.muted,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              errorStyle: const TextStyle(height: 0.01, fontSize: 0),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13,
              ),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              _errorText!,
              style: TextStyle(
                color: _palette.danger,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ],
    );
  }
}





enum _ResetStep { request, verifyOtp, newPassword, success }

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  _ResetStep _step = _ResetStep.request;

  // Step 1: Identifier & Delivery Method
  late final TextEditingController _identifierCtrl;
  final _requestFormKey = GlobalKey<FormState>();
  String _deliveryMethod = 'email'; // 'email' or 'sms'

  // Step 2: 6-Digit OTP
  late final List<TextEditingController> _otpCtrls;
  late final List<FocusNode> _otpFocusNodes;
  Timer? _resendTimer;
  int _resendCountdown = 0;
  String _maskedTarget = '';

  // Step 3: Password Update
  late final TextEditingController _newPassCtrl;
  late final TextEditingController _confirmPassCtrl;
  final _passwordFormKey = GlobalKey<FormState>();
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  // State & Reset Tokens
  String _resetToken = '';
  String _uidb64 = '';
  bool _isSubmitting = false;

  LoginPalette get _palette => LoginPalette.of(context);
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _identifierCtrl = TextEditingController();
    _otpCtrls = List.generate(6, (_) => TextEditingController());
    _otpFocusNodes = List.generate(6, (_) => FocusNode());
    _newPassCtrl = TextEditingController();
    _confirmPassCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _identifierCtrl.dispose();
    for (final c in _otpCtrls) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendCountdown = 60);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown <= 1) {
        timer.cancel();
        setState(() => _resendCountdown = 0);
      } else {
        setState(() => _resendCountdown--);
      }
    });
  }

  String get _currentOtp => _otpCtrls.map((c) => c.text.trim()).join();

  // ── Step 1: Request 6-digit OTP ───────────────────────────────────
  Future<void> _submitRequest() async {
    if (!_requestFormKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await apiHttpClient.post(
        Uri.parse('${ApiConfig.baseUrl}/password-reset/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identifier': _identifierCtrl.text.trim(),
          'delivery_method': _deliveryMethod,
        }),
      );

      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        data = null;
      }

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final masked = (data is Map && data['masked_target'] != null)
            ? data['masked_target'].toString()
            : (data is Map && data['masked_phone'] != null && data['masked_phone'].toString().isNotEmpty)
                ? data['masked_phone'].toString()
                : (data is Map && data['masked_email'] != null)
                    ? data['masked_email'].toString()
                    : '';
        setState(() {
          _maskedTarget = masked.isNotEmpty ? masked : _identifierCtrl.text.trim();
          _step = _ResetStep.verifyOtp;
          _errorMessage = null;
        });
        _startResendTimer();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _otpFocusNodes.isNotEmpty) {
            _otpFocusNodes[0].requestFocus();
          }
        });
      } else {
        final detail = data is Map ? data['detail'] : 'Failed to send verification code.';
        setState(() => _errorMessage = detail?.toString() ?? 'An error occurred.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Connection error. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Step 2: Verify 6-digit OTP ────────────────────────────────────
  Future<void> _submitVerifyOtp() async {
    final otp = _currentOtp;
    if (otp.length < 6) {
      setState(() => _errorMessage = 'Please enter all 6 digits of the code.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await apiHttpClient.post(
        Uri.parse('${ApiConfig.baseUrl}/password-reset/verify-otp/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identifier': _identifierCtrl.text.trim(),
          'otp_code': otp,
        }),
      );

      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        data = null;
      }

      if (!mounted) return;

      if (response.statusCode == 200 && data is Map) {
        setState(() {
          _resetToken = data['reset_token']?.toString() ?? '';
          _uidb64 = data['uidb64']?.toString() ?? '';
          _step = _ResetStep.newPassword;
          _errorMessage = null;
        });
      } else {
        final detail = data is Map ? data['detail'] : 'Invalid verification code.';
        setState(() => _errorMessage = detail?.toString() ?? 'Invalid verification code.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Connection error. Please check your network.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // ── Step 3: Update Password ───────────────────────────────────────
  Future<void> _submitNewPassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    if (_newPassCtrl.text != _confirmPassCtrl.text) {
      setState(() => _errorMessage = 'Passwords do not match.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final response = await apiHttpClient.post(
        Uri.parse('${ApiConfig.baseUrl}/password-reset/confirm/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uidb64': _uidb64,
          'reset_token': _resetToken,
          'new_password': _newPassCtrl.text,
          'confirm_password': _confirmPassCtrl.text,
        }),
      );

      dynamic data;
      try {
        data = jsonDecode(response.body);
      } catch (_) {
        data = null;
      }

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() {
          _step = _ResetStep.success;
          _errorMessage = null;
        });
      } else {
        final detail = data is Map ? data['detail'] : 'Failed to reset password.';
        setState(() => _errorMessage = detail?.toString() ?? 'Failed to reset password.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorMessage = 'Connection error. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  // Password Requirement Helpers
  bool get _hasMinLength => _newPassCtrl.text.length >= 8;
  bool get _hasComplexChars =>
      RegExp(r'[A-Za-z]').hasMatch(_newPassCtrl.text) &&
      RegExp(r'[0-9!@#$%^&*(),.?":{}|<>]').hasMatch(_newPassCtrl.text);
  bool get _passwordsMatch =>
      _confirmPassCtrl.text.isNotEmpty && _newPassCtrl.text == _confirmPassCtrl.text;

  int get _score {
    int count = 0;
    if (_hasMinLength) count++;
    if (_hasComplexChars) count++;
    if (_passwordsMatch) count++;
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        inputDecorationTheme: theme.inputDecorationTheme.copyWith(
          hintStyle: TextStyle(color: _palette.muted, fontSize: 14),
          labelStyle: TextStyle(color: _palette.label, fontSize: 14),
          prefixIconColor: _palette.muted,
          suffixIconColor: _palette.muted,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _palette.inputBorder),
          ),
          errorStyle: TextStyle(color: _palette.danger),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(foregroundColor: _palette.link),
        ),
      ),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _palette.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _buildCurrentStepContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStepContent() {
    switch (_step) {
      case _ResetStep.request:
        return _buildRequestStep();
      case _ResetStep.verifyOtp:
        return _buildVerifyOtpStep();
      case _ResetStep.newPassword:
        return _buildNewPasswordStep();
      case _ResetStep.success:
        return _buildSuccessStep();
    }
  }

  // ── 1. Request Step View ──────────────────────────────────────────
  Widget _buildRequestStep() {
    final isSms = _deliveryMethod == 'sms';

    return Form(
      key: _requestFormKey,
      child: Column(
        key: const ValueKey('step_request'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _palette.link.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.lock_reset_rounded, color: _palette.link, size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Reset Password',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 19,
                        color: _palette.primaryText,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Step 1 of 3: Verification',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: _palette.secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 20, color: _palette.secondaryText,
                ),
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Delivery Method Selection Segmented Tabs
          Container(
            decoration: BoxDecoration(
              color: _palette.subtleSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                Expanded(
                  child: _buildDeliveryMethodTab(
                    method: 'email',
                    label: 'Gmail / Email',
                    icon: Icons.mark_email_read_outlined,
                  ),
                ),
                Expanded(
                  child: _buildDeliveryMethodTab(
                    method: 'sms',
                    label: 'SMS / Text',
                    icon: Icons.phone_android_rounded,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            isSms
                ? 'Enter your Student ID, Faculty ID, or registered mobile phone number. We will send you a 6-digit verification code via SMS text message.'
                : 'Enter your Student ID, Faculty ID, or email address. We will send you a 6-digit verification code to your Gmail inbox.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: _palette.label,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          if (_errorMessage != null) ...[
            _buildErrorBadge(_errorMessage!),
            const SizedBox(height: 14),
          ],
          TextFormField(
            controller: _identifierCtrl,
            autofocus: true,
            decoration: InputDecoration(
              labelText: isSms ? 'ID or Mobile Number' : 'ID or Email Address',
              hintText: isSms ? 'e.g. 2023-10042 or 09171234567' : 'e.g. 2023-10042 or user@email.com',
              prefixIcon: Icon(isSms ? Icons.phone_outlined : Icons.person_outline, size: 20,
              ),
              filled: true,
              fillColor: _palette.inputFill,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _palette.link, width: 2,
                ),
              ),
            ),
            validator: (v) => v == null || v.trim().isEmpty
                ? (isSms ? 'Please enter your ID or mobile number' : 'Please enter your ID or email')
                : null,
            onFieldSubmitted: (_) => _isSubmitting ? null : _submitRequest(),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
                child: Text('Cancel', style: TextStyle(color: _palette.secondaryText),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _palette.action,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,
                        ),
                      )
                    : const Text('Send Code', style: TextStyle(fontWeight: FontWeight.w600),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDeliveryMethodTab({
    required String method,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _deliveryMethod == method;
    return InkWell(
      onTap: _isSubmitting
          ? null
          : () {
              setState(() {
                _deliveryMethod = method;
                _errorMessage = null;
              });
            },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        decoration: BoxDecoration(
          color: isSelected ? _palette.surface : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isSelected ? _palette.link : _palette.secondaryText,
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? _palette.link : _palette.secondaryText,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 2. OTP Code Verification Step ─────────────────────────────────
  Widget _buildVerifyOtpStep() {
    final isSms = _deliveryMethod == 'sms';

    return Column(
      key: const ValueKey('step_otp'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _palette.link.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isSms ? Icons.phone_android_rounded : Icons.mark_email_read_outlined,
                color: _palette.link,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Enter Verification Code',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: _palette.primaryText,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Step 2 of 3: 6-Digit Code',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 12,
                      color: _palette.secondaryText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, size: 20, color: _palette.secondaryText),
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            text: 'We sent a 6-digit verification code to ',
            children: [
              TextSpan(
                text: _maskedTarget,
                style: TextStyle(fontWeight: FontWeight.w700, color: _palette.primaryText,
                ),
              ),
              TextSpan(
                text: isSms
                    ? ' via SMS text message. Enter the code below:'
                    : ' via email. Enter the code below:',
              ),
            ],
          ),
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: _palette.label,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        if (_errorMessage != null) ...[
          _buildErrorBadge(_errorMessage!),
          const SizedBox(height: 14),
        ],
        // 6 Digit Input Boxes Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            6,
            (index) => Flexible(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: _buildOtpBox(index),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        // Resend Timer Row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() {
                        _step = _ResetStep.request;
                        _errorMessage = null;
                      });
                    },
              icon: const Icon(Icons.arrow_back, size: 16),
              label: Text(
                isSms ? 'Change ID / Number' : 'Change ID / Email',
                style: const TextStyle(fontSize: 12),
              ),
              style: TextButton.styleFrom(
                foregroundColor: _palette.secondaryText,
                padding: EdgeInsets.zero,
              ),
            ),
            if (_resendCountdown > 0)
              Text(
                'Resend in ${_resendCountdown}s',
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 12,
                  color: _palette.secondaryText,
                  fontWeight: FontWeight.w500,
                ),
              )
            else
              TextButton(
                onPressed: _isSubmitting ? null : _submitRequest,
                style: TextButton.styleFrom(
                  foregroundColor: _palette.link,
                  padding: EdgeInsets.zero,
                ),
                child: const Text('Resend Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
          ],
        ),
        const SizedBox(height: 22),
        ElevatedButton(
          onPressed: (_isSubmitting || _currentOtp.length < 6) ? null : _submitVerifyOtp,
          style: ElevatedButton.styleFrom(
            backgroundColor: _palette.action,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,
                  ),
                )
              : const Text('Verify Code', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
        ),
      ],
    );
  }

  Widget _buildOtpBox(int index) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 48, minWidth: 36),
      child: SizedBox(
        height: 54,
        child: TextFormField(
        controller: _otpCtrls[index],
        focusNode: _otpFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: 1,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: _palette.primaryText,
          fontFamily: 'Poppins',
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: _palette.inputFill,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _palette.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _palette.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: _palette.link, width: 2,
              ),
          ),
        ),
        onChanged: (val) {
          if (val.length > 1) {
            // Handle paste of whole 6 digits into single box
            final digits = val.replaceAll(RegExp(r'\D'), '');
            for (int i = 0; i < 6; i++) {
              if (i < digits.length) {
                _otpCtrls[i].text = digits[i];
              }
            }
            if (digits.length >= 6) {
              _otpFocusNodes[5].requestFocus();
              _submitVerifyOtp();
            }
            return;
          }
          if (val.isNotEmpty) {
            if (index < 5) {
              _otpFocusNodes[index + 1].requestFocus();
            } else {
              _otpFocusNodes[index].unfocus();
              if (_currentOtp.length == 6) {
                _submitVerifyOtp();
              }
            }
          } else {
            if (index > 0) {
              _otpFocusNodes[index - 1].requestFocus();
            }
          }
          setState(() {});
        },
        ),
      ),
    );
  }

  // ── 3. Create New Password Step ───────────────────────────────────
  Widget _buildNewPasswordStep() {
    return Form(
      key: _passwordFormKey,
      child: Column(
        key: const ValueKey('step_new_pass'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _palette.successBackground,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.shield_outlined, color: _palette.success, size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Create New Password',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                        color: _palette.primaryText,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Step 3 of 3: Security Update',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: _palette.secondaryText,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 20, color: _palette.secondaryText,
                ),
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Enter your new password below to regain access to your DefenSYS account.',
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: _palette.label,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          if (_errorMessage != null) ...[
            _buildErrorBadge(_errorMessage!),
            const SizedBox(height: 14),
          ],
          // New Password Input
          TextFormField(
            controller: _newPassCtrl,
            obscureText: _obscureNew,
            onChanged: (_) => setState(() {}),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Enter new password';
              if (v.length < 8) return 'Password must be at least 8 characters';
              return null;
            },
            decoration: InputDecoration(
              labelText: 'New Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                tooltip: _obscureNew ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: _palette.secondaryText,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
              filled: true,
              fillColor: _palette.inputFill,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _palette.link, width: 2,
                ),
              ),
            ),
          ),
          if (_newPassCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildRequirementsCard(),
          ],
          const SizedBox(height: 14),
          // Confirm Password Input
          TextFormField(
            controller: _confirmPassCtrl,
            obscureText: _obscureConfirm,
            onChanged: (_) => setState(() {}),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Confirm your new password';
              if (v != _newPassCtrl.text) return 'Passwords do not match';
              return null;
            },
            decoration: InputDecoration(
              labelText: 'Confirm Password',
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
              suffixIcon: IconButton(
                tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: _palette.secondaryText,
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              filled: true,
              fillColor: _palette.inputFill,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _palette.link, width: 2,
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitNewPassword,
            style: ElevatedButton.styleFrom(
              backgroundColor: _palette.action,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white,
                    ),
                  )
                : const Text('Update Password', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
          ),
        ],
      ),
    );
  }

  // ── 4. Success State View ─────────────────────────────────────────
  Widget _buildSuccessStep() {
    return Column(
      key: const ValueKey('step_success'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _palette.successBackground,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check_circle_outline_rounded,
              size: 48,
              color: _palette.success,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Password Reset Complete',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: _palette.primaryText,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your password has been successfully updated. You can now use your new password to sign in.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: _palette.secondaryText,
            height: 1.5,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, true),
          style: ElevatedButton.styleFrom(
            backgroundColor: _palette.action,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text('Back to Sign In', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorBadge(String error) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _palette.dangerBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _palette.dangerBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: _palette.danger),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: TextStyle(fontSize: 12, color: _palette.danger, fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequirementsCard() {
    String strengthLabel;
    Color strengthColor;
    double strengthPercent;

    switch (_score) {
      case 3:
        strengthLabel = 'Strong';
        strengthColor = _palette.success;
        strengthPercent = 1.0;
        break;
      case 2:
        strengthLabel = 'Fair';
        strengthColor = _palette.isDark
            ? _palette.warningText
            : _palette.warningBorder;
        strengthPercent = 0.66;
        break;
      default:
        strengthLabel = 'Weak';
        strengthColor = _palette.danger;
        strengthPercent = 0.33;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _palette.inputFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, size: 15, color: _palette.secondaryText,
              ),
              const SizedBox(width: 6),
              Text(
                'Password Security',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _palette.primaryText,
                ),
              ),
              const Spacer(),
              Text(
                strengthLabel,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: strengthColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: strengthPercent,
              minHeight: 3.5,
              backgroundColor: _palette.border,
              valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
            ),
          ),
          const SizedBox(height: 8),
          _reqItem('At least 8 characters long', _hasMinLength),
          const SizedBox(height: 4),
          _reqItem('Contains letters & numbers/symbols', _hasComplexChars),
          const SizedBox(height: 4),
          _reqItem('Matches confirmation password', _passwordsMatch),
        ],
      ),
    );
  }

  Widget _reqItem(String label, bool isSatisfied) {
    return Row(
      children: [
        Icon(
          isSatisfied ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: isSatisfied ? _palette.success : _palette.inputBorder,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSatisfied ? FontWeight.w600 : FontWeight.w400,
              color: isSatisfied ? _palette.primaryText : _palette.secondaryText,
            ),
          ),
        ),
      ],
    );
  }
}




