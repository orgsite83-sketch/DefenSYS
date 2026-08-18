import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';
import '../../navigation/admin_route_paths.dart';
import '../../theme/defensys_tokens.dart';
import '../../widgets/defensys_logo_mark.dart';
import '../../toasts/feedback_toast.dart';

/// Screen allowing unauthenticated users to confirm password resets
/// using the token and uid from the email link.
class ConfirmPasswordResetScreen extends StatefulWidget {
  final String uid;
  final String token;

  const ConfirmPasswordResetScreen({
    super.key,
    required this.uid,
    required this.token,
  });

  @override
  State<ConfirmPasswordResetScreen> createState() => _ConfirmPasswordResetScreenState();
}

class _ConfirmPasswordResetScreenState extends State<ConfirmPasswordResetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _newPassCtrl = TextEditingController();
  final _confirmPassCtrl = TextEditingController();

  bool _obscureNew = true;
  bool _obscureConfirm = true;
  bool _isSaving = false;
  bool _success = false;

  @override
  void dispose() {
    _newPassCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitReset() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/password-reset/confirm/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'uidb64': widget.uid,
          'token': widget.token,
          'new_password': _newPassCtrl.text,
          'confirm_password': _confirmPassCtrl.text,
        }),
      );

      if (!mounted) return;

      if (response.statusCode == 200) {
        setState(() => _success = true);
        showSuccessToast(context, 'Password reset successful!');
      } else {
        dynamic data;
        try {
          data = jsonDecode(response.body);
        } catch (_) {
          data = null;
        }
        final detail = data is Map ? (data['detail'] ?? data.values.firstOrNull) : null;
        showErrorToast(
          context,
          (detail ?? 'Password reset failed (${response.statusCode}). Please try again later.').toString(),
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Connection error: ${e.toString().split('\n').first}');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Requirement status checks
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
    return Scaffold(
      body: Stack(
        children: [
          // Dark Slate Tech Background Gradient
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF0B0F19), // Deep rich slate
                    Color(0xFF1E293B), // Slate-800
                  ],
                ),
              ),
            ),
          ),
          // Subtle Ambient Glow Overlay
          Positioned(
            top: -120,
            left: -100,
            child: Container(
              width: 380,
              height: 380,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DefensysTokens.maroon.withValues(alpha: 0.18),
              ),
            ),
          ),
          Positioned(
            bottom: -100,
            right: -100,
            child: Container(
              width: 360,
              height: 360,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DefensysTokens.techBlue.withValues(alpha: 0.08),
              ),
            ),
          ),
          // Center Form Card
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 450),
                child: Card(
                  elevation: 12,
                  shadowColor: Colors.black.withValues(alpha: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                    side: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _success ? _buildSuccessWidget() : _buildFormWidget(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormWidget() {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('form'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Logo Header Lockup
          Center(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: DefensysTokens.maroon.withValues(alpha: 0.06),
                shape: BoxShape.circle,
                border: Border.all(
                  color: DefensysTokens.maroon.withValues(alpha: 0.12),
                  width: 1,
                ),
              ),
              child: const DefensysLogoMark(
                size: 38,
                colorMode: DefensysLogoColorMode.brand,
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Reset Password',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.4,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Enter your new password below to regain access to your DefenSYS account.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF64748B),
              height: 1.5,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 28),

          // New Password Field
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
              labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF64748B)),
              suffixIcon: IconButton(
                tooltip: _obscureNew ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DefensysTokens.maroon, width: 2),
              ),
            ),
          ),

          // Dynamic Unified Password Requirements & Strength Card
          if (_newPassCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildRequirementsCard(),
          ],

          const SizedBox(height: 16),
          // Confirm Password Field
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
              labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
              prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20, color: Color(0xFF64748B)),
              suffixIcon: IconButton(
                tooltip: _obscureConfirm ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                  color: const Color(0xFF64748B),
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DefensysTokens.maroon, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 28),

          // Submit Button
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSaving ? null : _submitReset,
              style: ElevatedButton.styleFrom(
                backgroundColor: DefensysTokens.maroon,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSaving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Update Password',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'Poppins',
                        letterSpacing: 0.2,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// Unified Password Requirements and Strength Card
  Widget _buildRequirementsCard() {
    String strengthLabel;
    Color strengthColor;
    double strengthPercent;

    switch (_score) {
      case 3:
        strengthLabel = 'Strong';
        strengthColor = const Color(0xFF10B981); // Emerald
        strengthPercent = 1.0;
        break;
      case 2:
        strengthLabel = 'Fair';
        strengthColor = const Color(0xFFF59E0B); // Amber
        strengthPercent = 0.66;
        break;
      default:
        strengthLabel = 'Weak';
        strengthColor = const Color(0xFFEF4444); // Soft Red
        strengthPercent = 0.33;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with NEUTRAL Slate Icon
          Row(
            children: [
              const Icon(
                Icons.shield_outlined,
                size: 16,
                color: Color(0xFF64748B), // Slate-500 neutral icon (not error red!)
              ),
              const SizedBox(width: 8),
              const Text(
                'Password Security',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1E293B),
                ),
              ),
              const Spacer(),
              Text(
                strengthLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: strengthColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Strength Progress Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: strengthPercent,
              minHeight: 4,
              backgroundColor: const Color(0xFFE2E8F0),
              valueColor: AlwaysStoppedAnimation<Color>(strengthColor),
            ),
          ),
          const SizedBox(height: 10),

          // Guidance Helper Text
          const Text(
            'Allowed: Letters (A-Z, a-z), Numbers (0-9), and Symbols (! @ # \$ % ^ & *)',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 10),

          // Requirements Checklist
          _reqItem('At least 8 characters long', _hasMinLength),
          const SizedBox(height: 6),
          _reqItem('Contains letters & numbers/symbols', _hasComplexChars),
          const SizedBox(height: 6),
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
          size: 15,
          color: isSatisfied ? const Color(0xFF10B981) : const Color(0xFFCBD5E1),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSatisfied ? FontWeight.w600 : FontWeight.w400,
              color: isSatisfied ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessWidget() {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFECFDF5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              size: 48,
              color: Color(0xFF059669),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Password Reset Complete',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: -0.3,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your password has been successfully updated. You can now use your new credentials to sign in.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
            height: 1.5,
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: () => context.go(AppRoutes.login),
            style: ElevatedButton.styleFrom(
              backgroundColor: DefensysTokens.maroon,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text(
              'Back to Sign In',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

