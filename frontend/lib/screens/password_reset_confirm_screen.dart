import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../theme/defensys_tokens.dart';
import '../widgets/feedback_toast.dart';
import '../navigation/admin_route_paths.dart';

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
        showErrorToast(context, (detail ?? 'Password reset failed (${response.statusCode}). Please try again later.').toString());
      }
    } catch (e) {
      if (mounted) showErrorToast(context, 'Connection error: ${e.toString().split('\n').first}');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1E0302), // Deep near-black burgundy
              DefensysTokens.maroon,     // Corporate maroon
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Card(
                elevation: 8,
                shadowColor: Colors.black.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
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
          // Logo and Header
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: DefensysTokens.maroon.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_reset_outlined,
                size: 38,
                color: DefensysTokens.maroon,
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Reset Password',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
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
              height: 1.55,
              fontFamily: 'Poppins',
            ),
          ),
          const SizedBox(height: 28),

          // Fields
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
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureNew ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureNew = !_obscureNew),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: DefensysTokens.maroon, width: 2),
              ),
            ),
          ),
          
          if (_newPassCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Guidelines Box
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: DefensysTokens.maroon),
                      SizedBox(width: 8),
                      Text(
                        'Password Guidelines',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '• Allowed: Letters (A-Z, a-z), Numbers (0-9), and Symbols (! @ # \$ % ^ & *)\n'
                    '• Minimum 8 characters required.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF1F5F9)),
              ),
              child: Column(
                children: [
                  _reqItem('At least 8 characters long', _newPassCtrl.text.length >= 8),
                  const SizedBox(height: 4),
                  _reqItem(
                    'Contains letters & numbers/symbols',
                    RegExp(r'[A-Za-z]').hasMatch(_newPassCtrl.text) &&
                        RegExp(r'[0-9!@#$%^&*(),.?":{}|<>]').hasMatch(_newPassCtrl.text),
                  ),
                  const SizedBox(height: 4),
                  _reqItem(
                    'Matches confirmation password',
                    _confirmPassCtrl.text.isNotEmpty && _newPassCtrl.text == _confirmPassCtrl.text,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 14),
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
              prefixIcon: const Icon(Icons.lock_outline, size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                  size: 20,
                ),
                onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
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
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Update Password',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Poppins',
                      ),
                    ),
            ),
          ),
        ],
      ),
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
              color: Color(0xFFD1FAE5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 48,
              color: Color(0xFF059669),
            ),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Reset Complete',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF0F172A),
            fontFamily: 'Poppins',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Your password has been successfully reset. You can now use your new password to sign in.',
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
                fontWeight: FontWeight.bold,
                fontFamily: 'Poppins',
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _reqItem(String label, bool isSatisfied) {
    return Row(
      children: [
        Icon(
          isSatisfied ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
          size: 14,
          color: isSatisfied ? const Color(0xFF10B981) : Colors.grey.shade400,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSatisfied ? FontWeight.w600 : FontWeight.normal,
              color: isSatisfied ? const Color(0xFF0F172A) : Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}
