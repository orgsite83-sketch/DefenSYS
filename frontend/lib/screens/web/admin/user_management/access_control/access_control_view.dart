import 'package:flutter/material.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/user_management_provider.dart';

/// Access Control & Dynamic Role Assignment page component.
class AccessControlView extends StatefulWidget {
  const AccessControlView({
    super.key,
    required this.user,
    required this.state,
    required this.onBack,
    required this.onSaveRoles,
    required this.onEditProfile,
    required this.onResetPassword,
    this.pitLeadYearOptions = const ['1st Year', '2nd Year', '3rd Year'],
  });

  final Map<String, dynamic> user;
  final UserManagementState state;
  final VoidCallback onBack;
  final ValueChanged<Map<String, dynamic>> onSaveRoles;
  final VoidCallback onEditProfile;
  final VoidCallback onResetPassword;
  final List<String> pitLeadYearOptions;

  @override
  State<AccessControlView> createState() => _AccessControlViewState();
}

class _AccessControlViewState extends State<AccessControlView> {
  late String _role;
  late bool _isPanelist;
  late bool _isPitLead;
  late bool _isAdviser;
  late bool _isDocumenter;
  String? _pitLeadYear;

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _role = u['role']?.toString() ?? 'student';
    _isPanelist = u['is_panelist'] == true;
    _isPitLead = u['is_pit_lead'] == true;
    _isAdviser = u['is_adviser'] == true;
    _isDocumenter = u['is_documenter'] == true;

    final rawYear = u['pit_lead_year']?.toString().trim() ?? '';
    if (widget.pitLeadYearOptions.contains(rawYear)) {
      _pitLeadYear = rawYear;
    }
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
    widget.onSaveRoles({
      'is_panelist': _isPanelist,
      'is_pit_lead': _isPitLead,
      'pit_lead_year': _isPitLead ? _pitLeadYear : null,
      'is_adviser': _isAdviser,
      'is_documenter': _isDocumenter,
    });
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final name = (u['name']?.toString().trim().isNotEmpty == true)
        ? u['name']!.toString().trim()
        : '${u['first_name'] ?? ''} ${u['last_name'] ?? ''}'.trim();
    final email = u['email']?.toString() ?? '';
    final isFaculty = _role == 'admin' || _role == 'faculty';

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.shield_outlined,
            title: 'Access Control & Role Assignment',
            subtitle:
                'Configure primary access roles and operational duties for this user account.',
            actions: OutlinedButton.icon(
              onPressed: widget.state.isSaving ? null : widget.onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back to Users'),
              style: OutlinedButton.styleFrom(
                foregroundColor: DefensysUi.primaryMaroon,
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // User Profile Summary Card
              Expanded(
                flex: 1,
                child: DefensysCard(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CircleAvatar(
                        radius: 30,
                        backgroundColor: DefensysUi.primaryMaroon,
                        child: Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name.isNotEmpty ? name : '—',
                        style: const TextStyle(
                          color: DefensysUi.textDark,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        email.isNotEmpty ? email : '—',
                        style: const TextStyle(
                          color: DefensysUi.steelGrey,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${u['username']?.toString() ?? '—'}',
                        style: const TextStyle(
                          color: DefensysUi.steelGrey,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: widget.state.isSaving ? null : widget.onEditProfile,
                          icon: const Icon(Icons.person_outline, size: 18),
                          label: const Text('Edit User Profile'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: DefensysUi.primaryMaroon,
                            side: const BorderSide(color: Color(0xFFD1D5DB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: widget.state.isSaving ? null : widget.onResetPassword,
                          icon: const Icon(Icons.lock_reset_outlined, size: 18),
                          label: const Text('Reset Password'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 20),
              // Dynamic Role Assignment Controls
              Expanded(
                flex: 3,
                child: DefensysCard(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.shield_outlined, color: DefensysUi.primaryMaroon, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dynamic Role Assignment',
                                  style: TextStyle(
                                    color: DefensysUi.textDark,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Toggle switches to grant or revoke modular permissions.',
                                  style: TextStyle(
                                    color: DefensysUi.steelGrey,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isFaculty) ...[
                        _roleSwitchTile(
                          title: 'Defense Panelist',
                          subtitle: 'Participates as evaluator on defense panels.',
                          value: _isPanelist,
                          onChanged: widget.state.isSaving ? null : (v) => setState(() => _isPanelist = v),
                        ),
                        const Divider(),
                        _roleSwitchTile(
                          title: 'PIT Lead',
                          subtitle: 'Coordinates PIT activities and dependent roles.',
                          value: _isPitLead,
                          onChanged: widget.state.isSaving ? null : (v) {
                            setState(() {
                              _isPitLead = v;
                              if (!_isPitLead) _pitLeadYear = null;
                            });
                          },
                        ),
                        if (_isPitLead) ...[
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String?>(
                            value: _pitLeadYear,
                            decoration: const InputDecoration(
                              labelText: 'PIT Lead Year Level',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(value: null, child: Text('— Select year level —')),
                              ...widget.pitLeadYearOptions.map((y) => DropdownMenuItem(value: y, child: Text(y))),
                            ],
                            onChanged: widget.state.isSaving ? null : (v) => setState(() => _pitLeadYear = v),
                          ),
                          const SizedBox(height: 8),
                        ],
                        const Divider(),
                        _roleSwitchTile(
                          title: 'Project Adviser',
                          subtitle: 'Capstone advising responsibilities.',
                          value: _isAdviser,
                          onChanged: widget.state.isSaving ? null : (v) => setState(() => _isAdviser = v),
                        ),
                        const Divider(),
                        _roleSwitchTile(
                          title: 'Documenter',
                          subtitle: 'Records minutes of defense for capstone teams.',
                          value: _isDocumenter,
                          onChanged: widget.state.isSaving ? null : (v) => setState(() => _isDocumenter = v),
                        ),
                      ] else ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'Student account role permissions are tied to capstone team memberships.',
                            style: TextStyle(color: DefensysUi.steelGrey, fontSize: 13),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: widget.state.isSaving ? null : _onSave,
                          icon: const Icon(Icons.lock_outline_rounded, size: 18),
                          label: const Text('Save Role Configuration'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: DefensysUi.primaryMaroon,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _roleSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(fontSize: 12.5, color: DefensysUi.steelGrey)),
      value: value,
      onChanged: onChanged,
    );
  }
}
