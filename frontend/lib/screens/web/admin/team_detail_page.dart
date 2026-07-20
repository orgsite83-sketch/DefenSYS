import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/api_config.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/student_teams_provider.dart';
import '../../../services/team_detail_provider.dart';
import '../../../services/auth_provider.dart';
import '../../../utils/pdf_viewer.dart';
import '../../../widgets/feedback_toast.dart';
import 'widgets/defensys_admin_shell.dart';
import 'grade_center_shared.dart';

class TeamDetailPage extends ConsumerStatefulWidget {
  const TeamDetailPage({
    super.key,
    required this.teamId,
    required this.onBack,
    required this.canManage,
    required this.isPitLead,
    this.pitLeadYear,
    this.onDeleted,
  });

  final int teamId;
  final VoidCallback onBack;
  final bool canManage;
  final bool isPitLead;
  final String? pitLeadYear;
  final VoidCallback? onDeleted;

  @override
  ConsumerState<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends ConsumerState<TeamDetailPage> {
  static const _ink = DefensysUi.textDark;
  static const _muted = DefensysUi.steelGrey;
  static const _maroon = DefensysUi.primaryMaroon;
  static const _gold = DefensysUi.accentGold;
  static const _red = Color(0xFFDC2626);
  static const _line = Color(0xFFE5E7EB);

  final _nameController = TextEditingController();
  final _projectTitleController = TextEditingController();
  final _sectionController = TextEditingController();

  String _status = 'Pending';
  int? _adviserId;
  int? _originalAdviserId;
  final _selectedMembers = <int>{};
  int? _leaderId;
  String _selectedDeliverableStage = '';
  int? _selectedReportIndex;
  bool _isEditing = false;
  String _studentFilter = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(teamDetailProvider(widget.teamId).notifier).load();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _projectTitleController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  void _syncFormFromTeam(Map<String, dynamic> team, List<String> statuses) {
    _nameController.text = team['name']?.toString() ?? '';
    _projectTitleController.text = team['project_title']?.toString() ?? '';
    _sectionController.text = team['section']?.toString() ?? '';
    _status = team['status']?.toString() ?? 'Pending';
    if (!statuses.contains(_status) && statuses.isNotEmpty) {
      _status = statuses.first;
    }
    _adviserId = _asInt(team['adviser_id']);
    _originalAdviserId = _adviserId;
    _selectedMembers
      ..clear()
      ..addAll(_readIntList(team['member_ids']));
    _leaderId =
        _asInt(team['leader_id']) ??
        (_selectedMembers.isNotEmpty ? _selectedMembers.first : null);
  }

  @override
  Widget build(BuildContext context) {
    final detailState = ref.watch(teamDetailProvider(widget.teamId));
    final team = detailState.team;

    if (detailState.isLoading && team == null) {
      return const Center(child: CircularProgressIndicator(color: _maroon));
    }

    if (team == null) {
      return Padding(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(null),
            const SizedBox(height: 24),
            Text(
              detailState.error ?? 'Team not found.',
              style: const TextStyle(color: _red),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: widget.onBack, child: const Text('Back')),
          ],
        ),
      );
    }

    if (_nameController.text.isEmpty && team['name'] != null) {
      _syncFormFromTeam(team, detailState.statuses);
    }

    final stageOptions = detailState.stageOptions;
    if (stageOptions.isNotEmpty &&
        !stageOptions.contains(_selectedDeliverableStage)) {
      _selectedDeliverableStage = stageOptions.first;
    } else if (stageOptions.isEmpty) {
      _selectedDeliverableStage = '';
    }

    ref.listen(teamDetailProvider(widget.teamId), (prev, next) {
      final msg = next.message;
      if (msg != null && msg.isNotEmpty && msg != prev?.message) {
        showSuccessToast(context, msg);
      }
      final error = next.error;
      if (error != null && error.isNotEmpty && error != prev?.error) {
        showErrorToast(context, error);
      }
    });

    final level = team['level']?.toString() ?? '';
    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    final tabCount = isCapstone ? 4 : 3;

    return DefaultTabController(
      length: tabCount,
      child: Padding(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(team),
            if (detailState.error != null) ...[
              const SizedBox(height: 12),
              Text(detailState.error!, style: const TextStyle(color: _red)),
            ],
            const SizedBox(height: 16),
            TabBar(
              labelColor: _maroon,
              unselectedLabelColor: _muted,
              indicatorColor: _maroon,
              isScrollable: true,
              tabs: [
                const Tab(text: 'Overview'),
                if (isCapstone) ...[
                  const Tab(text: 'Weekly Reports'),
                  const Tab(text: 'Deliverables'),
                  const Tab(text: 'Team Documents'),
                ] else ...[
                  const Tab(text: 'Grades & Events'),
                  const Tab(text: 'Deliverables'),
                ],
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                children: [
                  _buildOverviewTab(detailState, team),
                  if (isCapstone) ...[
                    _buildWeeklyReportsTab(detailState),
                    _buildDeliverablesTab(detailState, stageOptions),
                    _buildDocumentsTab(detailState),
                  ] else ...[
                    _buildGradesTab(detailState),
                    _buildDeliverablesTab(detailState, stageOptions),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(Map<String, dynamic>? team) {
    final title = team?['name']?.toString() ?? 'Team';
    final project = team?['project_title']?.toString() ?? '';

    return Row(
      children: [
        IconButton(
          tooltip: 'Back to teams',
          onPressed: widget.onBack,
          icon: const Icon(Icons.arrow_back_rounded, color: _maroon),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: DefensysUi.pageTitle),
              if (project.isNotEmpty)
                Text(project, style: DefensysUi.subtitle, maxLines: 2),
              if (!_isEditing)
                const Text(
                  'Team workspace — submissions and roster',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
            ],
          ),
        ),
        if (widget.canManage && !_isEditing)
          OutlinedButton.icon(
            onPressed: () => setState(() => _isEditing = true),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit team'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _maroon,
              side: const BorderSide(color: _maroon),
            ),
          ),
        if (widget.canManage && _isEditing) ...[
          TextButton(
            onPressed: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? null
                : _cancelEditing,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? null
                : _saveOverview,
            style: ElevatedButton.styleFrom(
              backgroundColor: _maroon,
              foregroundColor: _gold,
            ),
            child: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save Changes'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? null
                : _confirmDelete,
            icon: const Icon(Icons.delete_outline, size: 18, color: _red),
            label: const Text('Delete', style: TextStyle(color: _red)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: _line),
            ),
          ),
        ],
      ],
    );
  }

  void _cancelEditing() {
    final detailState = ref.read(teamDetailProvider(widget.teamId));
    final team = detailState.team;
    if (team != null) {
      _syncFormFromTeam(team, detailState.statuses);
    }
    setState(() {
      _isEditing = false;
      _studentFilter = '';
    });
  }

  Widget _buildOverviewTab(
    TeamDetailState detailState,
    Map<String, dynamic> team,
  ) {
    if (widget.canManage && _isEditing) {
      return _buildOverviewEdit(detailState, team);
    }
    return _buildOverviewView(detailState, team);
  }

  Widget _buildTeamStatusBadge(String status) {
    final cleanStatus = status.trim().toLowerCase();
    Color color;
    IconData icon;

    switch (cleanStatus) {
      case 'approved':
      case 'passed':
        color = const Color(0xFF10B981); // Emerald Green
        icon = Icons.check_circle_outline_rounded;
        break;
      case 'failed':
        color = const Color(0xFFEF4444); // Red
        icon = Icons.cancel_outlined;
        break;
      case 'delayed/extended':
      case 'delayed':
      case 'extended':
        color = const Color(0xFF8B5CF6); // Purple
        icon = Icons.update_rounded;
        break;
      case 'pending':
      default:
        color = const Color(0xFFF59E0B); // Amber
        icon = Icons.hourglass_empty_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: 4),
          Text(
            status.toUpperCase(),
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetaText(String label, String value, {required IconData icon}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: _muted),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: _muted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: _muted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: _muted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _ink,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLeftOverviewColumn(
    Map<String, dynamic> team,
    bool isCapstone,
    String programLabel,
    String adviserName,
  ) {
    final project = team['project_title']?.toString() ?? '—';
    final status = team['status']?.toString() ?? 'Pending';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Project Overview Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'PROJECT INFORMATION',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: _muted,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          project,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  _buildTeamStatusBadge(status),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: _line, height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetaText('Program', programLabel, icon: Icons.school_outlined),
                  ),
                  if (!isCapstone)
                    Expanded(
                      child: _buildMetaText('Section', team['section']?.toString() ?? '—', icon: Icons.class_outlined),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Classroom & Admin details Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.badge_outlined, size: 18, color: _maroon),
                  SizedBox(width: 8),
                  Text(
                    'CLASSROOM DETAILS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: _ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (isCapstone) ...[
                _buildInfoRow(
                  Icons.class_outlined,
                  'Section',
                  team['section']?.toString() ?? '—',
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.person_outline,
                  'Instructor',
                  team['instructor_name']?.toString() ?? 'No instructor assigned',
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.computer_outlined,
                  'System Name',
                  team['system_name']?.toString() ?? '—',
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.manage_accounts_outlined,
                  'Section Project Manager',
                  team['project_manager_name']?.toString() ?? '—',
                ),
              ] else ...[
                _buildInfoRow(
                  Icons.computer_outlined,
                  'System Name',
                  team['system_name']?.toString() ?? '—',
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  Icons.manage_accounts_outlined,
                  'Section Project Manager',
                  team['project_manager_name']?.toString() ?? '—',
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRightOverviewColumn(
    TeamDetailState detailState,
    Map<String, dynamic> team,
    bool isCapstone,
    List<Map<String, dynamic>> members,
    int? leaderId,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Roster Card
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.people_alt_outlined, size: 18, color: _maroon),
                  const SizedBox(width: 8),
                  Text(
                    'TEAM ROSTER (${members.length}/4)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: _ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (members.isEmpty)
                const Text(
                  'No members assigned.',
                  style: TextStyle(color: _muted, fontSize: 13),
                )
              else
                ...members.map((student) {
                  final studentId = _asInt(student['id']);
                  final isLeader = studentId == leaderId;
                  final isEnrolled = student['is_enrolled'] != false;
                  final name = student['name']?.toString() ?? 'Unknown Student';
                  final username = student['username']?.toString() ?? '';
                  final initials = name.isNotEmpty
                      ? name.trim().split(' ').map((e) => e[0]).take(2).join().toUpperCase()
                      : '?';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFF3F4F6)),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: isLeader ? _gold.withValues(alpha: 0.2) : _maroon.withValues(alpha: 0.1),
                          child: Text(
                            initials,
                            style: TextStyle(
                              color: isLeader ? const Color(0xFFB45309) : _maroon,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: _ink,
                                ),
                              ),
                              if (username.isNotEmpty)
                                Text(
                                  username,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 11.5,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (isLeader)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFFDE68A)),
                                ),
                                child: const Text(
                                  'Leader',
                                  style: TextStyle(
                                    color: Color(0xFFD97706),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            if (!isEnrolled) ...[
                              if (isLeader) const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFFFCA5A5)),
                                ),
                                child: const Text(
                                  'Not Enrolled',
                                  style: TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        ),
        if (isCapstone && !widget.isPitLead) ...[
          const SizedBox(height: 20),
          // Adviser Assignment / History Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.workspace_premium_outlined, size: 18, color: _maroon),
                    SizedBox(width: 8),
                    Text(
                      'PROJECT ADVISER',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                        color: _ink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildInfoRow(
                  Icons.person_pin_rounded,
                  'Current Adviser',
                  team['adviser_name']?.toString() ??
                      _adviserLabel(_asInt(team['adviser_id']), detailState.advisers),
                ),
                const SizedBox(height: 20),
                _adviserHistorySection(detailState.adviserHistory),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOverviewView(
    TeamDetailState detailState,
    Map<String, dynamic> team,
  ) {
    final level = team['level']?.toString() ?? '';
    final yearLevel = team['year_level']?.toString() ?? '3rd Year';
    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    final programLabel = isCapstone
        ? 'Capstone · $yearLevel'
        : '$yearLevel PIT';
    final adviserName =
        team['adviser_name']?.toString() ??
        _adviserLabel(_asInt(team['adviser_id']), detailState.advisers);

    final members = (team['members'] as List? ?? const [])
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final leaderId = _asInt(team['leader_id']);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 850;

        final leftColumn = _buildLeftOverviewColumn(team, isCapstone, programLabel, adviserName);
        final rightColumn = _buildRightOverviewColumn(detailState, team, isCapstone, members, leaderId);

        if (isWide) {
          return SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: leftColumn,
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: rightColumn,
                ),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                leftColumn,
                const SizedBox(height: 24),
                rightColumn,
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildOverviewEdit(
    TeamDetailState detailState,
    Map<String, dynamic> team,
  ) {
    final level = team['level']?.toString() ?? '';
    final yearLevel = team['year_level']?.toString() ?? '3rd Year';
    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    final statusOptions = detailState.statuses.isEmpty
        ? const ['Pending', 'Approved', 'Failed', 'Delayed/Extended']
        : detailState.statuses;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 850;

        final leftColumn = Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TEAM METADATA',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Team Name',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _projectTitleController,
                decoration: const InputDecoration(
                  labelText: 'Project Title',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Program',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                child: Text(
                  isCapstone ? 'Capstone · $yearLevel' : '$yearLevel PIT',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: statusOptions.contains(_status)
                    ? _status
                    : statusOptions.first,
                decoration: const InputDecoration(
                  labelText: 'Team Result',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
                items: statusOptions
                    .map(
                      (item) => DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _status = value ?? _status),
              ),
              if (!isCapstone) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _sectionController,
                  decoration: const InputDecoration(
                    labelText: 'Section',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ],
              if (!widget.isPitLead && isCapstone) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  value: _adviserId,
                  decoration: const InputDecoration(
                    labelText: 'Adviser',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ...detailState.advisers.map(
                      (adviser) => DropdownMenuItem<int?>(
                        value: _asInt(adviser['id']),
                        child: Text(
                          '${adviser['name']} (${adviser['username']})',
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() => _adviserId = value),
                ),
              ],
            ],
          ),
        );

        final rightColumn = Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ROSTER SELECTION (${_selectedMembers.length}/4)',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: _ink,
                    ),
                  ),
                  const Icon(Icons.person_add_alt_1_outlined, size: 18, color: _maroon),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search Students',
                  hintText: 'Type name or student ID...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (val) {
                  setState(() {
                    _studentFilter = val;
                  });
                },
              ),
              const SizedBox(height: 12),
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _line),
                ),
                child: Builder(
                  builder: (context) {
                    final filteredStudents = detailState.students.where((student) {
                      final studentId = _asInt(student['id']);
                      if (studentId != null && _selectedMembers.contains(studentId)) {
                        return true;
                      }
                      if (_studentFilter.trim().isEmpty) return true;
                      final name = student['name']?.toString().toLowerCase() ?? '';
                      final username = student['username']?.toString().toLowerCase() ?? '';
                      final query = _studentFilter.toLowerCase();
                      return name.contains(query) || username.contains(query);
                    }).toList();

                    if (filteredStudents.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'No matching students found.',
                            style: TextStyle(color: _muted, fontSize: 13),
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      shrinkWrap: true,
                      itemCount: filteredStudents.length,
                      itemBuilder: (context, index) {
                        final student = filteredStudents[index];
                        final studentId = _asInt(student['id'])!;
                        final selected = _selectedMembers.contains(studentId);
                        return Material(
                          color: Colors.transparent,
                          child: CheckboxListTile(
                            value: selected,
                            activeColor: _maroon,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  if (_selectedMembers.length >= 4 && !selected) {
                                    showValidationToast(context, 'A team can have a maximum of 4 members.');
                                    return;
                                  }
                                  _selectedMembers.add(studentId);
                                  _leaderId ??= studentId;
                                } else {
                                  _selectedMembers.remove(studentId);
                                  if (_leaderId == studentId) {
                                    _leaderId = _selectedMembers.isEmpty
                                        ? null
                                        : _selectedMembers.first;
                                  }
                                }
                              });
                            },
                            title: Text(
                              '${student['name']} (${student['username']})',
                              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                            ),
                            subtitle: _leaderId == studentId
                                ? const Text(
                                    'Team Leader',
                                    style: TextStyle(
                                      color: _maroon,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                            secondary: selected
                                ? IconButton(
                                    tooltip: 'Set as leader',
                                    icon: Icon(
                                      _leaderId == studentId
                                          ? Icons.workspace_premium_rounded
                                          : Icons.circle_outlined,
                                      color: _leaderId == studentId ? _gold : _muted,
                                    ),
                                    onPressed: () =>
                                        setState(() => _leaderId = studentId),
                                  )
                                : null,
                          ),
                        );
                      },
                    );
                  }
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Select up to 4 members. Use the medal button to designate the team leader.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              if (!widget.isPitLead && isCapstone) ...[
                const SizedBox(height: 24),
                const Divider(color: _line),
                const SizedBox(height: 12),
                _adviserHistorySection(detailState.adviserHistory),
              ],
            ],
          ),
        );

        if (isWide) {
          return SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: leftColumn,
                ),
                const SizedBox(width: 24),
                Expanded(
                  flex: 2,
                  child: rightColumn,
                ),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                leftColumn,
                const SizedBox(height: 24),
                rightColumn,
              ],
            ),
          );
        }
      },
    );
  }

  Widget _buildWeeklyReportsTab(TeamDetailState detailState) {
    final reports = detailState.weeklyReports;

    if (reports.isEmpty) {
      return _emptyTab('No weekly progress reports submitted yet.');
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 280,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              final selected = _selectedReportIndex == index;
              return ListTile(
                selected: selected,
                selectedTileColor: const Color(0xFFF3F4F6),
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFE5E7EB),
                  child: Text(
                    '${report['week_number'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ),
                title: Text('Week ${report['week_number'] ?? ''}'),
                subtitle: Text(report['report_date']?.toString() ?? ''),
                onTap: () => setState(() => _selectedReportIndex = index),
              );
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _selectedReportIndex == null
              ? _emptyTab('Select a report to preview.')
              : _weeklyReportPreview(reports[_selectedReportIndex!]),
        ),
      ],
    );
  }

  Widget _weeklyReportPreview(Map<String, dynamic> report) {
    final reportFile = report['report_file'] as String?;
    final hasFile = reportFile != null && reportFile.isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Week ${report['week_number'] ?? ''}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text('Date: ${report['report_date'] ?? '—'}'),
          Text('Submitted by: ${report['student_name'] ?? '—'}'),
          const SizedBox(height: 16),
          if (hasFile)
            ElevatedButton.icon(
              onPressed: () => _viewWeeklyReportFile(report),
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('View report file'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _maroon,
                foregroundColor: _gold,
              ),
            )
          else
            const Text(
              'Legacy structured report (no file attachment).',
              style: TextStyle(color: _muted),
            ),
        ],
      ),
    );
  }

  Widget _buildDeliverablesTab(
    TeamDetailState detailState,
    List<String> stageOptions,
  ) {
    final level = detailState.team?['level']?.toString() ?? '';
    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    final deliverableTeam = detailState.deliverableTeam;
    if (deliverableTeam == null) {
      return _emptyTab(
        isCapstone
            ? 'No capstone deliverable record for this team (non-capstone or not loaded).'
            : 'No deliverables record for this team.',
      );
    }
    if (stageOptions.isEmpty) {
      return _emptyTab(isCapstone ? 'No defense stages setup yet.' : 'No PIT events setup yet.');
    }

    final stages = (deliverableTeam['stages'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final stage = stages.firstWhere(
      (item) => item['stage_label']?.toString() == _selectedDeliverableStage,
      orElse: () => stages.isNotEmpty ? stages.first : <String, dynamic>{},
    );
    final deliverables = (stage['deliverables'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
    final pre = deliverables.where((d) => d['type'] == 'pre').toList();
    final vault = deliverables.where((d) => d['type'] == 'post' || d['type'] == 'vault').toList();

    return SingleChildScrollView(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: stageOptions.map((label) {
                final active = label == _selectedDeliverableStage;
                return ChoiceChip(
                  label: Text(label),
                  selected: active,
                  onSelected: (_) =>
                      setState(() => _selectedDeliverableStage = label),
                  selectedColor: _maroon.withValues(alpha: 0.12),
                  labelStyle: TextStyle(
                    color: active ? _maroon : _ink,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'Pre-Defense Requirements',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            ...pre.map((item) => _deliverableRow(item)),
            const SizedBox(height: 20),
            const Text(
              'Post-Defense Submissions',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
            const SizedBox(height: 8),
            if (stage['vault_unlocked'] != true)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Post-Defense items unlock after the defense for this stage is completed.',
                  style: TextStyle(color: _muted, fontSize: 12.5),
                ),
              )
            else
              ...vault.map((item) => _deliverableRow(item)),
          ],
        ),
      ),
    );
  }

  Widget _deliverableRow(Map<String, dynamic> item) {
    final uploaded = item['uploaded'] == true;
    final submission = Map<String, dynamic>.from(
      item['submission'] as Map? ?? const {},
    );
    final fileUrl = submission['file_url']?.toString();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          Icon(
            uploaded ? Icons.check_circle : Icons.radio_button_unchecked,
            color: uploaded ? const Color(0xFF10B981) : _muted,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item['label']?.toString() ?? '',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (uploaded)
                  Text(
                    '${submission['file_name'] ?? ''} · ${submission['uploaded_by_name'] ?? ''}',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
              ],
            ),
          ),
          if (item['required'] == true)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Required',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
              ),
            ),
          if (uploaded && fileUrl != null && fileUrl.isNotEmpty) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Open file',
              onPressed: () => _openMediaUrl(fileUrl),
              icon: const Icon(Icons.open_in_new, size: 20),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDocumentsTab(TeamDetailState detailState) {
    final docs = detailState.documents;
    if (docs.isEmpty) {
      return _emptyTab('No team documents uploaded yet.');
    }

    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _line),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text('FILE', style: DefensysUi.tableHeader),
                  ),
                  Expanded(child: Text('TYPE', style: DefensysUi.tableHeader)),
                  Expanded(child: Text('DATE', style: DefensysUi.tableHeader)),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            const Divider(height: 1, color: _line),
            ...docs.map((doc) {
              final id = _asInt(doc['id']);
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        doc['file_name']?.toString() ?? '—',
                        style: DefensysUi.tableCell,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        doc['document_type']?.toString() ?? 'other',
                        style: DefensysUi.tableCell,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        _formatDate(doc['uploaded_at']),
                        style: DefensysUi.tableCell,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Download',
                      onPressed: id == null
                          ? null
                          : () => _downloadTeamDocument(id),
                      icon: const Icon(Icons.download_outlined, color: _maroon),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _emptyTab(String message) {
    return Center(
      child: Text(message, style: const TextStyle(color: _muted, fontSize: 14)),
    );
  }

  Widget _adviserHistorySection(List<Map<String, dynamic>> rows) {
    const headStyle = TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.8,
      color: Color(0xFF9CA3AF),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Adviser History',
          style: TextStyle(
            color: _ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Past and current advisers for this team.',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const Text(
            'No adviser changes recorded yet.',
            style: TextStyle(color: _muted, fontSize: 12.5),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _line),
            ),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text('ADVISER', style: headStyle),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('ASSIGNED', style: headStyle),
                      ),
                      Expanded(flex: 2, child: Text('ENDED', style: headStyle)),
                      Expanded(
                        flex: 2,
                        child: Text('CHANGED BY', style: headStyle),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: _line),
                ...rows.map((row) {
                  final isCurrent = row['is_current'] == true;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: const BoxDecoration(
                      border: Border(bottom: BorderSide(color: _line)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                row['adviser_name']?.toString() ?? 'Unassigned',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (isCurrent)
                                const Text(
                                  'Current',
                                  style: TextStyle(
                                    color: _maroon,
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(_formatDate(row['assigned_at'])),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            row['ended_at'] != null
                                ? _formatDate(row['ended_at'])
                                : '—',
                          ),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            row['assigned_by_name']?.toString() ?? '—',
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _saveOverview() async {
    if (_selectedMembers.isEmpty || _leaderId == null) {
      showValidationToast(context, 'Select at least one member and a leader.');
      return;
    }

    final detailState = ref.read(teamDetailProvider(widget.teamId));
    final team = detailState.team;
    if (team == null) return;

    final level = team['level']?.toString() ?? '';
    final isCapstone = level.toUpperCase().contains('CAPSTONE');
    var adviserId = isCapstone && !widget.isPitLead ? _adviserId : null;

    String? adviserChangeReason;
    if (widget.canManage &&
        isCapstone &&
        !widget.isPitLead &&
        _originalAdviserId != adviserId) {
      final reason = await _confirmAdviserChange(
        teamName: _nameController.text.trim(),
        fromAdviserId: _originalAdviserId,
        toAdviserId: adviserId,
        advisers: detailState.advisers,
      );
      if (!mounted) return;
      if (reason == null) return;
      adviserChangeReason = reason;
    }

    final payload = {
      'name': _nameController.text.trim(),
      'project_title': _projectTitleController.text.trim().isEmpty
          ? _nameController.text.trim()
          : _projectTitleController.text.trim(),
      'leader_id': _leaderId,
      'member_ids': _selectedMembers.toList(),
      'adviser_id': adviserId,
      'status': _status,
      'section': _sectionController.text.trim(),
      if (adviserChangeReason != null && adviserChangeReason.isNotEmpty)
        'adviser_change_reason': adviserChangeReason,
    };

    final ok = await ref
        .read(teamDetailProvider(widget.teamId).notifier)
        .save(payload);
    if (ok && mounted) {
      setState(() {
        _originalAdviserId = adviserId;
        _isEditing = false;
        _studentFilter = '';
      });
      await ref.read(studentTeamsProvider.notifier).fetchTeams();
    }
  }

  Future<void> _confirmDelete() async {
    final team = ref.read(teamDetailProvider(widget.teamId)).team;
    final name = team?['name']?.toString() ?? 'this team';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Delete Team'),
        content: Text('Delete $name? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final deleted = await ref
        .read(studentTeamsProvider.notifier)
        .deleteTeam(widget.teamId);
    if (deleted && mounted) {
      widget.onDeleted?.call();
      widget.onBack();
      return;
    }

    if (mounted) {
      final teamsState = ref.read(studentTeamsProvider);
      final errorMsg = teamsState.error;
      if (errorMsg != null && (errorMsg.contains('defense schedules') || errorMsg.contains('grade records'))) {
        final user = ref.read(authProvider).user;
        final isAdmin = user?['role']?.toString() == 'admin';

        if (!isAdmin) {
          showDialog(
            context: context,
            builder: (dialogContext) => AlertDialog(
              surfaceTintColor: Colors.transparent,
              title: const Text('Delete Blocked'),
              content: const Text('Only system administrators can delete teams with active schedules or grades.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }

        final forceDeleted = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return _ForceDeleteDialog(
              teamName: name,
              warningMessage: errorMsg,
            );
          },
        );

        if (forceDeleted == true && mounted) {
          final forceDone = await ref
              .read(studentTeamsProvider.notifier)
              .deleteTeam(widget.teamId, force: true);
          if (forceDone && mounted) {
            widget.onDeleted?.call();
            widget.onBack();
          }
        }
      }
    }
  }

  Future<String?> _confirmAdviserChange({
    required String teamName,
    required int? fromAdviserId,
    required int? toAdviserId,
    required List<Map<String, dynamic>> advisers,
  }) async {
    final reasonCtrl = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        surfaceTintColor: Colors.transparent,
        title: const Text('Change project adviser?'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team: $teamName',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text('From: ${_adviserLabel(fromAdviserId, advisers)}'),
              Text('To: ${_adviserLabel(toAdviserId, advisers)}'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                decoration: const InputDecoration(
                  labelText: 'Reason (optional)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reasonCtrl.text.trim()),
            child: const Text('Confirm change'),
          ),
        ],
      ),
    );
    reasonCtrl.dispose();
    return result;
  }

  String _adviserLabel(int? id, List<Map<String, dynamic>> advisers) {
    if (id == null) return 'Unassigned';
    for (final adviser in advisers) {
      if (_asInt(adviser['id']) == id) {
        return '${adviser['name']} (${adviser['username']})';
      }
    }
    return 'Unknown adviser';
  }

  Future<void> _viewWeeklyReportFile(Map<String, dynamic> report) async {
    final fileUrl = report['file_url'] as String?;
    final reportFile = report['report_file'] as String?;
    final fileRef = (fileUrl != null && fileUrl.isNotEmpty)
        ? fileUrl
        : reportFile;
    if (fileRef == null || fileRef.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          const Center(child: CircularProgressIndicator(color: _maroon)),
    );

    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileRef);
      if (mounted) Navigator.pop(context);

      if (mounted) {
        await viewPdfInDialog(
          context: context,
          pdfBytes: bytes,
          fileName: (reportFile ?? fileRef).split('/').last,
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        showErrorToast(context, 'Error opening file: $e');
      }
    }
  }

  Future<void> _openMediaUrl(String fileUrl) async {
    if (!mounted) return;
    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileUrl);
      if (!mounted) return;
      final name = fileUrl.split('/').last.toLowerCase();
      if (name.endsWith('.pdf')) {
        await viewPdfInDialog(
          context: context,
          pdfBytes: bytes,
          fileName: fileUrl.split('/').last,
        );
      } else {
        showValidationToast(
          context,
          'File preview is only available for PDFs.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, 'Error opening file: $e');
    }
  }

  Future<void> _downloadTeamDocument(int docId) async {
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(Uri.parse('${ApiConfig.teamDocumentsUrl}/$docId/download/'));
      if (!mounted) return;
      if (response.statusCode == 200) {
        showSuccessToast(context, 'Document downloaded.');
      } else {
        showErrorToast(context, 'Download failed (${response.statusCode})');
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Download error: $e');
      }
    }
  }

  String _formatDate(dynamic value) {
    final raw = value?.toString() ?? '';
    if (raw.isEmpty) return '—';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return raw.length > 10 ? raw.substring(0, 10) : raw;
    final local = dt.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  List<int> _readIntList(dynamic value) {
    if (value is! List) return [];
    return value.map(_asInt).whereType<int>().toList();
  }

  int? _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }

  Widget _buildGradesTab(TeamDetailState detailState) {
    final grades = detailState.grades;
    if (grades.isEmpty) {
      return _emptyTab('No grades or evaluation events recorded yet.');
    }

    return ListView.separated(
      itemCount: grades.length,
      separatorBuilder: (context, index) => const SizedBox(height: 24),
      itemBuilder: (context, index) {
        final grade = grades[index];
        final breakdowns = parseBreakdowns(grade);
        final peerGrades = parsePeerPerStudent(grade);

        final panelBreakdowns = breakdowns.where((b) => b['evaluation_type'] == 'panel').toList();
        final peerBreakdowns = breakdowns.where((b) => b['evaluation_type'] == 'peer').toList();

        final finalScore = asDouble(grade['final_grade']);

        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Event Name & Status Chip
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          grade['stage_label']?.toString() ?? 'Grade Evaluation',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: _maroon,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Formula: Panel ${weightText(grade, 'panel')}% + Peer ${weightText(grade, 'peer')}% = Final Grade',
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  gradeStatusChipWidget(grade),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: _line),
              const SizedBox(height: 16),

              // KPI / Scores Overview Row
              Row(
                children: [
                  Expanded(
                    child: _buildScoreStatCard(
                      title: 'Final Grade',
                      value: finalScore == null ? '--' : finalScore.toStringAsFixed(2),
                      color: finalScore == null
                          ? _muted
                          : finalScore >= 75
                              ? const Color(0xFF10B981)
                              : _red,
                      isBold: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildScoreStatCard(
                      title: 'Panel Score (${weightText(grade, 'panel')}%)',
                      value: scoreInput(grade['panel_score']).isEmpty
                          ? 'Pending'
                          : scoreInput(grade['panel_score']),
                      color: _ink,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildScoreStatCard(
                      title: 'Peer Score (${weightText(grade, 'peer')}%)',
                      value: scoreInput(grade['peer_score']).isEmpty
                          ? 'Pending'
                          : scoreInput(grade['peer_score']),
                      color: _ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Peer Scores Per Student
              if (peerGrades.isNotEmpty) ...[
                const Text(
                  'Peer Scores per Student',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _line),
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text('STUDENT', style: DefensysUi.tableHeader),
                            ),
                            Expanded(
                              child: Text('AVERAGE', style: DefensysUi.tableHeader, textAlign: TextAlign.right),
                            ),
                            Expanded(
                              child: Text('PEER GRADE', style: DefensysUi.tableHeader, textAlign: TextAlign.right),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: _line),
                      ...peerGrades.map((pg) {
                        final avg = asDouble(pg['average_score']);
                        final norm = asDouble(pg['normalized_score']);
                        final maxS = asDouble(pg['max_score']) ?? 10.0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${pg['student_name']} (${pg['username']})',
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  avg == null ? '—' : '${avg.toStringAsFixed(2)} / ${maxS.toStringAsFixed(0)}',
                                  style: DefensysUi.tableCell,
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  norm == null ? 'Pending' : norm.toStringAsFixed(2),
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.bold,
                                    color: norm == null ? _muted : _ink,
                                  ),
                                  textAlign: TextAlign.right,
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Criterion Breakdowns
              if (panelBreakdowns.isNotEmpty || peerBreakdowns.isNotEmpty) ...[
                const Text(
                  'Criterion Score Breakdowns',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
                const SizedBox(height: 12),
                if (panelBreakdowns.isNotEmpty)
                  breakdownSectionWidget('panel', panelBreakdowns),
                if (peerBreakdowns.isNotEmpty)
                  breakdownSectionWidget('peer', peerBreakdowns),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildScoreStatCard({
    required String title,
    required String value,
    required Color color,
    bool isBold = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _muted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ForceDeleteDialog extends StatefulWidget {
  final String teamName;
  final String warningMessage;

  const _ForceDeleteDialog({
    required this.teamName,
    required this.warningMessage,
  });

  @override
  State<_ForceDeleteDialog> createState() => _ForceDeleteDialogState();
}

class _ForceDeleteDialogState extends State<_ForceDeleteDialog> {
  final _controller = TextEditingController();
  bool _isValid = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_checkValidity);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _checkValidity() {
    setState(() {
      _isValid = _controller.text.trim() == widget.teamName.trim();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      surfaceTintColor: Colors.transparent,
      title: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: Colors.red, size: 28),
          SizedBox(width: 8),
          Text('Force Delete Team'),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.warningMessage,
              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
            ),
            const SizedBox(height: 12),
            const Text(
              'Force-deleting will permanently erase all associated grades, scores, and peer evaluations. This action cannot be undone.',
            ),
            const SizedBox(height: 16),
            Text(
              'To confirm, type the team name: ${widget.teamName}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                hintText: 'Enter team name',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          onPressed: _isValid ? () => Navigator.pop(context, true) : null,
          child: const Text('Force Delete'),
        ),
      ],
    );
  }
}
