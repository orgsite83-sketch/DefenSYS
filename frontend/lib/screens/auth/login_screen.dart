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
import '../../theme/app_theme.dart';
import '../../toasts/feedback_toast.dart';
import '../../widgets/defensys_logo_mark.dart';
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

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
  }

  Future<void> _loadRememberMe() async {
    final value = await SessionStorage.loadRememberMeChoice();
    if (mounted) setState(() => _rememberMe = value);
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
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFD97706), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              msg,
              style: const TextStyle(fontSize: 13, color: Color(0xFF92400E)),
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
    final sent = await showDialog<bool>(
      context: context,
      builder: (ctx) => const _ForgotPasswordDialog(),
    );
    if (sent == true && mounted) {
      showSuccessToast(
        context,
        'A password reset link has been sent to your email address.',
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
        'Faculty tools (advising, PIT lead, Evaluation & Grades) are available on the web app. Use a browser on desktop.',
      );
      return;
    }

    if (isWeb && baseRole == 'student') {
      await ref.read(authProvider.notifier).logout();
      if (!mounted) return;
      showErrorToast(context, 'Students must use the mobile app.');
      return;
    }

    if (isWeb) {
      await navigateToHomeAfterAuth(context, role: role, userData: user);
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
      backgroundColor: Colors.white,
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left Side: Hero Event Carousel & White branding overlays (60%)
          Expanded(
            flex: 6,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _HeroCarousel(height: double.infinity),
                ),
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
                    child: _brandLockup(isCompact: isCompact, isDarkTheme: true),
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
            flex: 4,
            child: Stack(
              children: [
                // Clean slate background gradient
                Positioned.fill(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFF8FAFC),
                          Color(0xFFF1F5F9),
                        ],
                      ),
                    ),
                  ),
                ),
                // Subtle IT technical grid lines overlay
                Positioned.fill(
                  child: CustomPaint(
                    painter: const _TechnicalGridPainter(),
                  ),
                ),
                // Tech Blueprint Background Elements (Option 1 - Framed Outwards)
                // 1. Top-Left Soft Maroon Square Panel
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: const Offset(-230, -200),
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: DefensysTokens.maroon.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: DefensysTokens.maroon.withValues(alpha: 0.08),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                // 2. Bottom-Right Soft Gold Square Panel
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: const Offset(230, 200),
                    child: Container(
                      width: 130,
                      height: 130,
                      decoration: BoxDecoration(
                        color: DefensysTokens.gold.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: DefensysTokens.gold.withValues(alpha: 0.08),
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),
                ),
                // 3. Top-Left Aligned Dot Grid (Maroon)
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: const Offset(-260, -90),
                    child: _buildBackgroundDotGrid(
                      color: DefensysTokens.maroon,
                      opacity: 0.12,
                    ),
                  ),
                ),
                // 4. Bottom-Right Aligned Dot Grid (Gold)
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: const Offset(260, 90),
                    child: _buildBackgroundDotGrid(
                      color: DefensysTokens.gold,
                      opacity: 0.12,
                    ),
                  ),
                ),
                // 5. Top-Right Aligned Dot Grid (Gold)
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: const Offset(240, -180),
                    child: _buildBackgroundDotGrid(
                      color: DefensysTokens.gold,
                      opacity: 0.12,
                    ),
                  ),
                ),
                // 6. Bottom-Left Aligned Dot Grid (Maroon)
                Align(
                  alignment: Alignment.center,
                  child: Transform.translate(
                    offset: const Offset(-240, 180),
                    child: _buildBackgroundDotGrid(
                      color: DefensysTokens.maroon,
                      opacity: 0.12,
                    ),
                  ),
                ),
                // Centered Form Card
                Positioned.fill(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(begin: 0.0, end: 1.0),
                          duration: const Duration(milliseconds: 800),
                          curve: Curves.easeOutBack,
                          builder: (context, value, child) {
                            return Transform.translate(
                              offset: Offset(0, 30 * (1.0 - value)),
                              child: Opacity(
                                opacity: value.clamp(0.0, 1.0),
                                child: child,
                              ),
                            );
                          },
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildWebLoginCard(authState),
                              const SizedBox(height: 24),
                              const Text(
                                'Department of Information Technology (c) 2026',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
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

  Widget _buildBackgroundDotGrid({required Color color, required double opacity}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (_) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            5,
            (_) => Container(
              margin: const EdgeInsets.all(4.5),
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: color.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            ),
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
                text: 'Defend with ',
                style: TextStyle(color: Colors.white),
              ),
              const TextSpan(
                text: 'clarity.\n',
                style: TextStyle(color: DefensysTokens.gold),
              ),
              const TextSpan(
                text: 'Manage with ',
                style: TextStyle(color: Colors.white),
              ),
              const TextSpan(
                text: 'confidence.',
                style: TextStyle(color: DefensysTokens.gold),
              ),
            ],
          ),
          style: TextStyle(
            fontSize: isCompact ? 36 : 48,
            fontWeight: FontWeight.w900,
            height: 1.15,
            shadows: [
              Shadow(
                color: Colors.black.withValues(alpha: 0.35),
                offset: const Offset(0, 2),
                blurRadius: 6,
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Container(
          width: 120,
          height: 4,
          decoration: BoxDecoration(
            color: DefensysTokens.gold,
            borderRadius: BorderRadius.circular(99),
          ),
        ),
      ],
    );
  }

  Widget _brandLockup({required bool isCompact, bool isDarkTheme = false}) {
    final textColor = isDarkTheme ? Colors.white : DefensysTokens.maroon;
    final subColor = isDarkTheme
        ? Colors.white.withValues(alpha: 0.8)
        : const Color(0xFF475569);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _webLogoMark(size: isCompact ? 48 : 58, color: isDarkTheme ? Colors.white : null),
        const SizedBox(width: 18),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'DefenSYS',
              style: TextStyle(
                color: textColor,
                fontSize: isCompact ? 28 : 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Capstone & PIT Management System',
              style: TextStyle(
                color: subColor,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _webLogoMark({required double size, Color? color}) {
    return DefensysLogoMark(
      size: size,
      customColor: color,
      colorMode: DefensysLogoColorMode.white,
    );
  }

  Widget _cardLogoMark({required double size}) {
    return DefensysLogoMark(
      size: size,
      colorMode: DefensysLogoColorMode.brand,
    );
  }

  Widget _buildWebLoginCard(AuthState authState) {
    final sessionBanner = _buildSessionBanner();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE2E8F0),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Accent Bar (Maroon & Gold Gradient)
            Container(
              height: 4,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    DefensysTokens.maroon,
                    DefensysTokens.gold,
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(32, 32, 32, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo mark at top center (HD, no outline, no circle)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _cardLogoMark(size: 64),
                    ),
                  ),
                  const Text(
                    'Welcome back',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF0F172A),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Sign In to manage defenses, teams, and academic records.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF64748B),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 28),
                  if (sessionBanner != null) sessionBanner,
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _WebInputField(
                          controller: _emailCtrl,
                          hintText: 'Username or Email',
                          prefixIcon: const Icon(Icons.person_outline, size: 22),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter your username'
                              : null,
                          onFieldSubmitted: (_) => _login(),
                        ),
                        const SizedBox(height: 16),
                        _WebInputField(
                          controller: _passCtrl,
                          obscureText: _obscure,
                          hintText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline, size: 21),
                          suffixIcon: IconButton(
                            tooltip: _obscure ? 'Show password' : 'Hide password',
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () => setState(() => _obscure = !_obscure),
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter your password'
                              : null,
                          onFieldSubmitted: (_) => _login(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Remember me & Forgot Password Row inline
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                              activeColor: DefensysTokens.maroon,
                              side: const BorderSide(color: Color(0xFF475569), width: 1.5),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Remember me',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 13,
                              color: Color(0xFF475569),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      GestureDetector(
                        onTap: _showForgotPasswordDialog,
                        child: const Text(
                          'Forgot password?',
                          style: TextStyle(
                            fontFamily: 'Poppins',
                            color: DefensysTokens.maroon,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _LoginButton(
                    onPressed: authState.isLoading ? null : _login,
                    isLoading: authState.isLoading,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Stay signed in only on personal devices.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Color(0xFF64748B),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileLayout(AuthState authState) {
    return Scaffold(
      backgroundColor: const Color(0xFF4D0817),
      body: Stack(
        children: [
          // Background organic vector curves & white sweeping wave
          Positioned.fill(
            child: CustomPaint(
              painter: const _HeaderWavePainter(),
            ),
          ),
          // 1. Watermark logo in upper right of dark background (Subtle faded black)
          Positioned(
            top: -15,
            right: -35,
            child: IgnorePointer(
              child: Opacity(
                opacity: 0.14,
                child: DefensysLogoMark(
                  size: 230,
                  customColor: Colors.black,
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 24),
                          // Header Brand Lockup (Shield Logo + Title + Subtitles)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _webLogoMark(size: 52, color: Colors.white),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Text(
                                      'DefenSYS',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Colors.white,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    const Text(
                                      'Capstone & PIT Management',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Text(
                                      'University Portal',
                                      style: TextStyle(
                                        fontFamily: 'Poppins',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w400,
                                        color: Colors.white.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          // Flexible spacing to position the form card lower into thumb zone
                          const Spacer(),
                          const SizedBox(height: 20),
                          // WHITE CARD CONTAINER (Floating sheet)
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                                width: 1.0,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.16),
                                  blurRadius: 24,
                                  offset: const Offset(0, 10),
                                ),
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(20),
                              child: Stack(
                                children: [
                                  // 2. Faded maroon logo watermark in lower right of the form card sheet
                                  Positioned(
                                    bottom: -25,
                                    right: -25,
                                    child: IgnorePointer(
                                      child: Opacity(
                                        opacity: 0.07,
                                        child: Transform.rotate(
                                          angle: -0.12,
                                          child: const DefensysLogoMark(
                                            size: 180,
                                            customColor: Color(0xFF6B1527),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // Top Accent Bar (Maroon & Gold Gradient)
                                      Container(
                                        height: 4,
                                        decoration: const BoxDecoration(
                                          gradient: LinearGradient(
                                            colors: [
                                              DefensysTokens.maroon,
                                              DefensysTokens.gold,
                                            ],
                                            begin: Alignment.centerLeft,
                                            end: Alignment.centerRight,
                                          ),
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 24),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            const Text(
                                              'Welcome back',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 14,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF64748B),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            const Text(
                                              'Sign in',
                                              style: TextStyle(
                                                fontFamily: 'Poppins',
                                                fontSize: 28,
                                                fontWeight: FontWeight.w800,
                                                color: Color(0xFF0F172A),
                                                letterSpacing: -0.5,
                                              ),
                                            ),
                                            const SizedBox(height: 20),
                                            if (_buildSessionBanner() != null) _buildSessionBanner()!,
                                            Form(
                                              key: _formKey,
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text(
                                                    'Student ID or Email',
                                                    style: TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF334155),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  TextFormField(
                                                    controller: _emailCtrl,
                                                    keyboardType: TextInputType.text,
                                                    style: const TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w500,
                                                      color: DefensysTokens.textDark,
                                                    ),
                                                    decoration: InputDecoration(
                                                      hintText: 'Student ID or Username',
                                                      hintStyle: const TextStyle(
                                                        fontFamily: 'Poppins',
                                                        color: Color(0xFF94A3B8),
                                                        fontSize: 14,
                                                      ),
                                                      filled: true,
                                                      fillColor: const Color(0xFFF8FAFC),
                                                      prefixIcon: const Icon(
                                                        Icons.person_outline,
                                                        color: Color(0xFF64748B),
                                                        size: 20,
                                                      ),
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                                      enabledBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                        borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
                                                      ),
                                                      focusedBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                        borderSide: const BorderSide(color: Color(0xFF6B1527), width: 1.5),
                                                      ),
                                                      errorBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                        borderSide: const BorderSide(color: DefensysTokens.danger, width: 1.0),
                                                      ),
                                                      focusedErrorBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                        borderSide: const BorderSide(color: DefensysTokens.danger, width: 1.5),
                                                      ),
                                                    ),
                                                    validator: (v) => v == null || v.trim().isEmpty
                                                        ? context.l10n.loginRequiredField
                                                        : null,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  const Text(
                                                    'Password',
                                                    style: TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF334155),
                                                    ),
                                                  ),
                                                  const SizedBox(height: 6),
                                                  TextFormField(
                                                    controller: _passCtrl,
                                                    obscureText: _obscure,
                                                    style: const TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 15,
                                                      fontWeight: FontWeight.w500,
                                                      color: DefensysTokens.textDark,
                                                    ),
                                                    decoration: InputDecoration(
                                                      hintText: 'Password',
                                                      hintStyle: const TextStyle(
                                                        fontFamily: 'Poppins',
                                                        color: Color(0xFF94A3B8),
                                                        fontSize: 14,
                                                      ),
                                                      filled: true,
                                                      fillColor: const Color(0xFFF8FAFC),
                                                      prefixIcon: const Icon(
                                                        Icons.lock_outline,
                                                        color: Color(0xFF64748B),
                                                        size: 20,
                                                      ),
                                                      suffixIcon: IconButton(
                                                        tooltip: _obscure ? 'Show password' : 'Hide password',
                                                        icon: Icon(
                                                          _obscure
                                                              ? Icons.visibility_off_outlined
                                                              : Icons.visibility_outlined,
                                                          color: const Color(0xFF64748B),
                                                          size: 20,
                                                        ),
                                                        onPressed: () => setState(() => _obscure = !_obscure),
                                                      ),
                                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                                                      enabledBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                        borderSide: const BorderSide(color: Color(0xFFCBD5E1), width: 1.0),
                                                      ),
                                                      focusedBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                        borderSide: const BorderSide(color: Color(0xFF6B1527), width: 1.5),
                                                      ),
                                                      errorBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                        borderSide: const BorderSide(color: DefensysTokens.danger, width: 1.0),
                                                      ),
                                                      focusedErrorBorder: OutlineInputBorder(
                                                        borderRadius: BorderRadius.circular(12),
                                                        borderSide: const BorderSide(color: DefensysTokens.danger, width: 1.5),
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
                                            // Inline Remember Me & Forgot Password Row
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                                        activeColor: DefensysTokens.maroon,
                                                        side: const BorderSide(color: Color(0xFF64748B), width: 1.5),
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius: BorderRadius.circular(4),
                                                        ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    const Text(
                                                      'Remember me',
                                                      style: TextStyle(
                                                        fontFamily: 'Poppins',
                                                        fontSize: 13,
                                                        color: Color(0xFF475569),
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                GestureDetector(
                                                  onTap: _showForgotPasswordDialog,
                                                  child: const Text(
                                                    'Forgot password?',
                                                    style: TextStyle(
                                                      fontFamily: 'Poppins',
                                                      color: Color(0xFF6B1527),
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 22),
                                            // Primary Sign In Button (Wine red fill)
                                            SizedBox(
                                              width: double.infinity,
                                              height: 52,
                                              child: ElevatedButton(
                                                onPressed: authState.isLoading ? null : _login,
                                                style: ElevatedButton.styleFrom(
                                                  backgroundColor: const Color(0xFF6B1527),
                                                  foregroundColor: Colors.white,
                                                  elevation: 2,
                                                  shadowColor: const Color(0xFF6B1527).withValues(alpha: 0.35),
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
                                            if (!kIsWeb)
                                              // Guest Panelist Access Button (Light cream fill + gold border & key)
                                              SizedBox(
                                                width: double.infinity,
                                                height: 52,
                                                child: OutlinedButton.icon(
                                                  onPressed: _showGuestDialog,
                                                  icon: const Icon(Icons.key_outlined, size: 18, color: Color(0xFF92400E)),
                                                  label: const Text(
                                                    'Guest Panelist Access',
                                                    style: TextStyle(
                                                      fontFamily: 'Poppins',
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                      color: Color(0xFF92400E),
                                                    ),
                                                  ),
                                                  style: OutlinedButton.styleFrom(
                                                    foregroundColor: const Color(0xFF92400E),
                                                    side: const BorderSide(
                                                      color: Color(0xFFF59E0B),
                                                      width: 1.2,
                                                    ),
                                                    backgroundColor: const Color(0xFFFFFBEB),
                                                    shape: RoundedRectangleBorder(
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          const SizedBox(height: 20),
                          // Footer section over dark burgundy background in light colors
                          Center(
                            child: Text(
                              'Department of Information Technology',
                              style: TextStyle(
                                fontFamily: 'Poppins',
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildLightFooterLink('About Us', () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const AboutScreen(),
                                ),
                              ), color: Colors.white.withValues(alpha: 0.85)),
                              _buildLightFooterDivider(),
                              _buildLightFooterLink('Privacy Policy', () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyScreen(),
                                ),
                              ), color: Colors.white.withValues(alpha: 0.85)),
                              _buildLightFooterDivider(),
                              _buildLightFooterLink('Terms', () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const TermsScreen(),
                                ),
                              ), color: Colors.white.withValues(alpha: 0.85)),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLightFooterLink(String label, VoidCallback onTap, {Color? color}) {
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

  Widget _buildLightFooterDivider() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        '•',
        style: TextStyle(
          color: Colors.white54,
          fontSize: 12,
        ),
      ),
    );
  }



  Widget _sealLogo({
    double size = 74,
    bool framed = true,
    String assetPath = 'assets/logo.png',
    bool cropToMark = false,
    Color? color,
  }) {
    final logo = DefensysLogoMark(
      size: size,
      customColor: color,
      colorMode: DefensysLogoColorMode.white,
    );

    if (cropToMark) {
      final croppedLogo = ClipRect(
        child: SizedBox(
          width: size,
          height: size,
          child: Transform.scale(scale: 1.24, child: logo),
        ),
      );

      if (!framed) {
        return SizedBox(width: size, height: size, child: croppedLogo);
      }

      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          border: Border.all(
            color: const Color(0xFFFDE68A).withValues(alpha: 0.5), // Softer delicate gold ring
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipOval(child: croppedLogo),
      );
    }

    if (!framed) {
      return SizedBox(width: size, height: size, child: logo);
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(
          color: const Color(0xFFFDE68A).withValues(alpha: 0.5), // Softer delicate gold ring
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(child: logo),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _showGuestDialog() {
    if (kIsWeb) {
      showErrorToast(
        context,
        'Guest panelist access is available on the mobile app only.',
      );
      return;
    }

    final codeCtrl = TextEditingController();
    final guestFormKey = GlobalKey<FormState>();
    bool isValidating = false;
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.vpn_key_rounded,
                  color: Color(0xFF92400E),
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Guest Access',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Enter the access code provided by the administrator.',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Form(
                key: guestFormKey,
                child: TextFormField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (_) {
                    if (dialogError != null) {
                      setDialogState(() => dialogError = null);
                    }
                  },
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 2,
                    fontFamily: 'monospace',
                  ),
                  decoration: InputDecoration(
                    hintText: 'DEF-XXXXXX',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade300,
                      letterSpacing: 2,
                    ),
                    prefixIcon: const Icon(Icons.lock_open_rounded, size: 20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    errorText: dialogError,
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Enter your access code';
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isValidating
                  ? null
                  : () async {
                      if (!(guestFormKey.currentState?.validate() ?? false)) {
                        return;
                      }

                      final code = codeCtrl.text.trim().toUpperCase();

                      setDialogState(() => isValidating = true);
                      final success = await ref
                          .read(authProvider.notifier)
                          .loginGuest(code);

                      if (!ctx.mounted || !mounted) return;

                      if (success) {
                        final user = ref.read(authProvider).user!;
                        Navigator.pop(ctx);
                        await navigateToHomeAfterAuth(
                          context,
                          role: 'Panelist',
                          userData: user,
                        );
                      } else {
                        setDialogState(() {
                          isValidating = false;
                          dialogError =
                              'Invalid or expired code. Please check and try again.';
                        });
                      }
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF92400E),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: isValidating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Verify & Enter',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroCarousel extends StatefulWidget {
  const _HeroCarousel({required this.height});

  final double height;

  @override
  State<_HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<_HeroCarousel> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;

  final List<String> _images = [
    'assets/login_hero_1.png',
    'assets/login_hero_2.png',
    'assets/login_hero_3.png',
    'assets/login_hero_4.png',
    'assets/login_hero_5.png',
    'assets/login_hero_6.png',
    'assets/login_hero_7.png',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!mounted) return;
      final nextPage = (_currentPage + 1) % _images.length;
      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  void _goToNextPage() {
    if (!mounted) return;
    _timer?.cancel();
    final nextPage = (_currentPage + 1) % _images.length;
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
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
            itemCount: _images.length,
            itemBuilder: (context, index) {
              return MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: _goToNextPage,
                  behavior: HitTestBehavior.opaque,
                  child: Image.asset(
                    _images[index],
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                  ),
                ),
              );
            },
          ),
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _images.length,
                (index) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == index ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == index
                        ? DefensysTokens.maroon
                        : Colors.white.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginButton extends StatefulWidget {
  const _LoginButton({
    required this.onPressed,
    required this.isLoading,
  });

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
            height: 54,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              gradient: LinearGradient(
                colors: isEnabled
                    ? [
                        const Color(0xFF5E0D08),
                        const Color(0xFF7A110A),
                        const Color(0xFF961911),
                      ]
                    : [
                        Colors.grey.shade400,
                        Colors.grey.shade500,
                      ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: _isHovered && isEnabled
                  ? [
                      BoxShadow(
                        color: const Color(0xFF7A110A).withValues(alpha: 0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
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
                    'Log in',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
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
    this.obscureText = false,
    this.validator,
    this.onFieldSubmitted,
    this.suffixIcon,
  });

  final TextEditingController controller;
  final String hintText;
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
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: hasError
                  ? const Color(0xFFDC2626)
                  : _isFocused
                      ? const Color(0xFF7A110A)
                      : const Color(0xFFE2E8F0),
              width: 1.5,
            ),
            boxShadow: _isFocused && !hasError
                ? [
                    BoxShadow(
                      color: const Color(0xFF7A110A).withValues(alpha: 0.08),
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
            style: const TextStyle(
              fontFamily: 'Poppins',
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E293B),
            ),
            decoration: InputDecoration(
              hintText: widget.hintText,
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: widget.prefixIcon,
              prefixIconColor: hasError
                  ? const Color(0xFFDC2626)
                  : _isFocused
                      ? const Color(0xFF7A110A)
                      : const Color(0xFF475569),
              suffixIcon: widget.suffixIcon,
              suffixIconColor: hasError
                  ? const Color(0xFFDC2626)
                  : _isFocused
                      ? const Color(0xFF7A110A)
                      : const Color(0xFF475569),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              errorStyle: const TextStyle(height: 0.01, fontSize: 0),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            ),
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              _errorText!,
              style: const TextStyle(
                color: Color(0xFFDC2626),
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

class _TechnicalGridPainter extends CustomPainter {
  const _TechnicalGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.35)
      ..strokeWidth = 1.0;

    const double step = 32.0;

    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HeaderWavePainter extends CustomPainter {
  const _HeaderWavePainter();

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Dark wine red base background
    final bgPaint = Paint()..color = const Color(0xFF4D0817);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    // 2. Top-right dark maroon wave
    final topWavePaint = Paint()
      ..color = const Color(0xFF6E0D22).withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final topPath = Path();
    topPath.moveTo(0, size.height * 0.22);
    topPath.cubicTo(
      size.width * 0.35,
      size.height * 0.10,
      size.width * 0.75,
      size.height * 0.32,
      size.width,
      size.height * 0.20,
    );
    topPath.lineTo(size.width, 0);
    topPath.lineTo(0, 0);
    topPath.close();
    canvas.drawPath(topPath, topWavePaint);

    // 3. Middle sweeping white organic wave
    final whiteWavePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final whitePath = Path();
    whitePath.moveTo(0, size.height * 0.30);
    whitePath.cubicTo(
      size.width * 0.35,
      size.height * 0.22,
      size.width * 0.85,
      size.height * 0.36,
      size.width,
      size.height * 0.28,
    );
    whitePath.lineTo(size.width, size.height * 0.72);
    whitePath.cubicTo(
      size.width * 0.65,
      size.height * 0.84,
      size.width * 0.15,
      size.height * 0.64,
      0,
      size.height * 0.76,
    );
    whitePath.close();
    canvas.drawPath(whitePath, whiteWavePaint);

    // 4. Bottom dark maroon wave over white wave
    final bottomWavePaint = Paint()
      ..color = const Color(0xFF38040F)
      ..style = PaintingStyle.fill;

    final bottomPath = Path();
    bottomPath.moveTo(0, size.height * 0.78);
    bottomPath.cubicTo(
      size.width * 0.35,
      size.height * 0.70,
      size.width * 0.75,
      size.height * 0.88,
      size.width,
      size.height * 0.78,
    );
    bottomPath.lineTo(size.width, size.height);
    bottomPath.lineTo(0, size.height);
    bottomPath.close();
    canvas.drawPath(bottomPath, bottomWavePaint);

    // 5. Subtle lower overlay wave for organic depth
    final bottomWavePaint2 = Paint()
      ..color = const Color(0xFF5E0B1B).withValues(alpha: 0.6)
      ..style = PaintingStyle.fill;

    final bottomPath2 = Path();
    bottomPath2.moveTo(0, size.height * 0.86);
    bottomPath2.cubicTo(
      size.width * 0.4,
      size.height * 0.80,
      size.width * 0.8,
      size.height * 0.94,
      size.width,
      size.height * 0.88,
    );
    bottomPath2.lineTo(size.width, size.height);
    bottomPath2.lineTo(0, size.height);
    bottomPath2.close();
    canvas.drawPath(bottomPath2, bottomWavePaint2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}



class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog();

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final TextEditingController _identifierCtrl;
  final _dialogFormKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _identifierCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_dialogFormKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await apiHttpClient.post(
        Uri.parse('${ApiConfig.baseUrl}/password-reset/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'identifier': _identifierCtrl.text.trim(),
        }),
      );
    } catch (_) {
      // Best-effort; always show same success message.
    }
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text(
        'Reset Password',
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w700,
          fontSize: 18,
          color: Color(0xFF0F172A),
        ),
      ),
      content: Form(
        key: _dialogFormKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Enter your Student/Employee ID or email address to receive a password reset link.',
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _identifierCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'ID or Email',
                prefixIcon: const Icon(Icons.person_outline, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: DefensysTokens.maroon, width: 2),
                ),
              ),
              validator: (v) => v == null || v.trim().isEmpty
                  ? 'Please enter your ID or email'
                  : null,
              onFieldSubmitted: (_) => _isSubmitting ? null : _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: DefensysTokens.maroon,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Send Reset Link'),
        ),
      ],
    );
  }
}



