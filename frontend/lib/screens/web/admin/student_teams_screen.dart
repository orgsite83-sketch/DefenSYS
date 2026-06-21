import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/l10n_ext.dart';
import '../../../navigation/admin_route_paths.dart';
import '../../../services/dashboard_provider.dart';
import '../../../services/student_teams_provider.dart';
import '../../../utils/csv_file_io.dart';
import '../../../utils/team_bulk_import_csv.dart';
import '../../../utils/team_bulk_import_draft.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/feedback_toast.dart';
import 'widgets/defensys_admin_shell.dart';
import 'widgets/team_bulk_import_review_table.dart';

List<String> _formatBulkImportErrorLines(dynamic messages) {
  if (messages is List) {
    return messages.map((item) => item.toString()).toList();
  }
  if (messages is Map) {
    final lines = <String>[];
    for (final entry in messages.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value is List) {
        for (final item in value) {
          lines.add('$key: $item');
        }
      } else {
        lines.add('$key: $value');
      }
    }
    return lines;
  }
  return [messages?.toString() ?? 'Unknown error'];
}

/// Who is viewing the shared Student Teams screen.
enum TeamListMode {
  /// System admin: capstone teams (+ optional PIT filter for audit).
  capstoneAdmin,

  /// Faculty PIT Lead workspace: PIT teams for assigned year only.
  pitLead,

  /// Faculty PIT Instructor workspace: PIT teams for assigned section only.
  pitInstructor,
}

class StudentTeamsScreen extends ConsumerStatefulWidget {
  const StudentTeamsScreen({
    super.key,
    this.mode = TeamListMode.capstoneAdmin,
    this.onOpenStudentRecords,
    this.initialBulkImport = false,
  });

  final TeamListMode mode;

  /// Opens Student Academic Records (rollover) from the admin shell.
  final VoidCallback? onOpenStudentRecords;
  final bool initialBulkImport;

  @override
  ConsumerState<StudentTeamsScreen> createState() => _StudentTeamsScreenState();
}

class _StudentTeamsScreenState extends ConsumerState<StudentTeamsScreen> {
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _gold = DefensysUi.accentGold;
  static const _blue = DefensysUi.techBlue;
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFDC2626);
  static const _line = Color(0xFFE5E7EB);

  final _searchController = TextEditingController();

  bool? _showBulkImport = false;
  String? _bulkCsv = '';
  String? _bulkAdviserFilter = 'all';
  Map<String, dynamic>? _bulkPreview;
  List<Map<String, dynamic>> _parsedBulkRows = [];
  bool _showIssuesOnly = false;
  TeamBulkImportDraft? _savedDraft;
  Timer? _draftSaveTimer;
  Timer? _rowPreviewTimer;
  String? _bulkImportSessionBaseline;
  String? _bulkImportPersistedSnapshot;
  String? _templateWarning;
  List<String> _csvColumns = [];
  String? _section;
  String? _systemName;
  String? _projectManager;

  bool get _isBulkImportVisible => _showBulkImport == true;
  String get _selectedBulkAdviserFilter => _bulkAdviserFilter ?? 'all';
  String get _csvDraft => _bulkCsv ?? '';

  bool get _isCapstoneAdmin => widget.mode == TeamListMode.capstoneAdmin;

  bool get _isPitLeadManager => widget.mode == TeamListMode.pitLead;

  bool get _isPitInstructor => widget.mode == TeamListMode.pitInstructor;

  bool get _pitTermIsAudit =>
      _isPitLeadManager && ref.read(studentTeamsProvider).operatingMode == 'audit';

  String _teamListScope = 'active';

  String? get _pitLeadYear {
    if (!_isPitLeadManager) {
      return null;
    }
    final faculty = ref.read(dashboardProvider('faculty')).data;
    final topLevel = faculty?['pit_lead_year']?.toString().trim();
    if (topLevel != null && topLevel.isNotEmpty) {
      return topLevel;
    }
    final roles =
        (faculty?['roles'] as Map?)?.cast<String, dynamic>() ?? {};
    final year = roles['pit_lead_year']?.toString().trim();
    return year != null && year.isNotEmpty ? year : null;
  }

  /// Admin dropdown may display Capstone while [state.level] is still empty
  /// until the first fetch completes or admin dashboard loads.
  String _teamLevelFilter(StudentTeamsState state) {
    if (!_isCapstoneAdmin) {
      return state.level;
    }
    final level = state.level.trim();
    if (level.isEmpty || level == 'Capstone') {
      return 'Capstone';
    }
    return level;
  }

  bool _isPitContext(StudentTeamsState state) =>
      _isPitLeadManager ||
      _isPitInstructor ||
      (_isCapstoneAdmin && _teamLevelFilter(state) == 'PIT');

  bool _teamIsPit(Map<String, dynamic> team) =>
      team['level']?.toString().toUpperCase().contains('PIT') ?? false;

  void _deriveLevelOnRow(Map<String, dynamic> row) {
    applyDerivedLevelToRow(
      row,
      isCapstoneAdmin: _isCapstoneAdmin,
      pitLeadYear: _pitLeadYear,
    );
  }

  void _deriveLevelsOnRows(List<Map<String, dynamic>> rows) {
    for (final row in rows) {
      _deriveLevelOnRow(row);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadBulkDraft();
      _fetchTeamsForCurrentRole();
      if (widget.initialBulkImport && mounted) {
        _openBulkImport();
      }
    });
  }

  void _openTeamDetailRoute(int teamId) {
    final route = (_isPitLeadManager || _isPitInstructor)
        ? FacultyRoutes.teamDetail(teamId)
        : AdminRoutes.teamDetail(teamId);
    context.push(route);
  }

  void _fetchTeamsForCurrentRole({String? scope}) {
    final initialLevel = _isCapstoneAdmin ? 'Capstone' : '';
    ref.read(studentTeamsProvider.notifier).fetchTeams(
          level: initialLevel,
          scope: (_isPitLeadManager || _isPitInstructor) ? (scope ?? _teamListScope) : null,
        );
  }

  @override
  void dispose() {
    _draftSaveTimer?.cancel();
    _rowPreviewTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isPitLeadManager || _isPitInstructor) {
      ref.watch(dashboardProvider('faculty'));
    }
    final state = ref.watch(studentTeamsProvider);

    if (_isBulkImportVisible) {
      return _bulkImportPage(state);
    }

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.groups_2_rounded,
            title: 'Student Teams',
            subtitle: _isCapstoneAdmin
                ? 'Manage capstone project teams, assign advisers, and review defense context.'
                : 'Manage PIT teams and PIT events for your assigned year level.',
            actions: _headerActions(state),
          ),
          const SizedBox(height: 26),
          _summaryCards(state),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(state.error!, warning: true),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(state.message!),
          ],
          if (state.operatingMessage != null &&
              state.operatingMessage!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            _notice(state.operatingMessage!, warning: _pitTermIsAudit),
          ],
          if (_isPitLeadManager || _isPitInstructor) ...[
            const SizedBox(height: 14),
            _pitTeamScopeToggle(state),
          ],
          if (_savedDraft != null && !_isBulkImportVisible) ...[
            const SizedBox(height: 14),
            _draftResumeBanner(),
          ],
          const SizedBox(height: 22),
          _teamsTableCard(state),
        ],
      ),
    );
  }

  bool _canCreateCapstoneTeams(StudentTeamsState state) =>
      !_isCapstoneAdmin || state.canCreateCapstoneTeams;

  bool _canManageTeams(StudentTeamsState state) {
    if (_isPitInstructor) {
      return false;
    }
    if (_pitTermIsAudit || state.operatingMode == 'audit') {
      return false;
    }
    return _isPitLeadManager ||
        (_isCapstoneAdmin && _teamLevelFilter(state) == 'PIT') ||
        _canCreateCapstoneTeams(state);
  }

  bool _shouldBlockCapstoneCreate(StudentTeamsState state) =>
      _isCapstoneAdmin &&
      _teamLevelFilter(state) == 'Capstone' &&
      !state.canCreateCapstoneTeams;

  bool _canTapTeamActions(StudentTeamsState state) =>
      !state.isSaving &&
      (_canManageTeams(state) ||
          (_isCapstoneAdmin && _teamLevelFilter(state) == 'Capstone'));

  Future<void> _showCapstoneCreationBlockedDialog(
    StudentTeamsState state,
  ) async {
    final message = state.capstoneModeMessage?.trim();
    if (message == null || message.isEmpty || !mounted) {
      return;
    }

    final isCapstone2 = state.capstoneMode == 'capstone_2_continue';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Capstone team creation closed'),
        content: SizedBox(
          width: 480,
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF374151),
              fontSize: 14,
              height: 1.45,
            ),
          ),
        ),
        actions: [
          if (isCapstone2 && widget.onOpenStudentRecords != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                widget.onOpenStudentRecords?.call();
              },
              child: const Text('Student Records'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onBulkImportPressed(StudentTeamsState state) {
    if (_shouldBlockCapstoneCreate(state)) {
      _showCapstoneCreationBlockedDialog(state);
      return;
    }
    if (!_canManageTeams(state) || state.isSaving) {
      return;
    }
    _openBulkImport();
  }

  void _onCreateTeamPressed(StudentTeamsState state) {
    if (_shouldBlockCapstoneCreate(state)) {
      _showCapstoneCreationBlockedDialog(state);
      return;
    }
    if (!_canManageTeams(state) || state.isSaving) {
      return;
    }
    _showTeamDialog();
  }

  Widget _headerActions(StudentTeamsState state) {
    if (_isPitInstructor) {
      return const SizedBox.shrink();
    }
    final canTapActions = _canTapTeamActions(state);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _secondaryButton(
          icon: Icons.description_rounded,
          label: 'CSV Template',
          onTap: _downloadCsvTemplate,
        ),
        const SizedBox(width: 14),
        _secondaryButton(
          icon: Icons.output_rounded,
          label: 'Bulk Import',
          onTap: canTapActions ? () => _onBulkImportPressed(state) : null,
        ),
        const SizedBox(width: 14),
        _primaryButton(
          icon: Icons.add_rounded,
          label: 'Create New Team',
          onTap: canTapActions ? () => _onCreateTeamPressed(state) : null,
        ),
      ],
    );
  }

  Widget _summaryCards(StudentTeamsState state) {
    final hideAdviser = _isPitContext(state);
    final cards = <Widget>[
      Expanded(
        child: _summaryCard(
          title: 'All Teams',
          value: _count(state, 'all'),
          subtitle: '',
          icon: Icons.groups_2_rounded,
          selected: true,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _summaryCard(
          title: 'Result Pending',
          value: _count(state, 'pending'),
          subtitle: 'Awaiting decision',
          icon: Icons.schedule_rounded,
          iconColor: const Color(0xFFB45309),
          iconBg: const Color(0xFFFEF3C7),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _summaryCard(
          title: 'Approved',
          value: _count(state, 'approved'),
          subtitle: 'Passed',
          icon: Icons.check_circle_rounded,
          iconColor: const Color(0xFF047857),
          iconBg: const Color(0xFFD1FAE5),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: _summaryCard(
          title: 'Failed',
          value: _count(state, 'failed'),
          subtitle: 'Teams',
          icon: Icons.cancel_rounded,
          iconColor: const Color(0xFFB91C1C),
          iconBg: const Color(0xFFFEE2E2),
        ),
      ),
    ];
    if (!hideAdviser) {
      cards.addAll([
        const SizedBox(width: 12),
        Expanded(
          child: _summaryCard(
            title: 'Adviser Review',
            value: _count(state, 'no_adviser'),
            subtitle: 'Needs Review',
            icon: Icons.warning_rounded,
            iconColor: const Color(0xFFD97706),
            iconBg: const Color(0xFFFEF3C7),
          ),
        ),
      ]);
    }
    return Row(children: cards);
  }

  Widget _summaryCard({
    required String title,
    required int value,
    required String subtitle,
    required IconData icon,
    bool selected = false,
    Color iconColor = _blue,
    Color iconBg = const Color(0xFFEFF6FF),
  }) {
    return Container(
      height: 101,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFFFF4F4) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: selected ? _maroon : Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: selected ? const Color(0xFFF1F2F4) : iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: selected ? _ink : iconColor, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value.toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F2743),
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF98A2B3),
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                      height: 1.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamsTableCard(StudentTeamsState state) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      decoration: DefensysUi.cardDecoration(),
      clipBehavior: Clip.none,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _searchField(state)),
              const SizedBox(width: 16),
              _levelFilter(state),
            ],
          ),
          const SizedBox(height: 16),
          if (state.isLoading)
            const SizedBox(
              height: 150,
              child: Center(child: CircularProgressIndicator(color: _maroon)),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: 1515, child: _teamsTable(state)),
            ),
          const SizedBox(height: 18),
          Container(height: 1, color: _line),
          const SizedBox(height: 14),
          Row(
            children: [
              Text(
                'Showing ${state.teams.length} of ${_count(state, 'filtered')} teams',
                style: const TextStyle(
                  color: Color(0xFF98A2B3),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchField(StudentTeamsState state) {
    return SizedBox(
      height: 43,
      child: TextField(
        controller: _searchController,
        enabled: !state.isSaving,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 19),
          hintText: _isPitContext(state)
              ? 'Search by project title or leader...'
              : 'Search by project title, leader, or adviser...',
          hintStyle: const TextStyle(color: _muted, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFFF3F4F6),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _maroon),
          ),
        ),
        onSubmitted: (value) {
          ref.read(studentTeamsProvider.notifier).fetchTeams(search: value);
        },
      ),
    );
  }

  Widget _levelFilter(StudentTeamsState state) {
    if (_isPitLeadManager || _isPitInstructor) {
      return const SizedBox.shrink();
    }

    final levelItems = <DropdownMenuItem<String>>[
      const DropdownMenuItem(
        value: 'Capstone',
        child: Text('Capstone Teams'),
      ),
      const DropdownMenuItem(
        value: 'PIT',
        child: Text('PIT Teams'),
      ),
    ];
    final values = levelItems.map((item) => item.value).toSet();
    final safeValue = values.contains(_teamLevelFilter(state))
        ? _teamLevelFilter(state)
        : 'Capstone';

    return Container(
      width: 220,
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
          style: const TextStyle(
            color: _ink,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
          items: levelItems,
          onChanged: state.isSaving
              ? null
              : (value) {
                  ref
                      .read(studentTeamsProvider.notifier)
                      .fetchTeams(level: value ?? '');
                },
        ),
      ),
    );
  }

  Widget _teamsTable(StudentTeamsState state) {
    final hideAdviser = _isPitContext(state);
    final pitOnlyView = hideAdviser;
    final columns = <_ColumnSpec>[
      const _ColumnSpec('Project Title', 1.45),
      const _ColumnSpec('Year Level', 1.0),
      const _ColumnSpec('Team Result', 1.12),
      _ColumnSpec(pitOnlyView ? 'PIT Event' : 'Defense Context', 1.42),
      const _ColumnSpec('Leader', 0.78),
      if (!hideAdviser) const _ColumnSpec('Adviser', 0.85),
      const _ColumnSpec('Members', 0.98),
      const _ColumnSpec('Details', 0.55),
    ];
    return Column(
      children: [
        _tableHeader(columns),
        if (state.teams.isEmpty)
          _emptyRows()
        else
          ...state.teams.map((team) => _teamRow(state, team, hideAdviser: hideAdviser)),
      ],
    );
  }

  Widget _tableHeader(List<_ColumnSpec> columns) {
    return Container(
      height: 51,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F1F4),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(children: columns.map(_tableHeaderCell).toList()),
    );
  }

  Widget _tableHeaderCell(_ColumnSpec column) {
    return Expanded(
      flex: (column.flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            column.label,
            style: const TextStyle(
              color: Color(0xFF5D6678),
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  Widget _teamRow(
    StudentTeamsState state,
    Map<String, dynamic> team, {
    required bool hideAdviser,
  }) {
    final leaderName = team['leader_name']?.toString() ?? '-';
    final members = team['members'] as List? ?? const [];
    final leaderId = team['leader_id'];
    final leaderMember = members.firstWhere(
      (m) => m is Map && m['id'] == leaderId,
      orElse: () => null,
    );
    final leaderEnrolled = leaderMember == null || leaderMember['is_enrolled'] == true;
    final hasUnenrolled = members.any((m) => m is Map && m['is_enrolled'] == false);

    Widget leaderWidget;
    if (!leaderEnrolled && leaderName != '-') {
      leaderWidget = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 6,
        children: [
          Text(
            leaderName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            decoration: BoxDecoration(
              color: const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: const Color(0xFFFCA5A5)),
            ),
            child: const Text(
              'Not Enrolled',
              style: TextStyle(
                color: Color(0xFFB91C1C),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      );
    } else {
      leaderWidget = _bodyText(leaderName);
    }

    Widget membersWidget;
    final memberCountStr = '${team['member_count'] ?? 0}';
    if (hasUnenrolled) {
      membersWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            memberCountStr,
            style: const TextStyle(
              color: _ink,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          const Tooltip(
            message: 'Contains non-enrolled members',
            child: Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFD97706),
              size: 16,
            ),
          ),
        ],
      );
    } else {
      membersWidget = _bodyText(memberCountStr);
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          _tableCell(
            Text(
              _projectTitle(team),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
            flex: 1.45,
          ),
          _tableCell(_bodyText(team['year_level']?.toString() ?? '-'), flex: 1),
          _tableCell(
            _statusBadge(team['status']?.toString() ?? 'Pending'),
            flex: 1.12,
          ),
          _tableCell(_bodyText(_defenseContext(team)), flex: 1.42),
          _tableCell(
            leaderWidget,
            flex: 0.78,
          ),
          if (!hideAdviser)
            _tableCell(
              _bodyText(team['adviser_name']?.toString() ?? '-'),
              flex: 0.85,
            ),
          _tableCell(membersWidget, flex: 0.98),
          _tableCell(_rowActions(state, team), flex: 0.55),
        ],
      ),
    );
  }

  Widget _tableCell(Widget child, {required double flex}) {
    return Expanded(
      flex: (flex * 100).round(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _bodyText(String value) {
    return Text(
      value.isEmpty ? '-' : value,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: _ink,
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _emptyRows() {
    return Container(
      height: 84,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: const Text(
        'No teams found.',
        style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = switch (status) {
      'Approved' => _green,
      'Failed' => _red,
      'Delayed/Extended' => _gold,
      _ => const Color(0xFFB45309),
    };
    final bg = switch (status) {
      'Approved' => const Color(0xFFD1FAE5),
      'Failed' => const Color(0xFFFEE2E2),
      'Delayed/Extended' => const Color(0xFFFEF3C7),
      _ => const Color(0xFFFEF3C7),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _rowActions(StudentTeamsState state, Map<String, dynamic> team) {
    final teamId = _asInt(team['id']);
    return Tooltip(
      message: 'View team details',
      child: InkWell(
        onTap: state.isSaving || teamId == null
            ? null
            : () => _openTeamDetailRoute(teamId),
        borderRadius: BorderRadius.circular(6),
        child: const Padding(
          padding: EdgeInsets.all(4),
          child: Icon(Icons.info_outline, color: _blue, size: 18),
        ),
      ),
    );
  }

  Widget _pitTeamScopeToggle(StudentTeamsState state) {
    return Row(
      children: [
        Container(
          width: 168,
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _teamListScope == 'active' ? 'active' : 'history',
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              style: const TextStyle(
                color: _ink,
                fontFamily: DefensysUi.fontFamily,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
              items: const [
                DropdownMenuItem(value: 'active', child: Text('Current Term')),
                DropdownMenuItem(value: 'history', child: Text('History')),
              ],
              onChanged: state.isSaving
                  ? null
                  : (value) {
                      if (value == null) return;
                      setState(() => _teamListScope = value);
                      _fetchTeamsForCurrentRole(scope: value);
                    },
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 42,
          child: OutlinedButton.icon(
            onPressed: state.isSaving
                ? null
                : () {
                    _searchController.clear();
                    setState(() => _teamListScope = 'active');
                    ref.read(studentTeamsProvider.notifier).fetchTeams(
                          level: _isCapstoneAdmin ? 'Capstone' : '',
                          scope: (_isPitLeadManager || _isPitInstructor) ? 'active' : null,
                          search: '',
                        );
                  },
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Clear'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _ink,
              side: const BorderSide(color: Color(0xFFD1D5DB)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
              padding: const EdgeInsets.symmetric(horizontal: 18),
              textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  Widget _secondaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: _ink,
          side: const BorderSide(color: Color(0xFFD1D5DB)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _primaryButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return SizedBox(
      height: 42,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: _maroon,
          foregroundColor: _gold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  Widget _notice(String message, {bool warning = false}) {
    final color = warning ? DefensysUi.warningText : DefensysUi.successText;
    final background = warning ? DefensysUi.warningBg : DefensysUi.successBg;
    final border = warning
        ? DefensysUi.warningBorder
        : DefensysUi.successBorder;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Future<void> _downloadCsvTemplate() async {
    if (_isPitLeadManager) {
      final year = _pitLeadYear ?? '3rd Year';
      await downloadTextFile(
        filename: sampleTeamCsvFilenameForYear(year),
        content: sampleTeamCsvForYear(year, isCapstoneAdmin: false),
      );
      return;
    }

    await downloadTextFile(
      filename: 'defensys-official-capstone-template.csv',
      content: 'Team Name,Capstone Project,Adviser,Team Members\n'
          'Team SkyLedger,Alumni Career Tracker,Ricardo Fontanilla,"VILLAR, Marcus"\n'
          ',,,"ONG, Patricia"\n'
          ',,,"SALAZAR, Ethan"\n'
          ',,,"CASTILLO, Zoe"\n',
    );
  }

  Future<void> _loadBulkDraft() async {
    final draft = await loadTeamBulkImportDraft();
    if (!mounted || draft == null) {
      return;
    }
    final rows = draft.rows.map((row) => Map<String, dynamic>.from(row)).toList();
    _deriveLevelsOnRows(rows);
    setState(() {
      _savedDraft = draft;
      _parsedBulkRows = rows;
      _bulkAdviserFilter = draft.adviserFilter;
      _bulkPreview = draft.preview;
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
  }

  Future<void> _persistBulkDraft() async {
    if (_parsedBulkRows.isEmpty) {
      await clearTeamBulkImportDraft();
      if (mounted) {
        setState(() => _savedDraft = null);
      }
      return;
    }

    final draft = TeamBulkImportDraft(
      rows: _parsedBulkRows
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
      preview: _bulkPreview,
      adviserFilter: _selectedBulkAdviserFilter,
      savedAt: DateTime.now(),
      issueCount: countPreviewIssues(_bulkPreview),
    );
    await saveTeamBulkImportDraft(draft);
    if (mounted) {
      setState(() => _savedDraft = draft);
      _bulkImportPersistedSnapshot = _bulkImportSnapshot();
    }
  }

  void _scheduleDraftSave() {
    _draftSaveTimer?.cancel();
    _draftSaveTimer = Timer(const Duration(milliseconds: 500), () {
      _persistBulkDraft();
    });
  }

  String _bulkImportSnapshot() {
    return jsonEncode({
      'rows': _parsedBulkRows,
      'filter': _selectedBulkAdviserFilter,
    });
  }

  void _captureBulkImportBaseline({bool persisted = false}) {
    final snap = _bulkImportSnapshot();
    _bulkImportSessionBaseline ??= snap;
    if (persisted) {
      _bulkImportPersistedSnapshot = snap;
    }
  }

  bool get _isBulkImportDirty {
    if (!_isBulkImportVisible || _parsedBulkRows.isEmpty) return false;
    if (_draftSaveTimer?.isActive ?? false) return true;
    final current = _bulkImportSnapshot();
    final baseline = _bulkImportPersistedSnapshot ?? _bulkImportSessionBaseline;
    return baseline != null && current != baseline;
  }

  Future<void> _requestCloseBulkImport() async {
    if (_isBulkImportDirty) {
      final leave = await showConfirmDialog(
        context,
        title: context.l10n.leaveBulkImportTitle,
        message: context.l10n.leaveBulkImportMessage,
        confirmLabel: context.l10n.saveAndLeave,
        cancelLabel: context.l10n.stay,
      );
      if (!leave || !mounted) return;
      _draftSaveTimer?.cancel();
      await _persistBulkDraft();
      _bulkImportPersistedSnapshot = _bulkImportSnapshot();
    } else {
      _scheduleDraftSave();
    }
    if (!mounted) return;
    setState(() => _showBulkImport = false);
  }

  Future<void> _discardBulkDraftConfirmed() async {
    await clearTeamBulkImportDraft();
    if (!mounted) {
      return;
    }
    setState(() {
      _savedDraft = null;
      _parsedBulkRows = [];
      _bulkCsv = '';
      _bulkPreview = null;
      _templateWarning = null;
      _csvColumns = [];
      _section = null;
      _systemName = null;
      _projectManager = null;
    });
  }

  Future<void> _discardBulkDraft() async {
    final confirmed = await confirmDestructive(
      context,
      title: 'Discard draft?',
      message: 'Your saved bulk import draft will be permanently deleted.',
      confirmLabel: 'Discard',
    );
    if (!confirmed || !mounted) return;
    await _discardBulkDraftConfirmed();
  }

  void _openBulkImport({bool resumeDraft = false}) {
    _bulkImportSessionBaseline = null;
    _bulkImportPersistedSnapshot = null;
    setState(() {
      _templateWarning = null;
      _csvColumns = [];
    });
    if (resumeDraft && _savedDraft != null) {
      setState(() {
        _showBulkImport = true;
        _parsedBulkRows = _savedDraft!.rows
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
        _bulkAdviserFilter = _savedDraft!.adviserFilter;
        _bulkPreview = _savedDraft!.preview;
        _bulkCsv = rowsToTeamCsv(
          _parsedBulkRows,
          isCapstoneAdmin: _isCapstoneAdmin,
        );
        _csvColumns = bulkImportHeaderFor(isCapstoneAdmin: _isCapstoneAdmin).split(',');
      });
      _captureBulkImportBaseline(persisted: true);
      _refreshBulkPreview();
      return;
    }

    setState(() => _showBulkImport = true);
    _captureBulkImportBaseline();
  }

  void _applyParsedRows(ParsedBulkCsvResult result) {
    final normalized = result.rows.map((row) => Map<String, dynamic>.from(row)).toList();
    _deriveLevelsOnRows(normalized);
    setState(() {
      _parsedBulkRows = normalized;
      _section = result.section;
      _systemName = result.systemName;
      _projectManager = result.projectManager;
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
    _scheduleDraftSave();
    _refreshBulkPreview();
  }

  Widget _draftResumeBanner() {
    final draft = _savedDraft!;
    final issueCount = draft.issueCount > 0
        ? draft.issueCount
        : countPreviewIssues(draft.preview);
    final savedLabel = MaterialLocalizations.of(context).formatShortDate(draft.savedAt);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF93C5FD)),
      ),
      child: Row(
        children: [
          const Icon(Icons.pending_actions_rounded, color: _blue, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              issueCount > 0
                  ? 'Unfinished bulk import — $issueCount row${issueCount == 1 ? '' : 's'} need fixes · Saved $savedLabel'
                  : 'Unfinished bulk import · Saved $savedLabel',
              style: const TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _secondaryButton(
            icon: Icons.play_arrow_rounded,
            label: 'Resume',
            onTap: () => _openBulkImport(resumeDraft: true),
          ),
          const SizedBox(width: 8),
          _secondaryButton(
            icon: Icons.delete_outline_rounded,
            label: 'Discard',
            onTap: _discardBulkDraft,
          ),
        ],
      ),
    );
  }

  Widget _bulkImportPage(StudentTeamsState state) {
    return PopScope(
      canPop: !_isBulkImportDirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _requestCloseBulkImport();
      },
      child: SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.output_rounded,
            title: 'Bulk Import Teams',
            subtitle:
                'Upload a CSV, review teams in the table, fix issues inline, then import ready rows.',
            actions: _secondaryButton(
              icon: Icons.arrow_back_rounded,
              label: 'Back to Teams',
              onTap: state.isSaving ? null : () => _requestCloseBulkImport(),
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _notice(state.error!, warning: true),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _notice(state.message!),
          ],
          const SizedBox(height: 28),
          _teamCsvFormatCard(),
          const SizedBox(height: 20),
          _teamUploadCsvCard(state),
        ],
      ),
      ),
    );
  }

  Widget _teamCsvFormatCard() {
    if (_isCapstoneAdmin) {
      final columns = const [
        'Team Name',
        'Capstone Project',
        'Adviser',
        'Team Members',
      ];
      final rows = const [
        ['Team SkyLedger', 'Alumni Career Tracker', 'Ricardo Fontanilla', 'VILLAR, Marcus'],
        ['', '', '', 'ONG, Patricia'],
        ['', '', '', 'SALAZAR, Ethan'],
        ['', '', '', 'CASTILLO, Zoe'],
      ];

      return DefensysCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Official Capstone CSV Format',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Each team can span multiple rows. The first member listed is set as the team leader.',
                    style: TextStyle(
                      color: Color(0xFF536079),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Container(height: 1, color: _line),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _bulkSampleMultiRowTable(columns, rows),
                  const SizedBox(height: 14),
                  _infoBanner(
                    'Official format: Team Members must use full names (First Last or Last, First). The adviser and year level will be resolved from student details. Standard DefenSYS format (one-row-per-team with pipe-separated member names) is also accepted automatically.',
                  ),
                  const SizedBox(height: 16),
                  _secondaryButton(
                    icon: Icons.file_download_rounded,
                    label: 'Download Sample Template',
                    onTap: _downloadCsvTemplate,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final columns = const [
      'Team Name',
      'PIT Project',
      'Team Members',
    ];
    final rows = const [
      ['Team CodeLearners', 'Smart Campus Navigator', 'Carlos Reyes'],
      ['', '', 'Maria Santos'],
      ['', '', 'Juan Dela Cruz'],
      ['', '', 'Ana Mendoza'],
      ['Team ByteBridge', 'Library Seat Finder', 'Darren Kim'],
    ];

    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Official PIT CSV Format',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Each team can span multiple rows. The first member listed is set as the team leader.',
                  style: TextStyle(
                    color: Color(0xFF536079),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bulkSampleMultiRowTable(columns, rows),
                const SizedBox(height: 14),
                _infoBanner(
                  'Official format: Team Members must use full names (First Last or Last, First). The year level will be resolved from student details. Standard DefenSYS format (one-row-per-team with pipe-separated member names) is also accepted automatically.',
                ),
                const SizedBox(height: 16),
                _secondaryButton(
                  icon: Icons.file_download_rounded,
                  label: 'Download Sample Template',
                  onTap: _downloadCsvTemplate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulkSampleTable(List<String> columns, List<String> values) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        children: [
          Container(
            height: 38,
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: columns
                  .map(
                    (column) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          column,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          Container(
            height: 40,
            alignment: Alignment.centerLeft,
            child: Row(
              children: values
                  .map(
                    (value) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          value,
                          style: const TextStyle(
                            color: Color(0xFF536079),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bulkSampleMultiRowTable(List<String> columns, List<List<String>> rows) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        children: [
          Container(
            height: 38,
            color: const Color(0xFFF8FAFC),
            child: Row(
              children: columns
                  .map(
                    (column) => Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text(
                          column,
                          style: const TextStyle(
                            color: _ink,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          for (final row in rows)
            Container(
              height: 36,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
              ),
              alignment: Alignment.centerLeft,
              child: Row(
                children: row
                    .map(
                      (value) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Text(
                            value,
                            style: const TextStyle(
                              color: Color(0xFF536079),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_rounded, color: Color(0xFFB45309), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFB45309),
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamUploadCsvCard(StudentTeamsState state) {
    return DefensysCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 20, 24, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Upload CSV',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Upload a CSV or resume a draft, edit rows in the review table, then import ready teams.',
                  style: TextStyle(
                    color: Color(0xFF536079),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isCapstoneAdmin) ...[
                  _fieldLabel('ADVISER IMPORT FILTER'),
                  const SizedBox(height: 8),
                  _dropdownBox(
                    value: _selectedBulkAdviserFilter,
                    hint: 'Select filter',
                    onChanged: state.isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _bulkAdviserFilter = value);
                            _refreshBulkPreview();
                            _scheduleDraftSave();
                          },
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All teams')),
                      DropdownMenuItem(
                        value: 'with_adviser',
                        child: Text('With adviser only'),
                      ),
                      DropdownMenuItem(
                        value: 'without_adviser',
                        child: Text('Without adviser only'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ],
                const Text(
                  'CSV source (upload / paste)',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                _fieldLabel('CSV FILE'),
                const SizedBox(height: 8),
                _bulkUploadDropZone(state),
                if (_templateWarning != null) ...[
                  const SizedBox(height: 12),
                  _notice(_templateWarning!, warning: true),
                ],
                if (_parsedBulkRows.isNotEmpty && _templateWarning == null) ...[
                  const SizedBox(height: 20),
                  _unifiedSectionMetadataCard(),
                  _teamBulkReviewSection(state),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    _primaryButton(
                      icon: Icons.system_update_alt_rounded,
                      label: state.isSaving
                          ? 'Importing...'
                          : 'Import ready teams',
                      onTap: state.isSaving || _parsedBulkRows.isEmpty || _templateWarning != null
                          ? null
                          : _importBulkTeams,
                    ),
                    const SizedBox(width: 12),
                    if (_parsedBulkRows.isNotEmpty && _templateWarning == null)
                      _secondaryButton(
                        icon: Icons.file_download_rounded,
                        label: 'Export CSV',
                        onTap: _exportBulkCsv,
                      ),
                    const SizedBox(width: 12),
                    _secondaryButton(
                      icon: Icons.close_rounded,
                      label: 'Cancel',
                      onTap: state.isSaving ? null : () => _requestCloseBulkImport(),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamBulkReviewSection(StudentTeamsState state) {
    final summary = (_bulkPreview?['summary'] as Map?)?.cast<String, dynamic>() ?? {};
    final previewRows = (_bulkPreview?['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final readyCount = _asInt(summary['ready']) ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFDDE2EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.fact_check_rounded, color: _maroon, size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Review & fix teams',
                  style: TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              FilterChip(
                label: const Text('Issues only'),
                selected: _showIssuesOnly,
                onSelected: state.isSaving
                    ? null
                    : (value) => setState(() => _showIssuesOnly = value),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${summary['total'] ?? _parsedBulkRows.length} rows · $readyCount ready to import',
            style: const TextStyle(
              color: Color(0xFF667085),
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          TeamBulkImportReviewTable(
            rows: _parsedBulkRows,
            previewRows: previewRows,
            isCapstoneAdmin: _isCapstoneAdmin,
            pitLeadYear: _pitLeadYear,
            showIssuesOnly: _showIssuesOnly,
            onRowChanged: _scheduleRowPreview,
            onDeleteRow: _deleteBulkRow,
            onAddRow: _addBulkRow,
          ),
        ],
      ),
    );
  }

  void _scheduleRowPreview(int index) {
    _scheduleDraftSave();
    _rowPreviewTimer?.cancel();
    _rowPreviewTimer = Timer(const Duration(milliseconds: 500), () {
      _preflightSingleRow(index);
    });
  }

  Future<void> _preflightSingleRow(int index) async {
    if (index < 0 || index >= _parsedBulkRows.length) {
      return;
    }
    final row = Map<String, dynamic>.from(_parsedBulkRows[index]);
    if (!_isCapstoneAdmin) {
      _deriveLevelOnRow(row);
    }
    _parsedBulkRows[index] = row;
    final preview = await ref.read(studentTeamsProvider.notifier).bulkImportPreview(
      [row],
      adviserFilter: _selectedBulkAdviserFilter,
    );
    if (!mounted || preview == null) {
      return;
    }
    final previewRows = (preview['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    if (previewRows.isEmpty) {
      return;
    }

    final previewRow = previewRows.first;
    if (_isCapstoneAdmin) {
      final inferredYear = previewRow['year_level']?.toString();
      final inferredLevel = previewRow['level']?.toString();
      if (inferredYear != null && inferredYear.isNotEmpty) {
        row['year_level'] = inferredYear;
      }
      if (inferredLevel != null && inferredLevel.isNotEmpty) {
        row['level'] = inferredLevel;
      }
      _parsedBulkRows[index] = row;
    }

    final existing = (_bulkPreview?['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final rowNumber = index + 1;
    final updated = [
      for (final item in existing)
        if (item['row'] != rowNumber) item,
      {...previewRows.first, 'row': rowNumber, 'sheet_row': rowNumber + 1},
    ];
    updated.sort((a, b) => (a['row'] as int).compareTo(b['row'] as int));

    final ready = updated.where((item) => item['ready'] == true).length;
    setState(() {
      _bulkPreview = {
        'rows': updated,
        'summary': {
          'total': _parsedBulkRows.length,
          'ready': ready,
          'with_adviser': updated
              .where((item) => item['adviser_status'] == 'valid')
              .length,
          'without_adviser': updated
              .where((item) => item['adviser_status'] == 'none')
              .length,
          'adviser_invalid': updated.where((item) {
            final status = item['adviser_status']?.toString() ?? '';
            return status != 'valid' && status != 'none';
          }).length,
        },
      };
    });
    _scheduleDraftSave();
  }

  void _addBulkRow() {
    final row = <String, dynamic>{
      'team_name': '',
      'project_title': '',
      if (!_isCapstoneAdmin) 'year_level': _pitLeadYear ?? '3rd Year',
      'member_ids': <String>[],
      'leader_id': '',
      'adviser_id': '',
    };
    _deriveLevelOnRow(row);
    setState(() {
      _parsedBulkRows = [..._parsedBulkRows, row];
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
    _refreshBulkPreview();
  }

  void _deleteBulkRow(int index) {
    setState(() {
      _parsedBulkRows = [
        for (var i = 0; i < _parsedBulkRows.length; i++)
          if (i != index) _parsedBulkRows[i],
      ];
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
    _refreshBulkPreview();
  }

  Future<void> _exportBulkCsv() async {
    if (_parsedBulkRows.isEmpty) {
      return;
    }
    await downloadTextFile(
      filename: 'defensys-team-import-draft.csv',
      content: rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      ),
    );
  }

  Widget _bulkUploadDropZone(StudentTeamsState state) {
    final csv = _csvDraft;
    final parsedRows = _parsedBulkRows.isNotEmpty
        ? _parsedBulkRows.length
        : _parseCsv(csv).length;

    return InkWell(
      onTap: state.isSaving ? null : _pickBulkCsvFile,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        height: 136,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFCBD5E1), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_upload_rounded,
              color: Color(0xFF98A2B3),
              size: 34,
            ),
            const SizedBox(height: 10),
            Text(
              csv.trim().isEmpty
                  ? 'Click to choose a CSV file'
                  : 'CSV content ready for preflight',
              style: const TextStyle(
                color: _ink,
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              csv.trim().isEmpty
                  ? 'Only .csv files accepted'
                  : '$parsedRows valid row${parsedRows == 1 ? '' : 's'} detected',
              style: const TextStyle(
                color: Color(0xFF98A2B3),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        color: Color(0xFF667085),
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _dropdownBox({
    required String? value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: onChanged == null ? const Color(0xFFF3F4F6) : Colors.white,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: const Color(0xFFD1D5DB)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 19),
          style: const TextStyle(
            color: _ink,
            fontFamily: DefensysUi.fontFamily,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Future<void> _pickBulkCsvFile() async {
    try {
      final csv = await pickCsvTextFile();
      if (!mounted || csv == null) {
        return;
      }

      final lines = csv
          .split(RegExp(r'\r?\n'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      List<String> headers = [];
      if (lines.isNotEmpty) {
        headers = lines.first
            .split(',')
            .map((header) => header.trim().toLowerCase().replaceFirst('\ufeff', ''))
            .toList();

        String? warning;
        final isClientTemplate = (headers.contains('team name') || headers.contains('team_name')) &&
            (headers.contains('team members') || headers.contains('team_members') || headers.contains('members'));
        final recognizedHeaders = {
          'team_name',
          'project_title',
          'level',
          'year_level',
          'member_ids',
          'leader_id',
          'adviser_id',
          'team name',
          'capstone project',
          'pit project',
          'project',
          'project title',
          'adviser',
          'team members',
          'members',
        };
        final unrecognized = headers.where((h) => !recognizedHeaders.contains(h)).toList();

        if (unrecognized.isNotEmpty) {
          warning = 'Wrong template? Unrecognized column(s) detected: ${unrecognized.join(", ")}. Please use the correct CSV template.';
        } else if (!_isCapstoneAdmin) {
          if (!isClientTemplate) {
            if (headers.contains('adviser_id') || headers.contains('year_level')) {
              warning = 'Wrong template? PIT import templates should not contain "adviser_id" or "year_level" columns. These will be ignored or cleared.';
            } else if (!headers.contains('member_ids') || !headers.contains('leader_id')) {
              warning = 'Wrong template? PIT import templates must contain "team_name", "project_title", "member_ids", and "leader_id" columns (or "Team Name" and "Team Members" for multi-row format).';
            }
          }
        } else {
          if (!isClientTemplate) {
            if (!headers.contains('adviser_id') || !headers.contains('year_level')) {
              warning = 'Wrong template? Capstone import templates should contain "year_level" and "adviser_id" columns (or "Team Name" and "Team Members" for client format).';
            }
          }
        }
        setState(() {
          _templateWarning = warning;
          _csvColumns = headers;
        });
      }

      final result = parseTeamBulkCsvWithContext(
        csv,
        isCapstoneAdmin: _isCapstoneAdmin,
        pitLeadYear: _pitLeadYear,
      );
      if (result.rows.isEmpty) {
        _snack('Selected file is not a valid DefenSYS team CSV template.');
        return;
      }

      _applyParsedRows(result);
    } catch (e) {
      _snack('Could not read CSV file: $e');
    }
  }

  Future<void> _refreshBulkPreview() async {
    if (_parsedBulkRows.isEmpty) {
      final result = parseTeamBulkCsvWithContext(
        _csvDraft,
        isCapstoneAdmin: _isCapstoneAdmin,
        pitLeadYear: _pitLeadYear,
      );
      if (result.rows.isEmpty) {
        setState(() => _bulkPreview = null);
        return;
      }
      final normalized = result.rows.map((row) => Map<String, dynamic>.from(row)).toList();
      _deriveLevelsOnRows(normalized);
      setState(() {
        _parsedBulkRows = normalized;
        _csvColumns = result.csvColumns;
        _section = result.section;
        _systemName = result.systemName;
        _projectManager = result.projectManager;
      });
    }

    _deriveLevelsOnRows(_parsedBulkRows);

    if (_parsedBulkRows.isEmpty) {
      setState(() => _bulkPreview = null);
      return;
    }

    final preview = await ref.read(studentTeamsProvider.notifier).bulkImportPreview(
      _parsedBulkRows,
      adviserFilter: _selectedBulkAdviserFilter,
      csvColumns: _csvColumns.isNotEmpty ? _csvColumns : null,
      section: _section,
      systemName: _systemName,
      projectManager: _projectManager,
    );
    if (!mounted) return;
    setState(() => _bulkPreview = preview);
    _scheduleDraftSave();
  }

  List<Map<String, dynamic>> _readyRowsForImport() {
    final previewRows = (_bulkPreview?['rows'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    if (previewRows.isEmpty) {
      return _parsedBulkRows;
    }

    final readyNumbers = previewRows
        .where((item) => item['ready'] == true)
        .map((item) => item['row'] as int)
        .toSet();

    if (readyNumbers.isEmpty) {
      return [];
    }

    final ready = <Map<String, dynamic>>[];
    for (var index = 0; index < _parsedBulkRows.length; index++) {
      if (readyNumbers.contains(index + 1)) {
        ready.add(Map<String, dynamic>.from(_parsedBulkRows[index]));
      }
    }
    return ready;
  }

  Future<void> _importBulkTeams() async {
    if (_parsedBulkRows.isEmpty) {
      _snack('Upload a CSV or add rows to import.');
      return;
    }

    if (_bulkPreview == null) {
      await _refreshBulkPreview();
    }

    final rows = _readyRowsForImport();
    if (rows.isEmpty) {
      _snack('No ready rows to import. Fix issues in the table first.');
      return;
    }

    final result = await ref.read(studentTeamsProvider.notifier).bulkImport(
      rows,
      adviserFilter: _selectedBulkAdviserFilter,
      csvColumns: _csvColumns.isNotEmpty ? _csvColumns : null,
      section: _section,
      systemName: _systemName,
      projectManager: _projectManager,
    );

    if (!mounted || result == null) {
      return;
    }

    final created = _asInt(result['created_count']) ?? 0;
    final errorCount = _asInt(result['error_count']) ?? 0;
    final importedRows = result['imported_rows'] as List? ?? const [];

    if (errorCount > 0) {
      _showImportResultDialog(result);
    }

    final remaining = trimRowsAfterImport(
      rows: _parsedBulkRows,
      importedRows: importedRows,
    );

    if (remaining.isEmpty) {
      await _discardBulkDraftConfirmed();
      if (!mounted) return;
      setState(() {
        _showBulkImport = false;
        _parsedBulkRows = [];
        _bulkCsv = '';
        _bulkPreview = null;
      });
      _snack('$created team${created == 1 ? '' : 's'} imported.');
      return;
    }

    setState(() {
      _parsedBulkRows = remaining;
      _bulkCsv = rowsToTeamCsv(
        _parsedBulkRows,
        isCapstoneAdmin: _isCapstoneAdmin,
      );
    });
    await _refreshBulkPreview();
    _snack(
      'Imported $created team${created == 1 ? '' : 's'}. '
      '${remaining.length} row${remaining.length == 1 ? '' : 's'} still need fixes — draft saved.',
    );
  }

  Future<void> _showImportResultDialog(Map<String, dynamic> result) async {
    final errors = (result['errors'] as List? ?? const [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();

    if (errors.isEmpty || !mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Import issues'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: errors.map((error) {
                final row = error['row'];
                final teamName = error['team_name']?.toString() ?? '-';
                final sheetRow = error['sheet_row'] ?? ((row is int) ? row + 1 : null);
                final issueLines = _formatBulkImportErrorLines(error['errors']);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Row $row · $teamName${sheetRow != null ? ' (sheet row $sheetRow)' : ''}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...issueLines.map(
                        (line) => Text(
                          '• $line',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _showTeamDialog() async {
    final state = ref.read(studentTeamsProvider);

    final isCapstoneAdmin = _isCapstoneAdmin;
    final isPitLead = _isPitLeadManager;
    const yearOptions = ['1st Year', '2nd Year', '3rd Year', '4th Year'];

    final statusOptions = state.statuses.isEmpty
        ? const ['Pending', 'Approved', 'Failed', 'Delayed/Extended']
        : state.statuses;
    final name = TextEditingController();
    final projectTitle = TextEditingController();
    var yearLevel = isCapstoneAdmin ? '3rd Year' : (_pitLeadYear ?? '3rd Year');
    if (!yearOptions.contains(yearLevel)) {
      yearLevel = isCapstoneAdmin ? '3rd Year' : (_pitLeadYear ?? '3rd Year');
    }
    var level = isPitLead
        ? '$yearLevel PIT'
        : '${yearLevel.trim()} Capstone';
    var status = 'Pending';
    if (!statusOptions.contains(status)) {
      status = statusOptions.first;
    }
    int? adviserId;
    if (!mounted) {
      name.dispose();
      projectTitle.dispose();
      return;
    }
    final selectedMembers = <int>{};
    int? leaderId;

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              surfaceTintColor: Colors.transparent,
              title: const Text('Create New Team'),
              content: SizedBox(
                width: 660,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: name,
                        decoration: const InputDecoration(
                          labelText: 'Team Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: projectTitle,
                        decoration: const InputDecoration(
                          labelText: 'Project Title',
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (isPitLead)
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Program',
                          ),
                          child: Text(
                            '$yearLevel PIT',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        )
                      else
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Program',
                          ),
                          child: Text(
                            'Capstone · $yearLevel',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(
                          labelText: 'Team Result',
                        ),
                        items: statusOptions
                            .map(
                              (item) => DropdownMenuItem(
                                value: item,
                                child: Text(item),
                              ),
                            )
                            .toList(),
                        onChanged: (value) {
                          setDialogState(() {
                            status = value ?? status;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      if (!isPitLead && level.toUpperCase().contains('CAPSTONE')) ...[
                        DropdownButtonFormField<int?>(
                          initialValue: adviserId,
                          decoration: const InputDecoration(labelText: 'Adviser'),
                          items: [
                            const DropdownMenuItem<int?>(
                              value: null,
                              child: Text('Unassigned'),
                            ),
                            ...state.advisers.map(
                              (adviser) => DropdownMenuItem<int?>(
                                value: _asInt(adviser['id']),
                                child: Text(
                                  '${adviser['name']} (${adviser['username']})',
                                ),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            setDialogState(() {
                              adviserId = value;
                            });
                          },
                        ),
                        const SizedBox(height: 16),
                      ] else
                        const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Members (${selectedMembers.length}/4)',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 260),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _line),
                        ),
                        child: ListView(
                          shrinkWrap: true,
                          children: state.students.map((student) {
                            final studentId = _asInt(student['id'])!;
                            final selected = selectedMembers.contains(
                              studentId,
                            );
                            return CheckboxListTile(
                              value: selected,
                              title: Text(
                                '${student['name']} (${student['username']})',
                              ),
                              subtitle: leaderId == studentId
                                  ? const Text('Team Leader')
                                  : null,
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    if (selectedMembers.length >= 4 &&
                                        !selected) {
                                      return;
                                    }
                                    selectedMembers.add(studentId);
                                    leaderId ??= studentId;
                                  } else {
                                    selectedMembers.remove(studentId);
                                    if (leaderId == studentId) {
                                      leaderId = selectedMembers.isEmpty
                                          ? null
                                          : selectedMembers.first;
                                    }
                                  }
                                });
                              },
                              secondary: selected
                                  ? IconButton(
                                      tooltip: 'Set as leader',
                                      icon: Icon(
                                        leaderId == studentId
                                            ? Icons.workspace_premium_rounded
                                            : Icons.circle_outlined,
                                        color: leaderId == studentId
                                            ? _gold
                                            : _muted,
                                      ),
                                      onPressed: () {
                                        setDialogState(() {
                                          leaderId = studentId;
                                        });
                                      },
                                    )
                                  : null,
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Select up to 4 members. Use the medal button to choose the leader.',
                          style: TextStyle(color: _muted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      selectedMembers.isEmpty ||
                          leaderId == null ||
                          name.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(dialogContext, true),
                  child: const Text('Create Team'),
                ),
              ],
            );
          },
        );
      },
    );

    if (!mounted || saved != true) {
      name.dispose();
      projectTitle.dispose();
      return;
    }

    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    if (!isCapstone) {
      adviserId = null;
    }

    if (isPitLead) {
      yearLevel = _pitLeadYear ?? yearLevel;
      level = '$yearLevel PIT';
    }

    final payload = {
      'name': name.text.trim(),
      'project_title': projectTitle.text.trim().isEmpty
          ? name.text.trim()
          : projectTitle.text.trim(),
      if (isPitLead) 'level': level,
      if (isPitLead) 'year_level': yearLevel,
      'leader_id': leaderId,
      'member_ids': selectedMembers.toList(),
      'adviser_id': isCapstone ? adviserId : null,
      'status': status,
    };

    name.dispose();
    projectTitle.dispose();

    await ref.read(studentTeamsProvider.notifier).addTeam(payload);
  }

  List<Map<String, dynamic>> _parseCsv(String csv) => parseTeamBulkCsvWithContext(
        csv,
        isCapstoneAdmin: _isCapstoneAdmin,
        pitLeadYear: _pitLeadYear,
      ).rows;

  String _projectTitle(Map<String, dynamic> team) {
    final title = team['project_title']?.toString();
    if (title != null && title.trim().isNotEmpty) {
      return title;
    }
    return team['name']?.toString() ?? '-';
  }

  String _defenseContext(Map<String, dynamic> team) {
    final context = team['defense_context'];
    if (context is Map) {
      if (context['is_pit'] == true || _teamIsPit(team)) {
        final label = context['event_label']?.toString() ?? '';
        final date = context['scheduled_date']?.toString() ?? '';
        if (label.isNotEmpty && date.isNotEmpty) {
          return '$label ($date)';
        }
        if (label.isNotEmpty) {
          return label;
        }
        return 'No PIT event scheduled';
      }
      final stage = context['current_stage']?.toString();
      if (stage != null && stage.isNotEmpty) {
        return stage;
      }
      final readyForStage = context['ready_for_stage']?.toString();
      if (readyForStage != null && readyForStage.isNotEmpty) {
        return readyForStage;
      }
    }
    if (context is String && context.trim().isNotEmpty) {
      return context;
    }
    return _teamIsPit(team) ? 'No PIT event scheduled' : 'No defense scheduled';
  }

  int _count(StudentTeamsState state, String key) {
    final value = state.counts[key];
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  Widget _unifiedSectionMetadataCard() {
    if (_section == null || _section!.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBBF7D0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hub_rounded, color: Color(0xFF16A34A), size: 20),
              const SizedBox(width: 8),
              Text(
                'Unified Section Integration: $_section',
                style: const TextStyle(
                  color: Color(0xFF14532D),
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('System Name: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF14532D))),
              Text(_systemName ?? 'Not specified', style: const TextStyle(fontSize: 13, color: Color(0xFF166534))),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Text('Project Manager: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF14532D))),
              Text(_projectManager ?? 'Not specified', style: const TextStyle(fontSize: 13, color: Color(0xFF166534))),
              const SizedBox(width: 6),
              if (_bulkPreview != null && _bulkPreview!['section_assignment'] != null) ...[
                if (_bulkPreview!['section_assignment']['project_manager_valid'] == true)
                  const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 15)
                else if (_bulkPreview!['section_assignment']['project_manager_error'] != null)
                  Tooltip(
                    message: _bulkPreview!['section_assignment']['project_manager_error'],
                    child: const Icon(Icons.error_outline_rounded, color: Colors.red, size: 15),
                  )
              ]
            ],
          ),
        ],
      ),
    );
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }

    showInfoToast(context, message);
  }

}

class _ColumnSpec {
  final String label;
  final double flex;

  const _ColumnSpec(this.label, this.flex);
}
