import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/unsaved_changes.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

class AccessControlView extends ConsumerStatefulWidget {
  const AccessControlView({
    super.key,
    required this.user,
    required this.state,
    required this.onBack,
    required this.onSaveRoles,
    required this.onEditProfile,
    required this.onResetPassword,
    this.onOpenPanelistAccess,
    this.pitLeadYearOptions = const ['1st Year', '2nd Year', '3rd Year'],
  });
  final Map<String, dynamic> user;
  final UserManagementState state;
  final VoidCallback onBack, onEditProfile, onResetPassword;
  final VoidCallback? onOpenPanelistAccess;
  final ValueChanged<Map<String, dynamic>> onSaveRoles;
  final List<String> pitLeadYearOptions;
  @override
  ConsumerState<AccessControlView> createState() => _AccessControlViewState();
}

class _AccessControlViewState extends ConsumerState<AccessControlView> {
  late bool _isAdmin, _isPanelist, _isPitLead, _isAdviser, _isDocumenter;
  String? _pitLeadYear, _validationError, _historyError;
  String _tab = 'roles';
  bool _historyLoading = false;
  List<Map<String, dynamic>> _history = [];
  UnsavedChangesNotifier? _dirtyGuard;
  UnsavedChangesSaveDraftNotifier? _draftGuard;
  int _historyGeneration = 0;
  bool get _hasChanges =>
      _isAdmin != (widget.user['role'] == 'admin') ||
      _isPanelist != (widget.user['is_panelist'] == true) ||
      _isPitLead != (widget.user['is_pit_lead'] == true) ||
      _isAdviser != (widget.user['is_adviser'] == true) ||
      _isDocumenter != (widget.user['is_documenter'] == true) ||
      (_isPitLead && _pitLeadYear != widget.user['pit_lead_year']);
  void _reset() {
    _isAdmin = widget.user['role'] == 'admin';
    _isPanelist = widget.user['is_panelist'] == true;
    _isPitLead = widget.user['is_pit_lead'] == true;
    _isAdviser = widget.user['is_adviser'] == true;
    _isDocumenter = widget.user['is_documenter'] == true;
    final year = widget.user['pit_lead_year']?.toString();
    _pitLeadYear = widget.pitLeadYearOptions.contains(year) ? year : null;
    _validationError = null;
  }

  @override
  void initState() {
    super.initState();
    _reset();
    _dirtyGuard = ref.read(unsavedChangesProvider.notifier);
    _draftGuard = ref.read(unsavedChangesSaveDraftProvider.notifier);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dirtyGuard?.setDirty(false);
      _draftGuard?.setCallback(null);
      _loadHistory();
    });
  }

  @override
  void didUpdateWidget(covariant AccessControlView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user['id'] != widget.user['id']) {
      _reset();
      _tab = 'roles';
      _history = [];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _dirtyGuard?.setDirty(false);
          _loadHistory();
        }
      });
    }
  }

  @override
  void dispose() {
    releaseUnsavedChangesAfterFrame(_dirtyGuard, _draftGuard);
    super.dispose();
  }

  void _change(VoidCallback change) {
    setState(() {
      change();
      _validationError = null;
    });
    _dirtyGuard?.setDirty(_hasChanges);
  }

  Future<void> _loadHistory() async {
    final id = int.tryParse(widget.user['id'].toString());
    if (id == null) return;
    final generation = ++_historyGeneration;
    setState(() {
      _historyLoading = true;
      _historyError = null;
    });
    try {
      final history = await ref
          .read(userManagementProvider.notifier)
          .fetchRoleAssignmentHistory(id);
      if (mounted && generation == _historyGeneration) {
        setState(() => _history = history);
      }
    } catch (_) {
      if (mounted && generation == _historyGeneration) {
        setState(
          () => _historyError = 'Could not load role history. Try again.',
        );
      }
    } finally {
      if (mounted && generation == _historyGeneration) {
        setState(() => _historyLoading = false);
      }
    }
  }

  Future<void> _toggleAdmin(bool value) async {
    final confirmed = await showConfirmDialog(
      context,
      title: value
          ? 'Grant Administrator Privileges?'
          : 'Revoke Administrator Privileges?',
      message: value
          ? 'This grants full access to system settings, schedules, grades and user management.'
          : 'This returns the account to Faculty access. Operational duties remain assigned.',
      confirmLabel: value ? 'Grant Admin Access' : 'Revoke Admin Access',
      destructive: !value,
      icon: Icons.admin_panel_settings_outlined,
    );
    if (confirmed && mounted) _change(() => _isAdmin = value);
  }

  Future<void> _leave(VoidCallback action) => guardUnsavedExit(
    context,
    isDirty: _hasChanges,
    onExit: () {
      _dirtyGuard?.setDirty(false);
      action();
    },
  );
  void _save() {
    if (_isPitLead && (_pitLeadYear == null || _pitLeadYear!.isEmpty)) {
      setState(
        () => _validationError = 'Choose a year level for the PIT Lead.',
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

  Widget _role({
    required String id,
    required String title,
    required String description,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? extra,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              size: 19,
              color: DefensysTokens.textSecondaryOf(context),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: DefensysTokens.textPrimaryOf(context),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: DefensysTokens.textSecondaryOf(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            Semantics(
              label: title,
              toggled: value,
              child: ShadSwitch(
                key: ValueKey('role-$id'),
                value: value,
                enabled: !widget.state.isSaving,
                onChanged: onChanged,
                checkedTrackColor: DefensysTokens.maroonOf(context),
              ),
            ),
          ],
        ),
        if (extra != null)
          Padding(
            padding: const EdgeInsets.only(top: 12, left: 31),
            child: extra,
          ),
      ],
    ),
  );
  Widget _sectionLabel(String label, String description) => Padding(
    padding: const EdgeInsets.only(top: 8, bottom: 4),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: DefensysTokens.textPrimaryOf(context),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          description,
          style: TextStyle(
            fontSize: 12,
            height: 1.5,
            color: DefensysTokens.textSecondaryOf(context),
          ),
        ),
      ],
    ),
  );
  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name =
        (user['name'] ??
                '${user['first_name'] ?? ''} ${user['last_name'] ?? ''}')
            .toString()
            .trim();
    final staff = user['role'] == 'admin' || user['role'] == 'faculty';
    final secondary = DefensysTokens.textSecondaryOf(context);
    final busy = widget.state.isSaving;
    final badges = <String>[
      if (user['role'] == 'admin') 'Administrator',
      if (user['is_panelist'] == true) 'Panelist',
      if (user['is_pit_lead'] == true)
        'PIT Lead · ${user['pit_lead_year'] ?? ''}',
      if (user['is_adviser'] == true) 'Adviser',
      if (user['is_documenter'] == true) 'Documenter',
    ];
    return DefensysShadcnScope(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(
          MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) => Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: constraints.maxWidth < 600
                            ? constraints.maxWidth
                            : constraints.maxWidth - 180,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Roles & access',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w700,
                                color: DefensysTokens.maroonTextOf(context),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Manage access and operational responsibilities.',
                              style: TextStyle(fontSize: 13, color: secondary),
                            ),
                          ],
                        ),
                      ),
                      ShadButton.ghost(
                        enabled: !busy,
                        onPressed: busy ? null : () => _leave(widget.onBack),
                        leading: const Icon(LucideIcons.arrowLeft, size: 15),
                        child: const Text('Back to Users'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                ShadCard(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final identity = Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: DefensysTokens.maroonOf(context),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              LucideIcons.userRound,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name.isEmpty
                                      ? user['username'].toString()
                                      : name,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: DefensysTokens.textPrimaryOf(
                                      context,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${user['email'] ?? ''} · ID ${user['username'] ?? user['id']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: secondary,
                                  ),
                                ),
                                if (badges.isNotEmpty) ...[
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final badge in badges)
                                        ShadBadge.outline(child: Text(badge)),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      );
                      final actions = Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          ShadButton.ghost(
                            enabled: !busy,
                            onPressed: busy ? null : widget.onEditProfile,
                            leading: const Icon(LucideIcons.pencil, size: 14),
                            child: const Text('Edit User Profile'),
                          ),
                          ShadButton.ghost(
                            enabled: !busy,
                            onPressed: busy ? null : widget.onResetPassword,
                            foregroundColor: DefensysTokens.danger,
                            child: const Text('Reset Password'),
                          ),
                        ],
                      );
                      return constraints.maxWidth < 720
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                identity,
                                const SizedBox(height: 14),
                                actions,
                              ],
                            )
                          : Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: identity),
                                const SizedBox(width: 16),
                                actions,
                              ],
                            );
                    },
                  ),
                ),
                const SizedBox(height: 20),
                ShadTabs<String>(
                  value: _tab,
                  onChanged: (value) => setState(() => _tab = value),
                  tabs: const [
                    ShadTab(value: 'roles', child: Text('Assigned roles')),
                    ShadTab(value: 'history', child: Text('Role history')),
                  ],
                ),
                const SizedBox(height: 16),
                if (_tab == 'history')
                  _historyView()
                else
                  ShadCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (staff) ...[
                          _sectionLabel(
                            'Account access',
                            'The primary role controls access to administration.',
                          ),
                          _role(
                            id: 'admin',
                            title: 'System Administrator',
                            description:
                                'Full access to configuration, users, schedules and grades.',
                            icon: LucideIcons.shieldCheck,
                            value: _isAdmin,
                            onChanged: _toggleAdmin,
                          ),
                          Divider(
                            color: DefensysTokens.borderOf(context),
                            height: 24,
                          ),
                          _sectionLabel(
                            'Operational duties',
                            'A faculty member can hold several duties, each with its own workspace.',
                          ),
                          _role(
                            id: 'panelist',
                            title: 'Defense Panelist',
                            description:
                                'Eligible for the reusable panelist pool. Defense assignments are made in scheduling.',
                            icon: LucideIcons.usersRound,
                            value: _isPanelist,
                            onChanged: (v) => _change(() => _isPanelist = v),
                            extra: widget.onOpenPanelistAccess == null
                                ? null
                                : Align(
                                    alignment: Alignment.centerLeft,
                                    child: ShadButton.ghost(
                                      size: ShadButtonSize.sm,
                                      enabled: !busy,
                                      onPressed: busy
                                          ? null
                                          : () => _leave(
                                              widget.onOpenPanelistAccess!,
                                            ),
                                      trailing: const Icon(
                                        LucideIcons.arrowUpRight,
                                        size: 13,
                                      ),
                                      child: const Flexible(
                                        child: Text(
                                          'View panelist requests & history',
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                          Divider(
                            color: DefensysTokens.borderOf(context),
                            height: 1,
                          ),
                          _role(
                            id: 'pit-lead',
                            title: 'PIT Lead',
                            description:
                                'Coordinates PIT activities and nominations for the assigned year.',
                            icon: LucideIcons.flag,
                            value: _isPitLead,
                            onChanged: (v) => _change(() {
                              _isPitLead = v;
                              if (!v) _pitLeadYear = null;
                            }),
                            extra: !_isPitLead
                                ? null
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'PIT Lead Year',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: secondary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      ShadSelect<String>(
                                        key: ValueKey('pit-year-$_pitLeadYear'),
                                        initialValue: _pitLeadYear,
                                        placeholder: const Text(
                                          'Choose a year level',
                                        ),
                                        enabled: !busy,
                                        minWidth: 180,
                                        options: [
                                          for (final year
                                              in widget.pitLeadYearOptions)
                                            ShadOption(
                                              value: year,
                                              child: Text(year),
                                            ),
                                        ],
                                        selectedOptionBuilder: (_, year) =>
                                            Text(year),
                                        onChanged: (year) =>
                                            _change(() => _pitLeadYear = year),
                                      ),
                                    ],
                                  ),
                          ),
                          Divider(
                            color: DefensysTokens.borderOf(context),
                            height: 1,
                          ),
                          _role(
                            id: 'adviser',
                            title: 'Project Adviser',
                            description:
                                'Advises assigned capstone teams and reviews their requirements.',
                            icon: LucideIcons.graduationCap,
                            value: _isAdviser,
                            onChanged: (v) => _change(() => _isAdviser = v),
                          ),
                          Divider(
                            color: DefensysTokens.borderOf(context),
                            height: 1,
                          ),
                          _role(
                            id: 'documenter',
                            title: 'Documenter',
                            description:
                                'Records and signs minutes for assigned capstone defenses.',
                            icon: LucideIcons.filePenLine,
                            value: _isDocumenter,
                            onChanged: (v) => _change(() => _isDocumenter = v),
                          ),
                        ] else
                          Text(
                            'Student access follows academic records and team memberships.',
                            style: TextStyle(color: secondary),
                          ),
                        if (_validationError != null ||
                            widget.state.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _validationError ?? widget.state.error!,
                              style: TextStyle(color: DefensysTokens.danger),
                            ),
                          ),
                        if (staff) ...[
                          Divider(
                            color: DefensysTokens.borderOf(context),
                            height: 32,
                          ),
                          Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 16,
                            runSpacing: 12,
                            children: [
                              Text(
                                _hasChanges
                                    ? 'Unsaved role changes'
                                    : 'All role changes saved',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: secondary,
                                ),
                              ),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (_hasChanges)
                                    ShadButton.outline(
                                      enabled: !busy,
                                      onPressed: busy
                                          ? null
                                          : () => _change(_reset),
                                      child: const Text('Discard changes'),
                                    ),
                                  ShadButton(
                                    enabled: _hasChanges && !busy,
                                    onPressed: _hasChanges && !busy
                                        ? _save
                                        : null,
                                    backgroundColor: DefensysTokens.maroonOf(
                                      context,
                                    ),
                                    leading: const Icon(
                                      LucideIcons.save,
                                      size: 15,
                                    ),
                                    child: Text(
                                      busy
                                          ? 'Saving…'
                                          : 'Save Role Configuration',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
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

  Widget _historyView() => ShadCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Role assignment history',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ),
            ShadButton.ghost(
              size: ShadButtonSize.sm,
              enabled: !_historyLoading,
              onPressed: _historyLoading ? null : _loadHistory,
              leading: const Icon(LucideIcons.refreshCw, size: 14),
              child: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_historyLoading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_historyError != null)
          Text(_historyError!, style: TextStyle(color: DefensysTokens.danger))
        else if (_history.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'No role assignments recorded yet.',
              style: TextStyle(color: DefensysTokens.textSecondaryOf(context)),
            ),
          )
        else
          for (final row in _history)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    row['action'] == 'assigned'
                        ? LucideIcons.circleCheck
                        : LucideIcons.circleMinus,
                    size: 17,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['role_label'] ?? row['role_key']}${(row['role_detail'] ?? '').toString().isEmpty ? '' : ' · ${row['role_detail']}'}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${row['changed_by_name'] ?? 'System'} · ${_date(row['changed_at'])}',
                          style: TextStyle(
                            fontSize: 12,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                        if (row['semester'] != null)
                          Text(
                            row['semester'].toString(),
                            style: TextStyle(
                              fontSize: 12,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ShadBadge.outline(
                    child: Text(
                      row['action'] == 'assigned' ? 'Assigned' : 'Revoked',
                    ),
                  ),
                ],
              ),
            ),
      ],
    ),
  );
  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null
        ? 'Date unavailable'
        : DateFormat('MMM d, y · h:mm a').format(date);
  }
}
