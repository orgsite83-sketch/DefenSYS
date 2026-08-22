import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/widgets/dialogs/confirm_dialog.dart';

/// Access Control & Dynamic Role Assignment page component matching canonical design.
class AccessControlView extends ConsumerStatefulWidget {
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
  ConsumerState<AccessControlView> createState() => _AccessControlViewState();
}

class _AccessControlViewState extends ConsumerState<AccessControlView> {
  static const Color _ink = DefensysUi.textDark;
  static const Color _line = Color(0xFFE5E7EB);
  static const Color _maroon = DefensysUi.primaryMaroon;
  static const Color _muted = DefensysUi.steelGrey;

  late String _role;
  late bool _isAdmin;
  late bool _isPanelist;
  late bool _isPitLead;
  late bool _isAdviser;
  late bool _isDocumenter;
  String? _pitLeadYear;

  bool _roleAssignmentsLoading = false;
  List<Map<String, dynamic>> _roleAssignments = [];

  static const _histHead = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w800,
    letterSpacing: 1.1,
    color: Color(0xFF9CA3AF),
  );

  static const Map<int, TableColumnWidth> _roleHistoryColumnWidths = {
    0: FlexColumnWidth(2.1),
    1: FlexColumnWidth(2.4),
    2: FlexColumnWidth(1.1),
    3: FlexColumnWidth(1.3),
    4: FlexColumnWidth(1.1),
  };

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _role = u['role']?.toString() ?? 'student';
    _isAdmin = _role == 'admin';
    _isPanelist = u['is_panelist'] == true;
    _isPitLead = u['is_pit_lead'] == true;
    _isAdviser = u['is_adviser'] == true;
    _isDocumenter = u['is_documenter'] == true;

    final rawYear = u['pit_lead_year']?.toString().trim() ?? '';
    if (widget.pitLeadYearOptions.contains(rawYear)) {
      _pitLeadYear = rawYear;
    }

    _loadRoleAssignments();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Future<void> _loadRoleAssignments() async {
    final userId = _asInt(widget.user['id']);
    if (userId == null) return;
    setState(() => _roleAssignmentsLoading = true);
    final rows = await ref
        .read(userManagementProvider.notifier)
        .fetchRoleAssignmentHistory(userId);
    if (!mounted) return;
    setState(() {
      _roleAssignments = rows;
      _roleAssignmentsLoading = false;
    });
  }

  Future<void> _onToggleAdmin(bool value) async {
    final name = (widget.user['name']?.toString().trim().isNotEmpty == true)
        ? widget.user['name']!.toString().trim()
        : '${widget.user['first_name'] ?? ''} ${widget.user['last_name'] ?? ''}'.trim();
    final displayName = name.isNotEmpty ? name : 'this faculty member';

    if (value) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Grant Administrator Privileges?',
        message:
            'You are granting $displayName full administrator access to DefenSYS. This user will have complete access to system settings, defense rubrics, schedules, grades, and user management.',
        confirmLabel: 'Grant Admin Access',
        destructive: false,
        icon: Icons.admin_panel_settings_rounded,
      );
      if (confirmed == true && mounted) {
        setState(() {
          _isAdmin = true;
        });
      }
    } else {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Revoke Administrator Privileges?',
        message:
            'Are you sure you want to remove administrator privileges for $displayName? Their account will return to standard Faculty permissions.',
        confirmLabel: 'Revoke Admin Access',
        destructive: true,
        icon: Icons.shield_outlined,
      );
      if (confirmed == true && mounted) {
        setState(() {
          _isAdmin = false;
        });
      }
    }
  }

  void _onSave() {
    if (_isPitLead && (_pitLeadYear == null || _pitLeadYear!.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'A PIT Lead year level (1st, 2nd, or 3rd Year) is required when assigning a user as PIT Lead.',
          ),
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }
    widget.onSaveRoles({
      'role': _isAdmin ? 'admin' : 'faculty',
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
                foregroundColor: _maroon,
                side: const BorderSide(color: Color(0xFFD1D5DB)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
                        backgroundColor: _maroon,
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
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        email.isNotEmpty ? email : '—',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'ID: ${u['username']?.toString() ?? '—'}',
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: widget.state.isSaving
                              ? null
                              : widget.onEditProfile,
                          icon: const Icon(Icons.person_outline, size: 18),
                          label: const Text('Edit User Profile'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _maroon,
                            side: const BorderSide(
                              color: Color(0xFFD1D5DB),
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 42,
                        child: OutlinedButton.icon(
                          onPressed: widget.state.isSaving
                              ? null
                              : widget.onResetPassword,
                          icon: const Icon(Icons.lock_reset_outlined, size: 18),
                          label: const Text('Reset Password'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(
                              color: Colors.red,
                              width: 1,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.shield_outlined, color: _maroon, size: 22),
                          SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Dynamic Role Assignment',
                                  style: TextStyle(
                                    color: _ink,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Assign operational responsibilities alongside the account\'s primary role permissions. Users can hold multiple roles simultaneously.',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 12.5,
                                    height: 1.45,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      if (isFaculty) ...[
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _line),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: const BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(color: _line),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        'ROLE',
                                        style: _histHead.copyWith(
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'ASSIGNED',
                                      style: _histHead.copyWith(fontSize: 10.5),
                                    ),
                                  ],
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _accessRoleCard(
                                      accent: _maroon,
                                      icon: Icons.admin_panel_settings_rounded,
                                      title: 'System Administrator',
                                      subtitle:
                                          'Grants full administrative privileges over system configuration, user accounts, and defense rubrics.',
                                      value: _isAdmin,
                                      enabled: !widget.state.isSaving,
                                      onChanged: (v) => _onToggleAdmin(v),
                                    ),
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: _line,
                                    ),
                                    _accessRoleCard(
                                      accent: const Color(0xFF9333EA),
                                      icon: Icons.groups_2_outlined,
                                      title: 'Defense Panelist',
                                      subtitle:
                                          'Participates as evaluator on defense panels.',
                                      value: _isPanelist,
                                      enabled: !widget.state.isSaving,
                                      onChanged: (v) =>
                                          setState(() => _isPanelist = v),
                                    ),
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: _line,
                                    ),
                                    _accessRoleCard(
                                      accent: const Color(0xFF2563EB),
                                      icon: Icons.flag_outlined,
                                      title: 'PIT Lead',
                                      subtitle:
                                          'Coordinates PIT activities and dependent roles.',
                                      value: _isPitLead,
                                      enabled: !widget.state.isSaving,
                                      onChanged: (v) {
                                        setState(() {
                                          _isPitLead = v;
                                          if (!_isPitLead) {
                                            _pitLeadYear = null;
                                          }
                                        });
                                      },
                                      below: _isPitLead
                                          ? [
                                              const Text(
                                                'PIT Lead Year',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w600,
                                                  color: _ink,
                                                ),
                                              ),
                                              const SizedBox(height: 6),
                                              DropdownButtonFormField<String?>(
                                                initialValue: _pitLeadYear,
                                                isExpanded: true,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                  color: _ink,
                                                ),
                                                decoration: InputDecoration(
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    borderSide:
                                                        const BorderSide(
                                                          color: Color(
                                                            0xFFD1D5DB,
                                                          ),
                                                        ),
                                                  ),
                                                  filled: true,
                                                  fillColor: Colors.white,
                                                ),
                                                dropdownColor: Colors.white,
                                                items: [
                                                  const DropdownMenuItem<
                                                    String?
                                                  >(
                                                    value: null,
                                                    child: Text(
                                                      '— Select year level —',
                                                    ),
                                                  ),
                                                  ...widget.pitLeadYearOptions
                                                      .map(
                                                        (y) => DropdownMenuItem<
                                                          String?
                                                        >(
                                                          value: y,
                                                          child: Text(y),
                                                        ),
                                                      ),
                                                ],
                                                onChanged: widget.state.isSaving
                                                    ? null
                                                    : (v) => setState(
                                                        () => _pitLeadYear = v,
                                                      ),
                                              ),
                                            ]
                                          : null,
                                    ),
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: _line,
                                    ),
                                    _accessRoleCard(
                                      accent: const Color(0xFF059669),
                                      icon: Icons.school_outlined,
                                      title: 'Project Adviser',
                                      subtitle:
                                          'Capstone advising responsibilities.',
                                      value: _isAdviser,
                                      enabled: !widget.state.isSaving,
                                      onChanged: (v) =>
                                          setState(() => _isAdviser = v),
                                    ),
                                    const Divider(
                                      height: 1,
                                      thickness: 1,
                                      color: _line,
                                    ),
                                    _accessRoleCard(
                                      accent: const Color(0xFF0284C7),
                                      icon: Icons.assignment_outlined,
                                      title: 'Documenter',
                                      subtitle:
                                          'Records minutes of defense for capstone teams.',
                                      value: _isDocumenter,
                                      enabled: !widget.state.isSaving,
                                      onChanged: (v) =>
                                          setState(() => _isDocumenter = v),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text(
                            'Student account role permissions are tied to capstone team memberships.',
                            style: TextStyle(color: _muted, fontSize: 13),
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Align(
                        alignment: Alignment.centerRight,
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            onPressed: widget.state.isSaving ? null : _onSave,
                            icon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 18,
                            ),
                            label: const Text('Save Role Configuration'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _maroon,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
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
          const SizedBox(height: 22),
          _roleAssignmentHistoryCard(),
        ],
      ),
    );
  }

  Widget _accessRoleCard({
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
    List<Widget>? below,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: value,
                activeThumbColor: _maroon,
                onChanged: enabled ? onChanged : null,
              ),
            ],
          ),
          if (below != null) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.only(left: 50),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: below,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _roleAssignmentHistoryCard() {
    return DefensysCard(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Icon(Icons.history_rounded, color: _maroon, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Role Assignment History',
                      style: TextStyle(
                        color: _ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Capability toggles: Panelist, PIT Lead, Project Adviser, etc.',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 12.5,
                        height: 1.4,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_roleAssignmentsLoading)
            const SizedBox(
              height: 72,
              child: Center(
                child: CircularProgressIndicator(color: _maroon),
              ),
            )
          else if (_roleAssignments.isEmpty)
            SizedBox(
              height: 72,
              width: double.infinity,
              child: Center(
                child: Text(
                  'No role assignments recorded yet.',
                  style: TextStyle(
                    color: _muted.withValues(alpha: 0.95),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          else
            _roleHistoryTable(),
        ],
      ),
    );
  }

  Widget _roleHistoryTable() {
    return Table(
      columnWidths: _roleHistoryColumnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: _line)),
          ),
          children: [
            _roleHistoryHeaderCell('ROLE'),
            _roleHistoryHeaderCell('SEMESTER'),
            _roleHistoryHeaderCell('YEAR LEVEL'),
            _roleHistoryHeaderCell('CHANGED'),
            _roleHistoryHeaderCell('ACTION'),
          ],
        ),
        ..._roleAssignments.map(_roleAssignmentHistoryTableRow),
      ],
    );
  }

  Widget _roleHistoryHeaderCell(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Text(text, style: _histHead),
    );
  }

  Widget _roleHistoryCell(
    String text, {
    FontWeight fontWeight = FontWeight.w500,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Text(
        text.isEmpty ? '—' : text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: _ink, fontSize: 12.5, fontWeight: fontWeight),
      ),
    );
  }

  String _roleHistoryLabel(Map<String, dynamic> row) {
    final label = row['role_label']?.toString() ?? '—';
    final detail = row['role_detail']?.toString();
    if (detail == null || detail.isEmpty) {
      return label;
    }
    return '$label ($detail)';
  }

  String _formatAssignmentTimestamp(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw;
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  TableRow _roleAssignmentHistoryTableRow(Map<String, dynamic> row) {
    final isAssigned = row['action']?.toString() == 'assigned';

    return TableRow(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      children: [
        _roleHistoryCell(
          _roleHistoryLabel(row),
          fontWeight: FontWeight.w700,
        ),
        _roleHistoryCell(
          row['semester_name']?.toString() ?? '—',
        ),
        _roleHistoryCell(
          row['year_level']?.toString() ?? '—',
        ),
        _roleHistoryCell(
          _formatAssignmentTimestamp(row['created_at']),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isAssigned
                    ? const Color(0xFFDEF7EC)
                    : const Color(0xFFFDE8E8),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                isAssigned ? 'Assigned' : 'Revoked',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: isAssigned
                      ? const Color(0xFF03543F)
                      : const Color(0xFF9B1C1C),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
