import 'package:defensys/theme/defensys_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../config/api_config.dart';
import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/authenticated_client.dart';
import '../../../../services/student_teams_provider.dart';
import '../../../../services/team_detail_provider.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/app/data_refresh_provider.dart';
import '../../../../utils/universal_file_viewer.dart';
import '../../../../toasts/feedback_toast.dart';
import '../../../../widgets/widgets.dart';
import '../../../../widgets/repository/proposal_title_summary.dart';
import '../../../../widgets/repository/shared_concept_review.dart';
import '../widgets/defensys_admin_shell.dart';
import '../grade_center_shared.dart';
import 'academic_progress_card.dart';
import 'team_progress_tabs.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import '../../../../widgets/academic/student_capstone_history.dart';

class TeamDetailPage extends ConsumerStatefulWidget {
  const TeamDetailPage({
    super.key,
    required this.teamId,
    required this.onBack,
    required this.canManage,
    required this.isPitLead,
    this.pitLeadYear,
    this.onDeleted,
    this.initialDeliverableStage,
    this.initialTab,
    this.initialEvent,
  });

  final int teamId;
  final VoidCallback onBack;
  final bool canManage;
  final bool isPitLead;
  final String? pitLeadYear;
  final VoidCallback? onDeleted;
  final String? initialDeliverableStage;
  final String? initialTab;
  final String? initialEvent;

  @override
  ConsumerState<TeamDetailPage> createState() => _TeamDetailPageState();
}

class _TeamDetailPageState extends ConsumerState<TeamDetailPage> {
  Color get _ink => DefensysTokens.textPrimaryOf(context);
  Color get _muted => DefensysTokens.textSecondaryOf(context);
  static const _gold = DefensysUi.accentGold;
  static const _red = Color(0xFFDC2626);
  Color get _line => DefensysTokens.borderOf(context);

  final _nameController = TextEditingController();
  final _projectTitleController = TextEditingController();
  final _sectionController = TextEditingController();

  String _status = 'Pending';
  int? _adviserId;
  int? _originalAdviserId;
  final _selectedMembers = <int>{};
  int? _leaderId;
  String _selectedDeliverableStage = '';
  int _activeTab = 0;
  bool _isEditing = false;
  String _studentFilter = '';
  bool _refreshAfterEvaluation = false;
  int _teamRevision = 0;

  @override
  void initState() {
    super.initState();
    _selectedDeliverableStage =
        widget.initialEvent ?? widget.initialDeliverableStage ?? '';
    _activeTab = switch (widget.initialTab) {
      'academic-progress' || 'event-progress' => 2,
      'deliverables' || 'weekly-reports' || 'documents' => 1,
      _ => widget.initialDeliverableStage == null ? 0 : 1,
    };
    _teamRevision = ref.read(dataRefreshProvider)[DataArea.teams] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final notifier = ref.read(teamDetailProvider(widget.teamId).notifier);
      if (widget.initialEvent != null ||
          widget.initialDeliverableStage != null) {
        notifier.selectEvent(
          widget.initialEvent ?? widget.initialDeliverableStage!,
        );
      } else {
        notifier.load();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TeamDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab &&
        widget.initialTab != null) {
      _activeTab = switch (widget.initialTab) {
        'academic-progress' || 'event-progress' => 2,
        'deliverables' || 'weekly-reports' || 'documents' => 1,
        _ => 0,
      };
    }
    final selected = widget.initialEvent ?? widget.initialDeliverableStage;
    if (selected != null && selected != _selectedDeliverableStage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _selectStage(selected);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isActive = TickerMode.of(context);
    final revision = ref.read(dataRefreshProvider)[DataArea.teams] ?? 0;
    if (!isActive || (!_refreshAfterEvaluation && revision == _teamRevision)) {
      return;
    }
    _refreshAfterEvaluation = false;
    _teamRevision = revision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && TickerMode.of(context)) {
        ref.read(teamDetailProvider(widget.teamId).notifier).load();
      }
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
      return Center(
        child: CircularProgressIndicator(
          color: DefensysTokens.maroonOf(context),
        ),
      );
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
              style: TextStyle(color: _red),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: widget.onBack, child: Text('Back')),
          ],
        ),
      );
    }

    if (_nameController.text.isEmpty && team['name'] != null) {
      _syncFormFromTeam(team, detailState.statuses);
    }

    final level = team['level']?.toString() ?? '';
    final isCapstone = level.toUpperCase().contains('CAPSTONE');

    final teamStages =
        (detailState.deliverableTeam?['stages'] as List? ?? const [])
            .whereType<Map>()
            .map((s) => s['stage_label']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();
    final eventLabels = detailState.events
        .map((e) => '${e['event_name']}')
        .toList();
    final stageOptions = !isCapstone && eventLabels.isNotEmpty
        ? eventLabels
        : teamStages.isNotEmpty
        ? teamStages
        : detailState.stageOptions;
    if (!isCapstone &&
        !detailState.isLoading &&
        detailState.selectedEvent != null) {
      _selectedDeliverableStage = detailState.selectedEvent!;
    }
    final currentStage = detailState.deliverableTeam?['current_stage']
        ?.toString();
    if (stageOptions.isNotEmpty) {
      if (_selectedDeliverableStage.isEmpty ||
          !stageOptions.contains(_selectedDeliverableStage)) {
        if (currentStage != null &&
            currentStage.isNotEmpty &&
            stageOptions.contains(currentStage)) {
          _selectedDeliverableStage = currentStage;
        } else {
          _selectedDeliverableStage = stageOptions.first;
        }
      }
    } else {
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

    ref.listen(dataRefreshProvider, (previous, next) {
      if (previous?[DataArea.deliverables] != next[DataArea.deliverables]) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && TickerMode.of(context)) _reload();
        });
      }
    });

    return DefensysShadcnScope(
      child: Padding(
        padding: DefensysUi.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(team),
            if (detailState.error != null)
              TeamDetailNotice(message: detailState.error!, onRetry: _reload),
            if (!isCapstone && stageOptions.isNotEmpty) ...[
              const SizedBox(height: 16),
              TeamContextSelect(
                labels: stageOptions,
                value: _selectedDeliverableStage,
                label: 'PIT event',
                enabled: !_isEditing && !detailState.isLoading,
                onChanged: _selectStage,
              ),
            ],
            const SizedBox(height: 16),
            ShadTabs<int>(
              scrollable: true,
              key: ValueKey('team-detail-tabs-$_activeTab'),
              value: _activeTab,
              onChanged: (tab) => setState(() => _activeTab = tab),
              tabs: [
                _teamTab(0, 'Overview'),
                _teamTab(1, 'Deliverables'),
                _teamTab(
                  2,
                  isCapstone ? 'Academic Progress' : 'Event Progress',
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (detailState.isLoading) ...[
              const ShadProgress(),
              const SizedBox(height: 12),
            ],
            Expanded(
              child:
                  !isCapstone &&
                      detailState.isLoading &&
                      detailState.selectedEvent != null &&
                      detailState.selectedEvent != _selectedDeliverableStage
                  ? const TeamDetailNotice(message: 'Loading event details?')
                  : switch (_activeTab) {
                      1 => _buildDeliverablesTab(detailState, stageOptions),
                      2 =>
                        isCapstone
                            ? _buildAcademicProgressTab(detailState)
                            : PitEventProgressTab(
                                state: detailState,
                                eventName: _selectedDeliverableStage,
                                onViewDeliverables: () =>
                                    setState(() => _activeTab = 1),
                                onViewEvaluation: _openEvaluation,
                                onRetry: _reload,
                              ),
                      _ => _buildOverviewTab(detailState, team),
                    },
            ),
          ],
        ),
      ),
    );
  }

  ShadTab<int> _teamTab(int value, String label) => ShadTab<int>(
    value: value,
    flex: 0,
    selectedForegroundColor: DefensysTokens.maroonTextOf(context),
    selectedBackgroundColor: DefensysTokens.panelOf(context),
    hoverBackgroundColor: DefensysTokens.surfaceHigherOf(context),
    textStyle: const TextStyle(
      fontFamily: DefensysTokens.fontFamilyInter,
      fontSize: 13,
    ),
    child: Text(label),
  );

  void _reload() => ref.read(teamDetailProvider(widget.teamId).notifier).load();

  void _selectStage(String value) {
    setState(() => _selectedDeliverableStage = value);
    final state = ref.read(teamDetailProvider(widget.teamId));
    if (state.events.isNotEmpty &&
        !'${state.team?['level']}'.toUpperCase().contains('CAPSTONE')) {
      ref.read(teamDetailProvider(widget.teamId).notifier).selectEvent(value);
    }
  }

  Widget _buildHeader(Map<String, dynamic>? team) {
    final title = team?['name']?.toString() ?? 'Team';
    final project = team?['project_title']?.toString() ?? '';
    final workflow = _overviewConceptWorkflow(team);
    final proposals = conceptRows(workflow['concepts']);

    return Row(
      children: [
        IconButton(
          tooltip: 'Back to teams',
          onPressed: widget.onBack,
          icon: Icon(
            Icons.arrow_back_rounded,
            color: DefensysTokens.maroonTextOf(context),
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: DefensysUi.pageTitle.copyWith(
                  color: DefensysTokens.maroonTextOf(context),
                ),
              ),
              if (hasOpenConceptProposals(workflow))
                Text(
                  'Concept selection · ${proposals.where((c) => '${c['title'] ?? ''}'.trim().isNotEmpty).length} of ${proposals.length} titles provided',
                  style: DefensysUi.subtitle.copyWith(
                    fontSize: 14,
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                )
              else if (project.isNotEmpty)
                Text(
                  project,
                  style: DefensysUi.subtitle.copyWith(
                    color: DefensysTokens.textSecondaryOf(context),
                  ),
                  maxLines: 2,
                ),
              if (!_isEditing)
                Text(
                  'Team workspace — submissions and roster',
                  style: TextStyle(
                    color: DefensysTokens.textSecondaryOf(context),
                    fontSize: 13,
                  ),
                ),
            ],
          ),
        ),
        if (widget.canManage && team?['is_editable'] != false && !_isEditing)
          ShadButton.outline(
            onPressed: () {
              _syncFormFromTeam(
                team!,
                ref.read(teamDetailProvider(widget.teamId)).statuses,
              );
              setState(() => _isEditing = true);
            },
            leading: const Icon(Icons.edit_outlined, size: 18),
            foregroundColor: DefensysTokens.maroonTextOf(context),
            child: Text('Edit team'),
          ),
        if (widget.canManage && _isEditing) ...[
          TextButton(
            onPressed: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? null
                : _cancelEditing,
            child: Text('Cancel'),
          ),
          const SizedBox(width: 8),
          DefensysSaveButton(
            onPressed: _saveOverview,
            isSaving: ref.watch(teamDetailProvider(widget.teamId)).isSaving,
            label: 'Save Changes',
            isPill: false,
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: ref.watch(teamDetailProvider(widget.teamId)).isSaving
                ? null
                : _confirmDelete,
            icon: const Icon(Icons.delete_outline, size: 18, color: _red),
            label: Text('Delete', style: TextStyle(color: _red)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: _line)),
          ),
        ],
      ],
    );
  }

  Map<String, dynamic> _overviewConceptWorkflow(Map<String, dynamic>? team) {
    final defense = team?['defense_context'] as Map?;
    if (defense?.containsKey('concept_workflow') == true) {
      return Map<String, dynamic>.from(
        defense?['concept_workflow'] as Map? ?? {},
      );
    }
    final workspace = ref
        .read(teamDetailProvider(widget.teamId))
        .deliverableTeam;
    final label =
        defense?['current_stage'] ??
        defense?['event_label'] ??
        workspace?['current_stage'];
    final stages = (workspace?['stages'] as List? ?? []).whereType<Map>();
    final stage = stages.where((s) => s['stage_label'] == label).firstOrNull;
    return Map<String, dynamic>.from(stage?['concept_workflow'] as Map? ?? {});
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
        Icon(icon, size: 18, color: DefensysTokens.textSecondaryOf(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: DefensysTokens.textSecondaryOf(context),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: DefensysTokens.textPrimaryOf(context),
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
            color: DefensysTokens.surfaceHigherOf(context),
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
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: _muted,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
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
    TeamDetailState detailState,
    Map<String, dynamic> team,
    bool isCapstone,
    String programLabel,
    String adviserName,
  ) {
    final project = team['project_title']?.toString() ?? '—';
    final status = team['status']?.toString() ?? 'Pending';
    final workflow = _overviewConceptWorkflow(team);
    final proposalMode = hasOpenConceptProposals(workflow);
    final proposals = conceptRows(workflow['concepts']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Project Overview Card
        Container(
          key: const ValueKey('team-project-information-card'),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: DefensysTokens.surfaceOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (proposalMode) ...[
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  spacing: 20,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PROJECT INFORMATION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: .8,
                            color: DefensysTokens.textSecondaryOf(context),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Concept proposals',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: DefensysTokens.textPrimaryOf(context),
                          ),
                        ),
                      ],
                    ),
                    ProposalTitleProgressBadge(rows: proposals),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'These proposals are awaiting concept selection.',
                  style: TextStyle(
                    fontSize: 14,
                    color: DefensysTokens.textSecondaryOf(context),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 8),
                ProposalTitleSummary(rows: proposals, showHeading: false),
              ] else
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'PROJECT INFORMATION',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                              color: DefensysTokens.textSecondaryOf(context),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            project,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: DefensysTokens.textPrimaryOf(context),
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
              Divider(color: DefensysTokens.borderOf(context), height: 1),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildMetaText(
                      'Program',
                      programLabel,
                      icon: Icons.school_outlined,
                    ),
                  ),
                  if (!isCapstone)
                    Expanded(
                      child: _buildMetaText(
                        'Section',
                        team['section']?.toString() ?? '—',
                        icon: Icons.class_outlined,
                      ),
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
            color: DefensysTokens.panelOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.badge_outlined,
                    size: 18,
                    color: DefensysTokens.maroonTextOf(context),
                  ),
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
                  team['instructor_name']?.toString() ??
                      'No instructor assigned',
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
                  Icons.person_outline,
                  'Section instructor',
                  team['instructor_name']?.toString().trim().isNotEmpty == true
                      ? team['instructor_name'].toString()
                      : 'No instructor assigned',
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
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _openEvaluation(Map<String, dynamic> grade) {
    final gradeId = asInt(grade['id']);
    if (gradeId == null) return;
    final router = GoRouter.of(context);
    final isFaculty = router.routeInformationProvider.value.uri.path.startsWith(
      '/faculty/',
    );
    final path = isFaculty
        ? FacultyRoutes.gradeDetail(gradeId)
        : AdminRoutes.gradeDetail(gradeId);
    final locked =
        grade['is_officially_complete'] == true ||
        grade['status'] == 'published';
    _refreshAfterEvaluation = true;
    // Cross-section pushes belong to the source branch's Navigator. Switch
    // branches instead, and retain an explicit destination for the Back link.
    router.go(
      Uri(
        path: path,
        queryParameters: {
          'locked': locked ? '1' : '0',
          'fromTeam': '${widget.teamId}',
          'fromTab':
              '${(ref.read(teamDetailProvider(widget.teamId)).team?['level'] ?? '')}'
                  .toUpperCase()
                  .contains('CAPSTONE')
              ? 'academic-progress'
              : 'event-progress',
          if (_selectedDeliverableStage.isNotEmpty)
            'fromStage': _selectedDeliverableStage,
        },
      ).toString(),
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
            color: DefensysTokens.panelOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.people_alt_outlined,
                    size: 18,
                    color: DefensysTokens.maroonTextOf(context),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'TEAM ROSTER (${members.length}/4)',
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
              if (members.isEmpty)
                Text(
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
                      ? name
                            .trim()
                            .split(' ')
                            .map((e) => e[0])
                            .take(2)
                            .join()
                            .toUpperCase()
                      : '?';

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: DefensysTokens.surfaceHigherOf(context),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: DefensysTokens.surfaceHigherOf(context),
                      ),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: DefensysTokens.panelOf(context),
                          child: Text(
                            initials,
                            style: TextStyle(
                              color: isLeader
                                  ? const Color(0xFFB45309)
                                  : DefensysTokens.maroonTextOf(context),
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
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                  color: _ink,
                                ),
                              ),
                              if (username.isNotEmpty)
                                Text(
                                  username,
                                  style: TextStyle(
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
                            if (isCapstone && studentId != null)
                              StudentCapstoneParticipationButton(
                                studentId: studentId,
                                name: name,
                                number: _asInt(
                                  (student['capstone_participation']
                                      as Map?)?['number'],
                                ),
                                canOpenHistory:
                                    ref.watch(authProvider).user?['role'] ==
                                    'admin',
                              ),
                            if (isLeader)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: const Color(0xFFFDE68A),
                                  ),
                                ),
                                child: Text(
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: DefensysTokens.surfaceHigherOf(
                                    context,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: DefensysTokens.borderOf(context),
                                  ),
                                ),
                                child: Text(
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
              color: DefensysTokens.panelOf(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: DefensysTokens.borderOf(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.workspace_premium_outlined,
                      size: 18,
                      color: DefensysTokens.maroonTextOf(context),
                    ),
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
                      _adviserLabel(
                        _asInt(team['adviser_id']),
                        detailState.advisers,
                      ),
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

        final leftColumn = _buildLeftOverviewColumn(
          detailState,
          team,
          isCapstone,
          programLabel,
          adviserName,
        );
        final rightColumn = _buildRightOverviewColumn(
          detailState,
          team,
          isCapstone,
          members,
          leaderId,
        );

        if (isWide) {
          return SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: leftColumn),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: rightColumn),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [leftColumn, const SizedBox(height: 24), rightColumn],
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
        ? const ['Pending', 'Approved', 'Failed']
        : detailState.statuses;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 850;

        final leftColumn = Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: DefensysTokens.panelOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
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
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _projectTitleController,
                decoration: const InputDecoration(
                  labelText: 'Project Title',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Program',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                child: Text(
                  isCapstone ? 'Capstone · $yearLevel' : '$yearLevel PIT',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: statusOptions.contains(_status)
                    ? _status
                    : statusOptions.first,
                decoration: const InputDecoration(
                  labelText: 'Team Result',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                ),
                items: statusOptions
                    .map(
                      (item) =>
                          DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _status = value ?? _status),
              ),
              if (!isCapstone) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _sectionController,
                  decoration: const InputDecoration(
                    labelText: 'Section',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
              if (!widget.isPitLead && isCapstone) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<int?>(
                  initialValue:
                      detailState.advisers.any(
                        (a) => _asInt(a['id']) == _adviserId,
                      )
                      ? _adviserId
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Adviser',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<int?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ...detailState.advisers.map(
                      (adviser) => DropdownMenuItem<int?>(
                        value: _asInt(adviser['id']),
                        enabled:
                            _asInt(adviser['id']) ==
                                _asInt(team['adviser_id']) ||
                            adviser['capacity'] is! Map ||
                            adviser['capacity']['can_assign'] != false,
                        child: Text(
                          '${adviser['name']} (${adviser['username']})'
                          '${adviser['capacity'] is Map ? ' · ${adviser['capacity']['active_count']}/${adviser['capacity']['effective_limit']}' : ''}',
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
            color: DefensysTokens.panelOf(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: DefensysTokens.borderOf(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ROSTER SELECTION (${_selectedMembers.length}/4)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: _ink,
                    ),
                  ),
                  Icon(
                    Icons.person_add_alt_1_outlined,
                    size: 18,
                    color: DefensysTokens.maroonTextOf(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Search Students',
                  hintText: 'Type name or student ID...',
                  prefixIcon: Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
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
                  color: DefensysTokens.surfaceHigherOf(context),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: DefensysTokens.borderOf(context)),
                ),
                child: Builder(
                  builder: (context) {
                    final filteredStudents = detailState.students.where((
                      student,
                    ) {
                      final studentId = _asInt(student['id']);
                      if (studentId != null &&
                          _selectedMembers.contains(studentId)) {
                        return true;
                      }
                      if (_studentFilter.trim().isEmpty) return true;
                      final name =
                          student['name']?.toString().toLowerCase() ?? '';
                      final username =
                          student['username']?.toString().toLowerCase() ?? '';
                      final query = _studentFilter.toLowerCase();
                      return name.contains(query) || username.contains(query);
                    }).toList();

                    if (filteredStudents.isEmpty) {
                      return Center(
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
                            activeColor: DefensysTokens.maroonOf(context),
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  if (_selectedMembers.length >= 4 &&
                                      !selected) {
                                    showValidationToast(
                                      context,
                                      'A team can have a maximum of 4 members.',
                                    );
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
                              style: TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: _leaderId == studentId
                                ? Text(
                                    'Team Leader',
                                    style: TextStyle(
                                      color: DefensysTokens.maroonTextOf(
                                        context,
                                      ),
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
                                      color: _leaderId == studentId
                                          ? _gold
                                          : _muted,
                                    ),
                                    onPressed: () =>
                                        setState(() => _leaderId = studentId),
                                  )
                                : null,
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Select up to 4 members. Use the medal button to designate the team leader.',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              if (!widget.isPitLead && isCapstone) ...[
                const SizedBox(height: 24),
                Divider(color: _line),
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
                Expanded(flex: 3, child: leftColumn),
                const SizedBox(width: 24),
                Expanded(flex: 2, child: rightColumn),
              ],
            ),
          );
        } else {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [leftColumn, const SizedBox(height: 24), rightColumn],
            ),
          );
        }
      },
    );
  }

  Widget _buildDeliverablesTab(TeamDetailState state, List<String> options) =>
      TeamDeliverablesTab(
        teamId: widget.teamId,
        state: state,
        stageLabel: _selectedDeliverableStage,
        stageOptions: options,
        onStageChanged: _selectStage,
        onRetry: _reload,
        onDownloadDocument: _downloadTeamDocument,
        onViewReport: _viewWeeklyReportFile,
      );

  Widget _buildAcademicProgressTab(TeamDetailState state) =>
      SingleChildScrollView(
        child: AcademicProgressCard(
          grades: state.grades,
          stageLabels: detailRows(state.deliverableTeam?['stages'])
              .map((s) => '${s['stage_label'] ?? ''}')
              .where((s) => s.isNotEmpty)
              .toList(),
          currentStage: state.deliverableTeam?['current_stage']?.toString(),
          isCapstone: true,
          isLoading: state.isLoading,
          error: state.gradesError,
          onRetry: _reload,
          onViewEvaluation: _openEvaluation,
        ),
      );

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
        Text(
          'Adviser History',
          style: TextStyle(
            color: _ink,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Past and current advisers for this team.',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          Text(
            'No adviser changes recorded yet.',
            style: TextStyle(color: _muted, fontSize: 12.5),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: DefensysTokens.surfaceHigherOf(context),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: DefensysTokens.borderOf(context)),
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
                Divider(height: 1, color: _line),
                ...rows.map((row) {
                  final isCurrent = row['is_current'] == true;
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
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
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (isCurrent)
                                Text(
                                  'Current',
                                  style: TextStyle(
                                    color: DefensysTokens.maroonTextOf(context),
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
      'project_title': _projectTitleController.text.trim(),
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
        title: Text('Delete Team'),
        content: Text('Delete $name? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Delete'),
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
        title: Text('Change project adviser?'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Team: $teamName',
                style: TextStyle(fontWeight: FontWeight.w700),
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
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reasonCtrl.text.trim()),
            child: Text('Confirm change'),
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

    await viewFileInDialog(
      context: context,
      fileUrl: fileRef,
      fileName: (reportFile ?? fileRef).split('/').last,
    );
  }

  Future<void> _downloadTeamDocument(int docId) async {
    try {
      final response = await ref
          .read(authenticatedHttpClientProvider)
          .get(Uri.parse('${ApiConfig.teamDocumentsUrl}/$docId/download/'));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final document = ref
            .read(teamDetailProvider(widget.teamId))
            .documents
            .where((doc) => '${doc['id']}' == '$docId')
            .firstOrNull;
        await downloadBytesFile(
          bytes: response.bodyBytes,
          fileName: '${document?['file_name'] ?? 'Document'}'
              .split(RegExp(r'[/\\]'))
              .last,
          mimeType: '${document?['mime_type'] ?? 'application/octet-stream'}',
        );
        if (!mounted) return;
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
}
