import 'package:flutter/material.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/widgets/dialogs/confirm_dialog.dart';

/// Modal dialog for creating a single user or editing an existing user's details.
/// Returns a [Map<String, dynamic>] payload if saved, or `null` if cancelled.
class UserCreateEditDialog extends StatefulWidget {
  const UserCreateEditDialog({
    super.key,
    this.user,
    this.defaultRole = 'faculty',
    this.pitLeadYearOptions = const ['1st Year', '2nd Year', '3rd Year'],
  });

  final Map<String, dynamic>? user;
  final String defaultRole;
  final List<String> pitLeadYearOptions;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    Map<String, dynamic>? user,
    String defaultRole = 'faculty',
    List<String> pitLeadYearOptions = const ['1st Year', '2nd Year', '3rd Year'],
  }) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) => UserCreateEditDialog(
        user: user,
        defaultRole: defaultRole,
        pitLeadYearOptions: pitLeadYearOptions,
      ),
    );
  }

  @override
  State<UserCreateEditDialog> createState() => _UserCreateEditDialogState();
}

class _UserCreateEditDialogState extends State<UserCreateEditDialog> {
  late final TextEditingController _usernameController;
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _passwordController;

  late bool _editing;
  late String _initialRole;
  late String _role;
  late bool _isPanelist;
  late bool _isPitLead;
  late bool _isAdviser;
  late bool _isDocumenter;
  late bool _isActive;
  String? _pitLeadYear;

  @override
  void initState() {
    super.initState();
    final user = widget.user;
    _editing = user != null;
    _usernameController = TextEditingController(
      text: user?['username']?.toString() ?? '',
    );
    _firstNameController = TextEditingController(
      text: user?['first_name']?.toString() ?? '',
    );
    _lastNameController = TextEditingController(
      text: user?['last_name']?.toString() ?? '',
    );
    _emailController = TextEditingController(
      text: user?['email']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: user?['phone_number']?.toString() ??
          user?['contact']?.toString() ??
          '',
    );
    _passwordController = TextEditingController();

    _initialRole = user?['role']?.toString() ?? widget.defaultRole;
    // Map initial admin role to faculty in dropdown (admin privilege is managed in Access Control)
    _role = (_initialRole == 'admin') ? 'faculty' : _initialRole;
    if (_role != 'faculty' && _role != 'student') {
      _role = widget.defaultRole;
    }

    _isPanelist = user?['is_panelist'] == true;
    _isPitLead = user?['is_pit_lead'] == true;
    _isAdviser = user?['is_adviser'] == true;
    _isDocumenter = user?['is_documenter'] == true;
    _isActive = user?['is_active'] != false;

    final rawYear = user?['pit_lead_year']?.toString().trim() ?? '';
    if (widget.pitLeadYearOptions.contains(rawYear)) {
      _pitLeadYear = rawYear;
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_editing && _isPitLead && (_pitLeadYear == null || _pitLeadYear!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('A PIT Lead year level (1st, 2nd, or 3rd Year) is required when assigning a user as PIT Lead.'),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    final payload = <String, dynamic>{
      'username': _usernameController.text.trim(),
      'first_name': _firstNameController.text.trim(),
      'last_name': _lastNameController.text.trim(),
      'email': _emailController.text.trim(),
      'phone_number': _phoneController.text.trim(),
      'role': _initialRole,
      'is_active': _isActive,
      'is_panelist': _isPanelist,
      'is_pit_lead': _isPitLead,
      'pit_lead_year': _isPitLead ? _pitLeadYear : null,
      'is_adviser': _isAdviser,
      'is_documenter': _isDocumenter,
      'is_uploader': widget.user?['is_uploader'] == true,
      if (!_editing && _passwordController.text.trim().isNotEmpty)
        'password': _passwordController.text.trim(),
    };
    if (mounted) {
      Navigator.of(context).pop(payload);
    }
  }

  Future<void> _onResetPassword() async {
    final user = widget.user;
    if (user == null) return;

    final username = _usernameController.text.trim();
    final name = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
    final displayName = name.isNotEmpty ? name : username;

    final confirmed = await showConfirmDialog(
      context,
      title: 'Reset Password?',
      message: 'Reset password for $displayName to their default ID number ($username)?',
      confirmLabel: 'Reset Password',
    );

    if (confirmed == true && mounted) {
      Navigator.of(context).pop({
        '_action': 'reset_password',
        'id': user['id'],
        'username': username,
      });
    }
  }

  Future<void> _onDelete() async {
    final user = widget.user;
    if (user == null) return;

    final username = _usernameController.text.trim();
    final name = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
    final displayName = name.isNotEmpty ? name : username;

    final confirmed = await showDestructiveTypeConfirmDialog(
      context,
      title: 'Delete User Account?',
      message:
          'You are about to permanently delete the account for $displayName (Username: $username). All role assignments, permissions, and operational duties will be permanently deleted.',
      matchTarget: username,
      confirmLabel: 'Permanently Delete Account',
      warningBanner:
          'This action is irreversible. The account credentials and assigned roles will be completely removed.',
    );

    if (confirmed == true && mounted) {
      Navigator.of(context).pop({'_action': 'delete', 'id': user['id']});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isFaculty = _role == 'faculty';

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(_editing ? 'Edit User' : 'Add Single Faculty',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF1F2937))),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _usernameController,
                enabled: !_editing,
                decoration: const InputDecoration(
                  labelText: 'ID Number / Username',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(
                        labelText: 'First Name',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(
                        labelText: 'Last Name',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Mobile / Phone Number',
                  hintText: 'e.g. 0917 123 4567',
                ),
              ),
              if (_editing) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Password & Credentials',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Reset password to default ID number (${_usernameController.text.trim()}).',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      OutlinedButton.icon(
                        onPressed: _onResetPassword,
                        icon: const Icon(Icons.lock_reset_rounded, size: 14),
                        label: const Text('Reset Password'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB45309),
                          side: const BorderSide(color: Color(0xFFFDE68A)),
                          backgroundColor: const Color(0xFFFFFBEB),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (!_editing) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password (optional, defaults to ID)',
                  ),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Active account'),
                value: _isActive,
                onChanged: (value) {
                  setState(() {
                    _isActive = value;
                  });
                },
              ),
              if (!_editing && isFaculty) ...[
                const Divider(),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Defense Panelist'),
                  subtitle: const Text(
                    'Eligible pool for automatic scheduler generation. (In timetable bulk import, any faculty member can be assigned).',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                  ),
                  value: _isPanelist,
                  onChanged: (value) {
                    setState(() {
                      _isPanelist = value ?? false;
                    });
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('PIT Lead'),
                  value: _isPitLead,
                  onChanged: (value) {
                    setState(() {
                      _isPitLead = value ?? false;
                      if (!_isPitLead) {
                        _pitLeadYear = null;
                      }
                    });
                  },
                ),
                if (_isPitLead) ...[
                  DropdownButtonFormField<String?>(
                    key: ValueKey('dlg-pit-$_pitLeadYear'),
                    initialValue: _pitLeadYear,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'PIT Lead Year',
                    ),
                    dropdownColor: Colors.white,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('— Select year level —'),
                      ),
                      ...widget.pitLeadYearOptions.map(
                        (y) => DropdownMenuItem<String?>(
                          value: y,
                          child: Text(y),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _pitLeadYear = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Project Adviser'),
                  value: _isAdviser,
                  onChanged: (value) {
                    setState(() {
                      _isAdviser = value ?? false;
                    });
                  },
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Documenter'),
                  subtitle: const Text(
                    'Records minutes of defense for capstone teams.',
                  ),
                  value: _isDocumenter,
                  onChanged: (value) {
                    setState(() {
                      _isDocumenter = value ?? false;
                    });
                  },
                ),
              ],
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
      actions: [
        SizedBox(
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (_editing)
                IconButton(
                  onPressed: _onDelete,
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  tooltip: 'Delete Account',
                  style: IconButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    backgroundColor: const Color(0xFFFEF2F2),
                    side: const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(8),
                  ),
                )
              else
                const SizedBox.shrink(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(null),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6B7280),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text('Cancel',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    onPressed: _onSave,
                    icon: Icon(_editing ? Icons.save_rounded : Icons.person_add_rounded, size: 16),
                    style: _editing
                        ? DefensysTokens.saveButtonStyle(
                            isPill: false,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 11),
                          )
                        : FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF7A1C1C),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                    label: Text(_editing ? 'Save Changes' : 'Create Faculty',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
