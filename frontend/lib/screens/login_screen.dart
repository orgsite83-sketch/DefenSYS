import 'dart:async';
import 'dart:ui' show ImageFilter;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n_ext.dart';
import '../navigation/post_auth_navigation.dart';
import '../services/auth_provider.dart';
import '../services/session_storage.dart';
import '../theme/defensys_tokens.dart';
import '../theme/app_theme.dart';
import '../widgets/feedback_toast.dart';
import 'about_screen.dart';
import 'privacy_screen.dart';
import 'terms_screen.dart';

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
        'Faculty tools (advising, PIT lead, Grade Center) are available on the web app. '
        'Use a browser on desktop.',
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
                        color: DefensysTokens.maroon.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: DefensysTokens.maroon.withOpacity(0.08),
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
                        color: DefensysTokens.gold.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: DefensysTokens.gold.withOpacity(0.08),
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
                color: color.withOpacity(opacity),
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
        _webLogoMark(size: isCompact ? 48 : 58),
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

  Widget _webLogoMark({required double size}) {
    // Select the best resolution mark based on required size to prevent pixelation
    final String assetPath;
    if (size <= 48) {
      assetPath = 'assets/logo-login-mark-48.png';
    } else if (size <= 58) {
      assetPath = 'assets/logo-login-mark-58.png';
    } else if (size <= 74) {
      assetPath = 'assets/logo-login-mark-74.png';
    } else {
      assetPath = 'assets/logo-login-mark-116.png';
    }

    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        errorBuilder: (context, error, stackTrace) {
          return _sealLogo(size: size, framed: false, cropToMark: true);
        },
      ),
    );
  }

  Widget _cardLogoMark({required double size}) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/logo-web-mark-smooth.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        isAntiAlias: true,
        errorBuilder: (context, error, stackTrace) {
          return _sealLogo(size: size, framed: false, cropToMark: true);
        },
      ),
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
            color: Colors.black.withOpacity(0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
                        onTap: () {},
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
      backgroundColor: AppColors.maroon,
      body: SafeArea(
        child: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: SingleChildScrollView(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
                  child: Column(
                    children: [
                      _sealLogo(),
                      const SizedBox(height: 16),
                      const Text(
                        'DefenSYS',
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Capstone & PIT Management',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.white.withValues(alpha: 0.7),
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome back',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.loginSignIn,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 28),
                      if (_buildSessionBanner() != null) _buildSessionBanner()!,
                      Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.text,
                              decoration: InputDecoration(
                                labelText: context.l10n.loginStudentIdLabel,
                                prefixIcon: const Icon(
                                  Icons.badge_outlined,
                                  size: 20,
                                ),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? context.l10n.loginRequiredField
                                  : null,
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              decoration: InputDecoration(
                                labelText: context.l10n.loginPasswordLabel,
                                prefixIcon: const Icon(
                                  Icons.lock_outline,
                                  size: 20,
                                ),
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Show password'
                                      : 'Hide password',
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    size: 20,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Enter your password'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {},
                          child: const Text(
                            'Forgot password?',
                            style: TextStyle(
                              color: AppColors.maroon,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: authState.isLoading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.maroon,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: authState.isLoading
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
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!kIsWeb)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _showGuestDialog,
                            icon: const Icon(Icons.vpn_key_rounded, size: 18),
                            label: const Text(
                              'Guest Panelist Access',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF92400E),
                              side: const BorderSide(
                                color: Color(0xFFFDE68A),
                                width: 1.5,
                              ),
                              backgroundColor: const Color(0xFFFFFBEB),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      Center(
                        child: Text(
                          'Department of Information Technology',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const AboutScreen(),
                              ),
                            ),
                            child: const Text(
                              'About Us',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.maroon,
                              ),
                            ),
                          ),
                          Text(
                            '|',
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PrivacyScreen(),
                              ),
                            ),
                            child: const Text(
                              'Privacy Policy',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.maroon,
                              ),
                            ),
                          ),
                          Text(
                            '|',
                            style: TextStyle(
                              color: AppColors.textSecondary.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const TermsScreen(),
                              ),
                            ),
                            child: const Text(
                              'Terms',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.maroon,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _webInputDecoration({
    String? hintText,
    Widget? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFF8FAFC).withValues(alpha: 0.8),
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      prefixIconColor: const Color(0xFF475569),
      suffixIconColor: const Color(0xFF475569),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DefensysTokens.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DefensysTokens.danger, width: 1.8),
      ),
    );
  }

  Widget _sealLogo({
    double size = 74,
    bool framed = true,
    String assetPath = 'assets/logo.png',
    bool cropToMark = false,
  }) {
    final logo = Image.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      isAntiAlias: true,
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.14),
              blurRadius: 12,
              offset: const Offset(0, 5),
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.14),
            blurRadius: 12,
            offset: const Offset(0, 5),
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
                        color: const Color(0xFF7A110A).withOpacity(0.4),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      )
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.12),
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
                      color: const Color(0xFF7A110A).withOpacity(0.08),
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
      ..color = const Color(0xFFE2E8F0).withOpacity(0.35)
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

