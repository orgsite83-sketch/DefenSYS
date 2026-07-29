import 'package:flutter/material.dart';

/// Modal dialog for creating a single user or editing an existing user's details.
/// Returns a [Map<String, dynamic>] payload if saved, or `null` if cancelled.
class UserCreateEditDialog extends StatefulWidget {
  const UserCreateEditDialog({
    super.key,
    this.user,
    this.pitLeadYearOptions = const ['1st Year', '2nd Year', '3rd Year'],
  });

  final Map<String, dynamic>? user;
  final List<String> pitLeadYearOptions;

  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    Map<String, dynamic>? user,
    List<String> pitLeadYearOptions = const ['1st Year', '2nd Year', '3rd Year'],
  }) {
    return showDialog<Map<String, dynamic>?>(
      context: context,
      builder: (dialogContext) => UserCreateEditDialog(
        user: user,
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
  late final TextEditingController _passwordController;

  late bool _editing;
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
    _passwordController = TextEditingController();

    _role = user?['role']?.toString() ?? 'student';
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
    _passwordController.dispose();
    super.dispose();
  }

  void _onSave() {
    if (_isPitLead && (_pitLeadYear == null || _pitLeadYear!.trim().isEmpty)) {
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
      'role': _role,
      'is_active': _isActive,
      'is_panelist': _isPanelist,
      'is_pit_lead': _isPitLead,
      'pit_lead_year': _isPitLead ? _pitLeadYear : null,
      'is_adviser': _isAdviser,
      'is_documenter': _isDocumenter,
      'is_uploader': widget.user?['is_uploader'] == true,
      if (_passwordController.text.trim().isNotEmpty)
        'password': _passwordController.text.trim(),
    };
    Navigator.of(context).pop(payload);
  }

  @override
  Widget build(BuildContext context) {
    final isFaculty = _role == 'admin' || _role == 'faculty';

    return AlertDialog(
      title: Text(_editing ? 'Edit User' : 'Add Single User'),
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
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(
                  labelText: 'Base Role',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text('Admin'),
                  ),
                  DropdownMenuItem(
                    value: 'faculty',
                    child: Text('Faculty'),
                  ),
                  DropdownMenuItem(
                    value: 'student',
                    child: Text('Student'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _role = value ?? 'student';
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: _editing
                      ? 'New Password (optional)'
                      : 'Password (optional, defaults to ID)',
                ),
              ),
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
              if (isFaculty) ...[
                const Divider(),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Defense Panelist'),
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
                if (_editing) ...[
                  Builder(
                    builder: (context) {
                      final assignments = widget.user?['instructor_assignments'] as List?;
                      if (assignments != null && assignments.isNotEmpty) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Divider(),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: Text(
                                'Active PIT Instructor Workload',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF374151),
                                ),
                              ),
                            ),
                            ...assignments.map((a) {
                              final map = Map<String, dynamic>.from(a as Map);
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 4),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.co_present_rounded,
                                      size: 16,
                                      color: Color(0xFF15803D),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '${map['year_level']} — ${map['section']} (${map['semester']})',
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF4B5563),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _onSave,
          child: Text(_editing ? 'Save Changes' : 'Create User'),
        ),
      ],
    );
  }
}
