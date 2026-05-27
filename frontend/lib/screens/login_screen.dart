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

    final success = await ref.read(authProvider.notifier).login(
          username,
          pass,
          rememberMe: _rememberMe,
        );
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
      await navigateToHomeAfterAuth(
        context,
        role: role,
        userData: user,
      );
      return;
    }

    await navigateToHomeAfterAuth(
      context,
      role: role,
      userData: user,
    );
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
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
    final pageHeight = constraints.maxHeight < 760
        ? 760.0
        : constraints.maxHeight;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F7),
      body: SingleChildScrollView(
        child: SizedBox(
          height: pageHeight,
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 335,
                child: ClipPath(
                  clipper: _WebHeaderClipper(),
                  child: Container(color: DefensysTokens.maroon),
                ),
              ),
              Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 156),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 360,
                        padding: const EdgeInsets.fromLTRB(30, 42, 30, 34),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 28,
                              offset: const Offset(0, 18),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(child: _sealLogo()),
                            const SizedBox(height: 28),
                            const Text(
                              'DefenSYS',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: DefensysTokens.maroon,
                                letterSpacing: 0.2,
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Capstone & PIT Management System',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF475569),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 32),
                            if (_buildSessionBanner() != null) _buildSessionBanner()!,
                            Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _fieldLabel('Username or Email'),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    controller: _emailCtrl,
                                    decoration: _webInputDecoration(),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'Enter your username or email'
                                            : null,
                                    onFieldSubmitted: (_) => _login(),
                                  ),
                                  const SizedBox(height: 20),
                                  _fieldLabel('Password'),
                                  const SizedBox(height: 10),
                                  TextFormField(
                                    controller: _passCtrl,
                                    obscureText: _obscure,
                                    decoration: _webInputDecoration(
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
                                        onPressed: () => setState(
                                          () => _obscure = !_obscure,
                                        ),
                                      ),
                                    ),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
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
                                    onChanged: (value) => setState(
                                      () => _rememberMe = value ?? false,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Remember me',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      color: Color(0xFF2563EB),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (kIsWeb) ...[
                              const SizedBox(height: 6),
                              const Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  'Stay signed in on this device for up to 7 days. '
                                  'Only enable on personal devices.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 51,
                              child: ElevatedButton(
                                onPressed: authState.isLoading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: DefensysTokens.maroon,
                                  foregroundColor: const Color(0xFFFFD24A),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
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
                                        'LOG IN',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'Department of Information Technology (c) 2026',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                              prefixIcon: const Icon(Icons.badge_outlined, size: 20),
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
                              prefixIcon:
                                  const Icon(Icons.lock_outline, size: 20),
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
                          color: AppColors.textSecondary.withValues(alpha: 0.7),
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

  Widget _fieldLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 13,
        fontWeight: FontWeight.w800,
      ),
    );
  }

  InputDecoration _webInputDecoration({Widget? suffixIcon}) {
    return InputDecoration(
      filled: true,
      fillColor: const Color(0xFFEAF2FF),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: DefensysTokens.maroon, width: 1.4),
      ),
    );
  }

  Widget _sealLogo() {
    return Container(
      width: 74,
      height: 74,
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
      child: ClipOval(
        child: Image.asset(
          'assets/logo.png',
          width: 74,
          height: 74,
          fit: BoxFit.cover,
        ),
      ),
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

class _WebHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height - 46)
      ..cubicTo(
        size.width * 0.20,
        size.height,
        size.width * 0.78,
        size.height,
        size.width,
        size.height - 46,
      )
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
