import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'package:defensys/services/user_management_provider.dart';
import 'package:defensys/services/unsaved_changes_provider.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/utils/unsaved_changes.dart';
import 'package:defensys/widgets/confirm_dialog.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';

/// Full-screen shadcn-styled Role & Access Control view for DefenSYS User Management.
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

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final name = (user['name'] ??
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

    final isNarrow = MediaQuery.sizeOf(context).width < 768;

    return DefensysShadcnScope(
      child: SingleChildScrollView(
        padding: isNarrow
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
            : DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top Header
            _topHeader(busy, secondary),
            const SizedBox(height: 20),

            // User Identity Banner / Card
            _userHeaderCard(user, name, badges, secondary, busy),
            const SizedBox(height: 20),

            // Tab Switcher (Assigned roles vs Role history)
            ShadTabs<String>(
              value: _tab,
              onChanged: (value) => setState(() => _tab = value),
              tabs: const [
                ShadTab(value: 'roles', child: Text('Assigned roles')),
                ShadTab(value: 'history', child: Text('Role history')),
              ],
            ),
            const SizedBox(height: 18),

            // Active Tab Content
            if (_tab == 'history')
              _historyView()
            else if (!staff)
              _studentNotice(secondary)
            else
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1024;
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: constraints.maxWidth >= 1320 ? 420 : 360,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _adminCard(),
                              const SizedBox(height: 16),
                              _guidelinesCard(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: _operationalDutiesCard(secondary, busy),
                        ),
                      ],
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _adminCard(),
                      const SizedBox(height: 16),
                      _operationalDutiesCard(secondary, busy),
                      const SizedBox(height: 16),
                      _guidelinesCard(),
                    ],
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _topHeader(bool busy, Color secondary) {
    return LayoutBuilder(
      builder: (context, constraints) => Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
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
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.shieldCheck,
                      color: DefensysTokens.maroonTextOf(context),
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Roles & access',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: DefensysTokens.maroonTextOf(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage access and operational responsibilities.',
                  style: TextStyle(fontSize: 13, color: secondary),
                ),
              ],
            ),
          ),
          ShadButton.outline(
            enabled: !busy,
            onPressed: busy ? null : () => _leave(widget.onBack),
            leading: const Icon(LucideIcons.arrowLeft, size: 14),
            child: const Text('Back to Users'),
          ),
        ],
      ),
    );
  }

  Widget _userHeaderCard(
    Map<String, dynamic> user,
    String name,
    List<String> badges,
    Color secondary,
    bool busy,
  ) {
    final isDark = DefensysTokens.isDark(context);
    final maroon = DefensysTokens.maroonOf(context);
    final email = user['email']?.toString() ?? '';
    final idNum = (user['username'] ?? user['id'] ?? '').toString();

    return ShadCard(
      padding: const EdgeInsets.all(20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: maroon,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isDark
                      ? null
                      : [
                          BoxShadow(
                            color: maroon.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                child: const Icon(
                  LucideIcons.userRound,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          name.isEmpty ? idNum : name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        ShadBadge.secondary(
                          child: Text(
                            user['role'] == 'admin'
                                ? 'Administrator'
                                : 'Faculty Member',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 14,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (email.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.mail,
                                  size: 13, color: secondary),
                              const SizedBox(width: 5),
                              Text(email,
                                  style: TextStyle(
                                      fontSize: 12, color: secondary)),
                            ],
                          ),
                        if (idNum.isNotEmpty)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(LucideIcons.idCard,
                                  size: 13, color: secondary),
                              const SizedBox(width: 5),
                              Text('ID: $idNum',
                                  style: TextStyle(
                                      fontSize: 12, color: secondary)),
                            ],
                          ),
                      ],
                    ),
                    if (badges.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final badge in badges)
                            ShadBadge.outline(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    badge.contains('PIT Lead')
                                        ? LucideIcons.flag
                                        : badge == 'Administrator'
                                            ? LucideIcons.shieldCheck
                                            : badge == 'Panelist'
                                                ? LucideIcons.usersRound
                                                : badge == 'Adviser'
                                                    ? LucideIcons.graduationCap
                                                    : LucideIcons.filePenLine,
                                    size: 12,
                                    color: maroon,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(badge),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );

          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ShadButton.outline(
                enabled: !busy,
                onPressed: busy ? null : widget.onEditProfile,
                leading: const Icon(LucideIcons.pencil, size: 14),
                child: const Text('Edit User Profile'),
              ),
              ShadButton.outline(
                enabled: !busy,
                onPressed: busy ? null : widget.onResetPassword,
                foregroundColor: DefensysTokens.danger,
                leading: const Icon(LucideIcons.keyRound, size: 14),
                child: const Text('Reset Password'),
              ),
            ],
          );

          return constraints.maxWidth < 720
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    identity,
                    const SizedBox(height: 16),
                    actions,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: identity),
                    const SizedBox(width: 20),
                    actions,
                  ],
                );
        },
      ),
    );
  }

  Widget _adminCard() {
    final isDark = DefensysTokens.isDark(context);
    final maroon = DefensysTokens.maroonOf(context);
    final secondary = DefensysTokens.textSecondaryOf(context);

    return ShadCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF3B1517)
                      : const Color(0xFFFDF2F2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  LucideIcons.shieldCheck,
                  color: maroon,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account access',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: DefensysTokens.textPrimaryOf(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'The primary role controls access to administration.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _isAdmin
                  ? (isDark ? const Color(0xFF2A1619) : const Color(0xFFFEF2F2))
                  : (isDark ? DefensysTokens.mistPanel : const Color(0xFFF8FAFC)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _isAdmin
                    ? maroon.withValues(alpha: 0.45)
                    : DefensysTokens.borderOf(context),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'System Administrator',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: DefensysTokens.textPrimaryOf(context),
                            ),
                          ),
                          ShadBadge.outline(
                            child: Text(
                              _isAdmin ? 'Superuser' : 'Standard',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: _isAdmin ? maroon : secondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Full access to configuration, users, schedules and grades.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.45,
                          color: secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Semantics(
                  label: 'System Administrator',
                  toggled: _isAdmin,
                  child: ShadSwitch(
                    key: const ValueKey('role-admin'),
                    value: _isAdmin,
                    enabled: !widget.state.isSaving,
                    onChanged: _toggleAdmin,
                    checkedTrackColor: maroon,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E24) : const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _isAdmin ? LucideIcons.shieldAlert : LucideIcons.info,
                  size: 15,
                  color: _isAdmin ? DefensysTokens.goldOf(context) : secondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _isAdmin
                        ? 'Administrator privileges are elevated. This account can alter system settings, period schedules, and managed users.'
                        : 'Changes require explicit confirmation. Operational duties remain active regardless of administrative access.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _guidelinesCard() {
    return ShadCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.bookOpen,
                  size: 16, color: DefensysTokens.maroonTextOf(context)),
              const SizedBox(width: 8),
              Text(
                'Duty Guidelines',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textPrimaryOf(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _guideItem(
            icon: LucideIcons.usersRound,
            title: 'Defense Panelist',
            desc:
                'Evaluates capstone student teams and enters rubrics scoring.',
          ),
          const SizedBox(height: 10),
          _guideItem(
            icon: LucideIcons.flag,
            title: 'PIT Leadership',
            desc:
                'Oversees student cohort enrollment and requirements for the year.',
          ),
          const SizedBox(height: 10),
          _guideItem(
            icon: LucideIcons.graduationCap,
            title: 'Project Advising',
            desc: 'Mentors assigned capstone teams and reviews submissions.',
          ),
          const SizedBox(height: 10),
          _guideItem(
            icon: LucideIcons.filePenLine,
            title: 'Defense Minutes',
            desc: 'Records minutes and captures official signatures.',
          ),
        ],
      ),
    );
  }

  Widget _guideItem({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    final secondary = DefensysTokens.textSecondaryOf(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: secondary),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: secondary,
                fontFamily: DefensysTokens.fontFamilyInter,
              ),
              children: [
                TextSpan(
                  text: '$title: ',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: DefensysTokens.textPrimaryOf(context),
                  ),
                ),
                TextSpan(text: desc),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _operationalDutiesCard(Color secondary, bool busy) {
    final isDark = DefensysTokens.isDark(context);
    final maroon = DefensysTokens.maroonOf(context);

    int activeCount = 0;
    if (_isPanelist) activeCount++;
    if (_isPitLead) activeCount++;
    if (_isAdviser) activeCount++;
    if (_isDocumenter) activeCount++;

    return ShadCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'Operational duties',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        ShadBadge.secondary(
                          child: Text(
                            '$activeCount active',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'A faculty member can hold several duties, each with its own workspace.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _dutyTile(
            id: 'panelist',
            title: 'Defense Panelist',
            description:
                'Eligible for the reusable panelist pool. Defense assignments are made in scheduling.',
            icon: LucideIcons.usersRound,
            iconColor: const Color(0xFF2563EB),
            iconBg: const Color(0xFFEFF6FF),
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
                          : () => _leave(widget.onOpenPanelistAccess!),
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
          _dutyTile(
            id: 'pit-lead',
            title: 'PIT Lead',
            description:
                'Coordinates PIT activities and nominations for the assigned year.',
            icon: LucideIcons.flag,
            iconColor: const Color(0xFFD97706),
            iconBg: const Color(0xFFFFFBEB),
            value: _isPitLead,
            onChanged: (v) => _change(() {
              _isPitLead = v;
              if (!v) _pitLeadYear = null;
            }),
            extra: !_isPitLead
                ? null
                : Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark
                          ? DefensysTokens.mistInputFill
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: DefensysTokens.borderOf(context)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PIT Lead Year',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ShadSelect<String>(
                          key: ValueKey('pit-year-$_pitLeadYear'),
                          initialValue: _pitLeadYear,
                          placeholder: const Text('Choose a year level'),
                          enabled: !busy,
                          minWidth: 160,
                          options: [
                            for (final year in widget.pitLeadYearOptions)
                              ShadOption(
                                value: year,
                                child: Text(year),
                              ),
                          ],
                          selectedOptionBuilder: (_, year) => Text(year),
                          onChanged: (year) =>
                              _change(() => _pitLeadYear = year),
                        ),
                      ],
                    ),
                  ),
          ),
          _dutyTile(
            id: 'adviser',
            title: 'Project Adviser',
            description:
                'Advises assigned capstone teams and reviews their requirements.',
            icon: LucideIcons.graduationCap,
            iconColor: const Color(0xFF059669),
            iconBg: const Color(0xFFECFDF5),
            value: _isAdviser,
            onChanged: (v) => _change(() => _isAdviser = v),
          ),
          _dutyTile(
            id: 'documenter',
            title: 'Documenter',
            description:
                'Records and signs minutes for assigned capstone defenses.',
            icon: LucideIcons.filePenLine,
            iconColor: const Color(0xFF7C3AED),
            iconBg: const Color(0xFFF5F3FF),
            value: _isDocumenter,
            onChanged: (v) => _change(() => _isDocumenter = v),
          ),
          if (_validationError != null || widget.state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: DefensysTokens.dangerBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.dangerBorder),
                ),
                child: Row(
                  children: [
                    const Icon(LucideIcons.circleAlert,
                        size: 16, color: DefensysTokens.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _validationError ?? widget.state.error!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: DefensysTokens.dangerText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          Divider(color: DefensysTokens.borderOf(context), height: 1),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _hasChanges
                          ? DefensysTokens.gold
                          : const Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _hasChanges
                        ? 'Unsaved role changes'
                        : 'All role changes saved',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: secondary,
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  if (_hasChanges)
                    ShadButton.outline(
                      enabled: !busy,
                      onPressed: busy ? null : () => _change(_reset),
                      child: const Text('Discard changes'),
                    ),
                  ShadButton(
                    enabled: _hasChanges && !busy,
                    onPressed: _hasChanges && !busy ? _save : null,
                    backgroundColor: maroon,
                    leading: const Icon(
                      LucideIcons.save,
                      size: 15,
                    ),
                    child: Text(
                      busy ? 'Saving…' : 'Save Role Configuration',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _dutyTile({
    required String id,
    required String title,
    required String description,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? extra,
  }) {
    final isDark = DefensysTokens.isDark(context);
    final borderColor = value
        ? (isDark
            ? DefensysTokens.maroonOf(context).withValues(alpha: 0.5)
            : DefensysTokens.maroonOf(context).withValues(alpha: 0.35))
        : DefensysTokens.borderOf(context);

    final bgColor = value
        ? (isDark ? DefensysTokens.mistPanel : const Color(0xFFFDFBFB))
        : DefensysTokens.surfaceOf(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: value ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: isDark ? iconColor.withValues(alpha: 0.15) : iconBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 19, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                        ShadBadge.outline(
                          child: Text(
                            value ? 'Active' : 'Inactive',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: value
                                  ? DefensysTokens.maroonTextOf(context)
                                  : DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: DefensysTokens.textSecondaryOf(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
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
              padding: const EdgeInsets.only(top: 12),
              child: extra,
            ),
        ],
      ),
    );
  }

  Widget _studentNotice(Color secondary) {
    return ShadCard(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          const Icon(LucideIcons.info, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Student access follows academic records and team memberships.',
              style: TextStyle(fontSize: 14, color: secondary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyView() {
    final isDark = DefensysTokens.isDark(context);
    final secondary = DefensysTokens.textSecondaryOf(context);
    final primary = DefensysTokens.textPrimaryOf(context);

    return ShadCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Role assignment history',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: primary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Audit log of role and privilege changes for this user account.',
                      style: TextStyle(fontSize: 13, color: secondary),
                    ),
                  ],
                ),
              ),
              ShadButton.outline(
                size: ShadButtonSize.sm,
                enabled: !_historyLoading,
                onPressed: _historyLoading ? null : _loadHistory,
                leading: const Icon(LucideIcons.refreshCw, size: 14),
                child: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (_historyLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(36),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_historyError != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: DefensysTokens.dangerBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: DefensysTokens.dangerBorder),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.circleAlert,
                      size: 16, color: DefensysTokens.danger),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _historyError!,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: DefensysTokens.dangerText,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (_history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.history,
                        size: 40, color: secondary.withValues(alpha: 0.6)),
                    const SizedBox(height: 12),
                    Text(
                      'No role assignments recorded yet.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Historical role changes for this account will appear here.',
                      style: TextStyle(
                          fontSize: 12, color: secondary.withValues(alpha: 0.8)),
                    ),
                  ],
                ),
              ),
            )
          else
            for (int i = 0; i < _history.length; i++) ...[
              if (i > 0)
                Divider(
                    color: DefensysTokens.borderOf(context), height: 1),
              _historyItem(_history[i], primary, secondary, isDark),
            ],
        ],
      ),
    );
  }

  Widget _historyItem(
    Map<String, dynamic> row,
    Color primary,
    Color secondary,
    bool isDark,
  ) {
    final isAssigned = row['action'] == 'assigned';
    final actionColor = isAssigned
        ? const Color(0xFF10B981)
        : const Color(0xFFEF4444);
    final actionBg = isAssigned
        ? (isDark
            ? const Color(0xFF064E3B).withValues(alpha: 0.4)
            : const Color(0xFFECFDF5))
        : (isDark
            ? const Color(0xFF7F1D1D).withValues(alpha: 0.4)
            : const Color(0xFFFEF2F2));

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: actionBg,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isAssigned ? LucideIcons.circleCheck : LucideIcons.circleMinus,
              size: 18,
              color: actionColor,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['role_label'] ?? row['role_key']}${(row['role_detail'] ?? '').toString().isEmpty ? '' : ' · ${row['role_detail']}'}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: primary,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${row['changed_by_name'] ?? 'System'} · ${_date(row['changed_at'])}',
                  style: TextStyle(
                    fontSize: 12,
                    color: secondary,
                  ),
                ),
                if (row['semester'] != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    row['semester'].toString(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: DefensysTokens.maroonTextOf(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          ShadBadge.outline(
            child: Text(
              isAssigned ? 'Assigned' : 'Revoked',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: isAssigned
                    ? (isDark
                        ? const Color(0xFF34D399)
                        : const Color(0xFF059669))
                    : (isDark
                        ? const Color(0xFFF87171)
                        : const Color(0xFFDC2626)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null
        ? 'Date unavailable'
        : DateFormat('MMM d, y · h:mm a').format(date);
  }
}
