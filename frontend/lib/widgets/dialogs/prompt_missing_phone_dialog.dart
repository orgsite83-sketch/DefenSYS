import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/api_config.dart';
import '../../services/auth/auth_provider.dart';
import '../../services/network/api_http.dart';
import '../../theme/defensys_tokens.dart';
import '../../toasts/feedback_toast.dart';

class PromptMissingPhoneDialog extends ConsumerStatefulWidget {
  const PromptMissingPhoneDialog({super.key});

  static final Set<dynamic> _dismissedUserIds = {};

  static void maybeShow(BuildContext context, WidgetRef ref) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final auth = ref.read(authProvider);
      final user = auth.user;
      if (user == null) return;

      final phone = (user['phone_number'] ?? '').toString().trim();
      if (phone.isNotEmpty) return;

      final userId = user['id'] ?? user['username'];
      if (_dismissedUserIds.contains(userId)) return;

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => const PromptMissingPhoneDialog(),
      );
    });
  }

  @override
  ConsumerState<PromptMissingPhoneDialog> createState() =>
      _PromptMissingPhoneDialogState();
}

class _PromptMissingPhoneDialogState
    extends ConsumerState<PromptMissingPhoneDialog> {
  static const _maroon = DefensysTokens.maroon;
  static const _ink = DefensysTokens.textDark;
  static const _muted = DefensysTokens.steelGrey;
  static const _line = Color(0xFFE5E7EB);

  final _phoneCtrl = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  String _cleanPhoneNumber(String input) {
    return input.replaceAll(RegExp(r'[\s\-()]'), '');
  }

  Future<void> _handleSave() async {
    final rawPhone = _phoneCtrl.text.trim();
    final clean = _cleanPhoneNumber(rawPhone);

    if (clean.isEmpty) {
      setState(() => _error = 'Please enter your mobile phone number.');
      return;
    }

    final digitsOnly = clean.replaceFirst('+', '');
    if (digitsOnly.length < 10 || digitsOnly.length > 13) {
      setState(() => _error = 'Please enter a valid mobile number (e.g. 09171234567).');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final auth = ref.read(authProvider);
      final token = auth.token;
      if (token == null) {
        setState(() {
          _isLoading = false;
          _error = 'You must be logged in to update your profile.';
        });
        return;
      }

      final response = await apiHttpClient.patch(
        Uri.parse('${ApiConfig.baseUrl}/me/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'phone_number': clean}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is Map<String, dynamic>) {
          ref.read(authProvider.notifier).updateCurrentUser(data);
        }
        if (mounted) {
          showSuccessToast(context, 'Mobile number saved successfully.');
          Navigator.of(context).pop();
        }
      } else {
        String msg = 'Failed to save mobile number. Please try again.';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody is Map && errBody['detail'] != null) {
            msg = errBody['detail'].toString();
          } else if (errBody is Map && errBody['phone_number'] != null) {
            final p = errBody['phone_number'];
            msg = p is List ? p.first.toString() : p.toString();
          }
        } catch (_) {}

        if (mounted) {
          setState(() {
            _isLoading = false;
            _error = msg;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Connection error: $e';
        });
      }
    }
  }

  void _handleSkip() {
    final user = ref.read(authProvider).user;
    if (user != null) {
      final userId = user['id'] ?? user['username'];
      PromptMissingPhoneDialog._dismissedUserIds.add(userId);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with Phone Icon
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.phone_iphone_rounded,
                        color: Color(0xFF2563EB),
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Add Recovery Mobile Number',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Enable instant SMS password recovery',
                          style: TextStyle(
                            fontSize: 12,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Description Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _line),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(
                      Icons.shield_outlined,
                      size: 18,
                      color: Color(0xFF0284C7),
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your mobile number is used to receive 6-digit OTP verification codes via SMS when resetting your password or recovering your account.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF334155),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),

              // Phone Number Input Field
              const Text(
                'Mobile Phone Number',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+\s\-]')),
                ],
                onSubmitted: (_) => _handleSave(),
                decoration: InputDecoration(
                  hintText: 'e.g. 0917 123 4567 or +639171234567',
                  hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  prefixIcon: const Icon(
                    Icons.phone_outlined,
                    size: 18,
                    color: Color(0xFF64748B),
                  ),
                  filled: true,
                  fillColor: const Color(0xFFFAFAFA),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: _maroon, width: 1.5),
                  ),
                ),
              ),

              // Error Message
              if (_error != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFDC2626), size: 15),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 24),

              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : _handleSkip,
                    style: TextButton.styleFrom(
                      foregroundColor: _muted,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                    ),
                    child: const Text('Skip for Now'),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: _isLoading ? null : _handleSave,
                    icon: _isLoading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 16),
                    label: Text(_isLoading ? 'Saving...' : 'Save Mobile Number'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _maroon,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
