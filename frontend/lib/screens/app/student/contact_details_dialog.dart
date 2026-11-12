import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../config/api_config.dart';
import '../../../services/auth_provider.dart';
import '../../../services/authenticated_client.dart';
import '../../../theme/defensys_tokens.dart';
import '../../../widgets/shadcn/defensys_shadcn_scope.dart';

Future<bool?> showContactDetailsDialog(
  BuildContext context,
  Map<String, dynamic> user,
) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ContactDetailsDialog(user: user),
);

class _ContactDetailsDialog extends ConsumerStatefulWidget {
  const _ContactDetailsDialog({required this.user});
  final Map<String, dynamic> user;

  @override
  ConsumerState<_ContactDetailsDialog> createState() =>
      _ContactDetailsDialogState();
}

class _ContactDetailsDialogState extends ConsumerState<_ContactDetailsDialog> {
  late final _email = TextEditingController(
    text: widget.user['email']?.toString().trim() ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.user['phone_number']?.toString().trim() ?? '',
  );
  final _password = TextEditingController();
  var _saving = false;
  Map<String, String> _errors = {};

  @override
  void dispose() {
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_password.text.isEmpty) {
      setState(
        () => _errors = {'current_password': 'Enter your current password.'},
      );
      return;
    }
    setState(() {
      _saving = true;
      _errors = {};
    });
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .patch(
            Uri.parse('${ApiConfig.baseUrl}/me/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _email.text.trim(),
              'phone_number': _phone.text.trim(),
              'current_password': _password.text,
            }),
          );
      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        ref
            .read(authProvider.notifier)
            .updateCurrentUser(Map<String, dynamic>.from(data as Map));
        Navigator.pop(context, true);
        return;
      }
      setState(() {
        _errors = data is Map
            ? data.map<String, String>(
                (key, value) => MapEntry(
                  key.toString(),
                  value is List ? value.join(' ') : value.toString(),
                ),
              )
            : {'detail': 'Unable to save contact details. Please try again.'};
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => _errors = {
            'detail': 'Unable to save contact details. Please try again.',
          },
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _field(
    String label,
    String field,
    TextEditingController controller, {
    TextInputType? keyboardType,
    bool password = false,
    bool autofocus = false,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label),
      const SizedBox(height: 6),
      ShadInput(
        key: ValueKey('contact_$field'),
        controller: controller,
        enabled: !_saving,
        autofocus: autofocus,
        keyboardType: keyboardType,
        obscureText: password,
        autocorrect: false,
        enableSuggestions: !password,
        onSubmitted: password ? (_) => _save() : null,
      ),
      if (_errors[field] case final error?) ...[
        const SizedBox(height: 4),
        Text(
          error,
          style: TextStyle(
            fontFamily: DefensysTokens.fontFamilyInter,
            color: Theme.of(context).colorScheme.error,
            fontSize: 12,
          ),
        ),
      ],
    ],
  );

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: DefensysShadcnScope(
      maroonActions: true,
      child: ShadDialog(
        title: const Text('Edit contact details'),
        closeIcon: _saving ? const SizedBox.shrink() : null,
        constraints: const BoxConstraints(maxWidth: 440),
        actions: [
          ShadButton.outline(
            onPressed: _saving ? null : () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ShadButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _field(
                'Email address (optional)',
                'email',
                _email,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              _field(
                'Phone number (optional)',
                'phone_number',
                _phone,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              _field(
                'Current password',
                'current_password',
                _password,
                password: true,
              ),
              if (_errors['detail'] ?? _errors['non_field_errors']
                  case final error?) ...[
                const SizedBox(height: 12),
                Text(
                  error,
                  style: TextStyle(
                    fontFamily: DefensysTokens.fontFamilyInter,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
