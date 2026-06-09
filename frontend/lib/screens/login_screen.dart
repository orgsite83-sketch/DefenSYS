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
    final pageHeight = constraints.maxHeight < 720
        ? 720.0
        : constraints.maxHeight;
    final isCompact = constraints.maxWidth < 980;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: SizedBox(
          height: pageHeight,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                bottom: 0,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Color(0xFFF8FAFC),
                        Color(0xFFF7F8FA),
                        Color(0xFFF3F4F6),
                      ],
                      stops: [0.0, 0.58, 1.0],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -120,
                bottom: -180,
                width: 520,
                height: 300,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED).withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(48),
                  ),
                ),
              ),
              Positioned(
                top: 92,
                left: 96,
                child: _backgroundTile(
                  size: 74,
                  color: DefensysTokens.gold,
                  opacity: 0.08,
                  radius: 20,
                ),
              ),
              Positioned(
                top: 168,
                left: 214,
                child: _backgroundTile(
                  size: 38,
                  color: DefensysTokens.maroon,
                  opacity: 0.06,
                  radius: 12,
                ),
              ),
              Positioned(
                top: 72,
                right: -110,
                width: 360,
                height: 220,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDECEC).withValues(alpha: 0.58),
                    borderRadius: BorderRadius.circular(44),
                  ),
                ),
              ),
              Positioned(
                top: 128,
                right: 170,
                child: _backgroundTile(
                  size: 52,
                  color: DefensysTokens.gold,
                  opacity: 0.07,
                  radius: 14,
                ),
              ),
              Positioned(
                right: 68,
                bottom: 132,
                child: _backgroundTile(
                  size: 92,
                  color: DefensysTokens.maroon,
                  opacity: 0.045,
                  radius: 22,
                ),
              ),
              Positioned(
                left: 78,
                bottom: 126,
                child: _backgroundDotGrid(
                  color: DefensysTokens.maroon,
                  opacity: 0.11,
                ),
              ),
              Positioned(
                top: 116,
                right: 424,
                child: _backgroundDotGrid(
                  color: DefensysTokens.gold,
                  opacity: 0.12,
                ),
              ),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: isCompact ? 28 : 56,
                    vertical: 34,
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: isCompact ? 5 : 6,
                          child: _buildWebStoryPanel(isCompact: isCompact),
                        ),
                        SizedBox(width: isCompact ? 28 : 58),
                        SizedBox(
                          width: isCompact ? 360 : 390,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _buildWebLoginCard(authState),
                              const SizedBox(height: 28),
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
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _backgroundTile({
    required double size,
    required Color color,
    required double opacity,
    required double radius,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: opacity),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: color.withValues(alpha: opacity * 0.72)),
      ),
    );
  }

  Widget _backgroundDotGrid({required Color color, required double opacity}) {
    return SizedBox(
      width: 74,
      height: 74,
      child: Wrap(
        spacing: 9,
        runSpacing: 9,
        children: List.generate(
          25,
          (_) => Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: color.withValues(alpha: opacity),
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWebStoryPanel({required bool isCompact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _brandLockup(isCompact: isCompact),
        SizedBox(height: isCompact ? 26 : 34),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset(
            'assets/login_hero.png',
            height: isCompact ? 300 : 390,
            width: double.infinity,
            fit: BoxFit.cover,
            alignment: Alignment.center,
          ),
        ),
        SizedBox(height: isCompact ? 24 : 34),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Defend with '),
              const TextSpan(
                text: 'clarity.\n',
                style: TextStyle(color: DefensysTokens.maroon),
              ),
              const TextSpan(text: 'Manage with '),
              const TextSpan(
                text: 'confidence.',
                style: TextStyle(color: DefensysTokens.maroon),
              ),
            ],
          ),
          style: TextStyle(
            color: const Color(0xFF111827),
            fontSize: isCompact ? 36 : 48,
            fontWeight: FontWeight.w900,
            height: 1.08,
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

  Widget _brandLockup({required bool isCompact}) {
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
                color: DefensysTokens.maroon,
                fontSize: isCompact ? 28 : 34,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            const Text(
              'Capstone & PIT Management System',
              style: TextStyle(
                color: Color(0xFF475569),
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
    final assetPath = size <= 50
        ? 'assets/logo-login-mark-48.png'
        : 'assets/logo-login-mark-58.png';

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

  Widget _buildWebLoginCard(AuthState authState) {
    final sessionBanner = _buildSessionBanner();

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 36, 32, 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 36,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: _webLogoMark(size: 58)),
          const SizedBox(height: 24),
          const Text(
            'Welcome back',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF111827),
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sign in to manage defenses, teams, and academic records.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 28),
          if (sessionBanner != null) sessionBanner,
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _emailCtrl,
                  decoration: _webInputDecoration(
                    hintText: 'Username or Email',
                    prefixIcon: const Icon(Icons.person_outline, size: 22),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter your username or email'
                      : null,
                  onFieldSubmitted: (_) => _login(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscure,
                  decoration: _webInputDecoration(
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
          Row(
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
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Remember me',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text(
                  'Forgot password?',
                  style: TextStyle(
                    color: DefensysTokens.maroon,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: authState.isLoading ? null : _login,
              style: ElevatedButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: Colors.white,
                elevation: 0,
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
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Log in',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Stay signed in only on personal devices.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
      fillColor: const Color(0xFFF8FAFC),
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
        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DefensysTokens.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: DefensysTokens.danger, width: 1.4),
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
