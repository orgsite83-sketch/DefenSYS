import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../../config/api_config.dart';
import '../../../services/authenticated_client.dart';
import '../../../services/capstone_deliverables_provider.dart';
import '../../../services/weekly_progress_provider.dart';
import '../../../services/adviser_grading_provider.dart';
import '../../../theme/app_theme.dart';
import '../admin/widgets/defensys_admin_shell.dart';
import '../faculty/weekly_progress_reports_screen.dart';
import '../../../l10n/l10n_ext.dart';
import '../../../widgets/confirm_dialog.dart';
import '../../../widgets/feedback_toast.dart';
import '../../../utils/progress_upload.dart';
import '../../../services/auth_provider.dart';
import '../../../utils/pdf_viewer.dart';

String _formatUploadFailureMessage(int statusCode, String responseBody) {
  try {
    final decoded = jsonDecode(responseBody);
    if (decoded is Map) {
      final detail = decoded['detail'];
      if (detail is String && detail.isNotEmpty) {
        return 'Upload failed: $detail';
      }
      final lines = <String>[];
      decoded.forEach((key, value) {
        if (value is List) {
          for (final item in value) {
            lines.add('$key: $item');
          }
        } else {
          lines.add('$key: $value');
        }
      });
      if (lines.isNotEmpty) {
        return 'Upload failed: ${lines.join(' ')}';
      }
    }
  } catch (_) {
    // Not JSON (e.g. legacy HTML error page).
  }
  if (responseBody.contains('<!DOCTYPE html>') ||
      responseBody.contains('<html')) {
    return 'Upload failed (server error $statusCode). Check backend logs or try again.';
  }
  final trimmed = responseBody.trim();
  if (trimmed.isEmpty) {
    return 'Upload failed (status $statusCode).';
  }
  return 'Upload failed: $trimmed';
}

class TeamDeliverablesScreen extends ConsumerStatefulWidget {
  final String? initialScope;
  final bool isAdviser;
  final String? pitYearLevel;
  final int? initialTeamId;
  final int? initialTab;
  const TeamDeliverablesScreen({
    super.key,
    this.initialScope,
    this.isAdviser = false,
    this.pitYearLevel,
    this.initialTeamId,
    this.initialTab,
  });

  @override
  ConsumerState<TeamDeliverablesScreen> createState() =>
      _TeamDeliverablesScreenState();
}

class _TeamDeliverablesScreenState
    extends ConsumerState<TeamDeliverablesScreen> {
  final _searchController = TextEditingController();
  Timer? _pendingRemoveTimer;
  bool _pendingRemoveCancelled = false;
  
  // State for master-detail split layout and stage selections
  int? _selectedTeamId;
  bool _showMobileDetail = false;
  final Map<int, String> _cardSelectedStages = {};
  Timer? _searchDebounceTimer;

  // State for inner tabs within expanded cards
  final Map<int, int> _cardActiveTabs = {}; // teamId -> tabIndex
  
  // Scoring text controllers and selected rubrics mapped by "$teamId-$stageLabel"
  final Map<String, Map<String, TextEditingController>> _teamCriteriaScoreCtrls = {};
  final Map<String, TextEditingController> _teamManualScoreCtrls = {};
  final Map<String, Map<String, dynamic>?> _teamSelectedRubrics = {};

  @override
  void initState() {
    super.initState();
    _selectedTeamId = widget.initialTeamId;
    if (widget.initialTeamId != null && widget.initialTab != null) {
      _cardActiveTabs[widget.initialTeamId!] = widget.initialTab!;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
        scope: widget.initialScope,
        yearLevel: widget.pitYearLevel,
      );
      ref.read(adviserGradingProvider.notifier).fetchAll();
      ref.read(weeklyProgressProvider.notifier).fetchReports();
    });
  }

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    _pendingRemoveTimer?.cancel();
    _searchController.dispose();
    for (final c in _teamManualScoreCtrls.values) {
      c.dispose();
    }
    for (final subMap in _teamCriteriaScoreCtrls.values) {
      for (final c in subMap.values) {
        c.dispose();
      }
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(capstoneDeliverablesProvider);

    // Auto-select the first team if none is selected or selected team is not present in the current list
    if (state.teams.isNotEmpty) {
      final teamIds = state.teams.map((t) => _asInt(t['id'])).toList();
      if (_selectedTeamId == null || !teamIds.contains(_selectedTeamId)) {
        _selectedTeamId = teamIds.first;
      }
    }

    final isWide = MediaQuery.of(context).size.width >= 900;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: null,
      body: isWide 
          ? _buildDesktopLayout(state) 
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(),
              child: _buildMobileLayout(state),
            ),
    );
  }
  Widget _buildDesktopLayout(CapstoneDeliverablesState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          child: DefensysPageHeader(
            icon: Icons.folder_open_outlined,
            title: state.scope == 'pit' ? 'PIT Teams' : 'Capstone Teams',
            subtitle: state.activeSemester?['display_name']?.toString() ?? 'Active Semester',
            actions: IconButton(
              tooltip: 'Refresh',
              onPressed: state.isSaving
                  ? null
                  : () => ref
                        .read(capstoneDeliverablesProvider.notifier)
                        .fetchDeliverables(),
              icon: const Icon(Icons.refresh),
            ),
          ),
        ),
        // Stats at the top
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
          child: _buildStats(state),
        ),
        if (state.error != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _notice(Icons.error_outline, state.error!, AppColors.danger),
          ),
        ],
        if (state.message != null) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _notice(Icons.check_circle_outline, state.message!, AppColors.success),
          ),
        ],
        if (_stageNotConfigured(state)) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: _notice(
              Icons.info_outline,
              state.scope == 'pit'
                  ? 'No deliverables configured for ${state.selectedStage}. Add them in PIT Event Settings.'
                  : 'No deliverables configured for ${state.selectedStage}. Add them in Defense Stages Setup so Required progress can be tracked.',
              AppColors.gold,
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Split Pane view
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left pane: Team list & search toolbar
                SizedBox(
                  width: 380,
                  child: Column(
                    children: [
                      _buildToolbar(state),
                      const SizedBox(height: 12),
                      Expanded(
                        child: state.isLoading
                            ? const Center(child: CircularProgressIndicator())
                            : SingleChildScrollView(
                                child: _buildTeamListCompact(state),
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 20),
                // Right pane: Detail View
                Expanded(
                  child: state.isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _selectedTeamId == null
                          ? _buildNoSelectionDetailPane(state)
                          : SingleChildScrollView(
                              child: _buildTeamDetailPane(
                                state,
                                state.teams.firstWhere(
                                  (t) => _asInt(t['id']) == _selectedTeamId,
                                  orElse: () => state.teams.first,
                                ),
                              ),
                            ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(CapstoneDeliverablesState state) {
    if (_showMobileDetail && _selectedTeamId != null) {
      final team = state.teams.firstWhere(
        (t) => _asInt(t['id']) == _selectedTeamId,
        orElse: () => state.teams.isNotEmpty ? state.teams.first : const <String, dynamic>{},
      );
      if (team.isEmpty) {
        return _buildNoSelectionDetailPane(state);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextButton.icon(
              onPressed: () {
                setState(() {
                  _showMobileDetail = false;
                });
              },
              icon: const Icon(Icons.arrow_back, color: AppColors.maroon),
              label: const Text(
                'Back to Teams List',
                style: TextStyle(color: AppColors.maroon, fontWeight: FontWeight.bold),
              ),
              style: TextButton.styleFrom(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.zero,
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildTeamDetailPane(state, team),
            ),
          ),
        ],
      );
    }

    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DefensysPageHeader(
            icon: Icons.folder_open_outlined,
            title: state.scope == 'pit' ? 'PIT Teams' : 'Capstone Teams',
            subtitle: state.activeSemester?['display_name']?.toString() ?? 'Active Semester',
            actions: IconButton(
              tooltip: 'Refresh',
              onPressed: state.isSaving
                  ? null
                  : () => ref
                        .read(capstoneDeliverablesProvider.notifier)
                        .fetchDeliverables(),
              icon: const Icon(Icons.refresh),
            ),
          ),
          const SizedBox(height: 16),
          _buildStats(state),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            _notice(Icons.error_outline, state.error!, AppColors.danger),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 12),
            _notice(Icons.check_circle_outline, state.message!, AppColors.success),
          ],
          const SizedBox(height: 16),
          _buildToolbar(state),
          if (_stageNotConfigured(state)) ...[
            const SizedBox(height: 12),
            _notice(
              Icons.info_outline,
              state.scope == 'pit'
                  ? 'No deliverables configured for ${state.selectedStage}. Add them in PIT Event Settings.'
                  : 'No deliverables configured for ${state.selectedStage}. Add them in Defense Stages Setup so Required progress can be tracked.',
              AppColors.gold,
            ),
          ],
          const SizedBox(height: 16),
          if (state.isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              ),
            )
          else
            _buildTeamListCompact(state),
        ],
      ),
    );
  }

  Widget _buildTeamListCompact(CapstoneDeliverablesState state) {
    if (state.teams.isEmpty) {
      final emptyTitle = state.scope == 'pit' ? 'No PIT teams found' : 'No Capstone teams found';
      final emptySubtitle = state.scope == 'pit' ? 'Assign PIT teams first.' : 'Assign Capstone teams and advisers first.';
      return Container(
        decoration: _cardDecoration(),
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.folder_open_outlined, size: 36, color: AppColors.textSecondary),
            const SizedBox(height: 10),
            Text(emptyTitle, style: const TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(emptySubtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12), textAlign: TextAlign.center),
          ],
        ),
      );
    }

    return Column(
      children: state.teams.map((team) {
        final teamId = _asInt(team['id']);
        final isSelected = teamId == _selectedTeamId;
        return _buildCompactTeamCard(state, team, isSelected);
      }).toList(),
    );
  }

  Widget _buildCompactTeamCard(CapstoneDeliverablesState state, Map<String, dynamic> team, bool isSelected) {
    final teamId = _asInt(team['id']);
    final stages = _stageList(team);
    final cardSelectedStageLabel = _cardSelectedStages[teamId] ?? state.selectedStage;
    final stagePayload = _stagePayload(stages, cardSelectedStageLabel);
    final complete = stagePayload['required_complete'] == true;
    final endorsed = stagePayload['endorsed'] == true;
    final archiveComplete = stagePayload['archive_complete'] == true;
    final status = archiveComplete
        ? 'stage_completed'
        : (stagePayload['status']?.toString() ??
            (endorsed ? 'endorsed' : (complete ? 'complete' : 'missing')));

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.maroon.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? AppColors.maroon : const Color(0xFFE2E8F0),
          width: isSelected ? 1.8 : 1.0,
        ),
        boxShadow: isSelected
            ? [
                BoxShadow(
                  color: AppColors.maroon.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isSelected)
                Container(
                  width: 5,
                  color: AppColors.maroon,
                ),
              Expanded(
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _selectedTeamId = teamId;
                        _showMobileDetail = true;
                      });
                    },
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(isSelected ? 10 : 12, 12, 12, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top Row: Level & Section tags on left, Status Chip on right
                          Row(
                            children: [
                              Expanded(
                                child: Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: [
                                    if (team['level'] != null && team['level'].toString().isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Text(
                                          team['level'].toString(),
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                    if (team['section'] != null && team['section'].toString().isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFFE2E8F0)),
                                        ),
                                        child: Text(
                                          team['section'].toString(),
                                          style: const TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF475569),
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              _statusChip(status),
                            ],
                          ),
                          const SizedBox(height: 8),
                          // Team Name
                          Text(
                            team['name']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? AppColors.maroon : AppColors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          // Project Title
                          Text(
                            team['project_title']?.toString() ?? '',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          // Adviser Name
                          Row(
                            children: [
                              Icon(
                                Icons.school_outlined,
                                size: 14,
                                color: isSelected ? AppColors.maroon.withValues(alpha: 0.7) : AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Adviser: ${team['adviser_name'] ?? 'Unassigned'}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          // Team Members list (Compact chips)
                          if (team['members'] is List && (team['members'] as List).isNotEmpty) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'TEAM MEMBERS',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: (team['members'] as List).take(4).map<Widget>((m) {
                                final isLeader = m['role'] == 'leader';
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isLeader ? const Color(0xFFFEF3C7) : const Color(0xFFF1F5F9),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isLeader ? const Color(0xFFFDE68A) : const Color(0xFFE2E8F0),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (isLeader) ...[
                                        const Icon(Icons.star_rounded, size: 10, color: Color(0xFFD97706)),
                                        const SizedBox(width: 2),
                                      ],
                                      Flexible(
                                        child: Text(
                                          m['name']?.toString() ?? '',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: isLeader ? FontWeight.w700 : FontWeight.normal,
                                            color: isLeader ? const Color(0xFFB45309) : const Color(0xFF475569),
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 1,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamDetailPane(CapstoneDeliverablesState state, Map<String, dynamic> team) {
    final teamId = _asInt(team['id']);
    
    // Determine which stage we are focusing on for this card
    final cardSelectedStageLabel = _cardSelectedStages[teamId] ?? state.selectedStage;

    final stages = _stageList(team);
    final stagePayload = _stagePayload(stages, cardSelectedStageLabel);

    final configured = stagePayload['deliverables_configured'] == true;
    final complete = stagePayload['required_complete'] == true;
    final endorsed = stagePayload['endorsed'] == true;
    final archiveComplete = stagePayload['archive_complete'] == true;
    final canEndorse = configured && complete && !endorsed;
    final status = archiveComplete
        ? 'stage_completed'
        : (stagePayload['status']?.toString() ??
            (endorsed ? 'endorsed' : (complete ? 'complete' : 'missing')));

    final gradingState = ref.watch(adviserGradingProvider);
    final gradeRecord = gradingState.grades.firstWhere(
      (g) => _asInt(g['team_id']) == teamId && g['stage_label']?.toString() == cardSelectedStageLabel,
      orElse: () => team['grade'] is Map ? Map<String, dynamic>.from(team['grade'] as Map) : <String, dynamic>{},
    );

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Section: Team details & status badge
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      team['name']?.toString() ?? '',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.maroon,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      team['project_title']?.toString() ?? '',
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _chip(
                          team['year_level']?.toString() ?? '',
                          AppColors.gold,
                        ),
                        _chip(
                          'Adviser: ${team['adviser_name'] ?? 'Unassigned'}',
                          AppColors.maroon,
                        ),
                        _chip(
                          '${team['submitted_count'] ?? 0} submitted',
                          Colors.blue,
                        ),
                        if (gradeRecord['final_grade'] != null)
                          _chip(
                            'Grade: ${_asDouble(gradeRecord['final_grade'])?.toStringAsFixed(2) ?? ''} (${gradeRecord['result']?.toString().toUpperCase() ?? ''})',
                            gradeRecord['result'] == 'passed' ? AppColors.success : AppColors.danger,
                            icon: gradeRecord['result'] == 'passed' ? Icons.check_circle : Icons.error_outline,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _statusChip(status),
            ],
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Color(0xFFE2E8F0), height: 1),
          ),

          // Detailed section with stage selection, tabs, deliverables etc.
          _buildExpandedSection(team, state),
        ],
      ),
    );
  }

  Widget _buildNoSelectionDetailPane(CapstoneDeliverablesState state) {
    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(32),
      alignment: Alignment.center,
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 64, color: AppColors.textSecondary),
          SizedBox(height: 16),
          Text(
            'No Team Selected',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          SizedBox(height: 6),
          Text(
            'Select a team from the list to view deliverables, grades, and roster details.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStats(CapstoneDeliverablesState state) {
    final teamLabel = state.scope == 'pit' ? 'PIT Teams' : 'Capstone Teams';
    final items = [
      _stat(teamLabel, _count(state, 'teams'), Icons.groups_2_outlined, AppColors.maroon),
      _stat('Ready', _count(state, 'ready'), Icons.verified_outlined, AppColors.success),
      _stat('Pending', _count(state, 'pending_review'), Icons.rate_review_outlined, Colors.orange),
      _stat('Missing', _count(state, 'missing_requirements'), Icons.warning_amber_outlined, AppColors.warning),
      _stat('Files', _count(state, 'submitted_files'), Icons.folder_copy_outlined, Colors.blue),
      _stat('Archive Files', _count(state, 'archive_files'), Icons.inventory_2_outlined, AppColors.gold),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            children: items.map((widget) {
              final calculatedWidth = (constraints.maxWidth - 12) / 2;
              final itemWidth = calculatedWidth.clamp(0.0, double.infinity);
              return SizedBox(
                width: itemWidth > 180 ? itemWidth : double.infinity,
                child: widget,
              );
            }).toList(),
          );
        }
        return Row(
          children: List.generate(items.length, (index) {
            final isFirst = index == 0;
            final isLast = index == items.length - 1;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: isFirst ? 0 : 8,
                  right: isLast ? 0 : 8,
                ),
                child: items[index],
              ),
            );
          }),
        );
      },
    );
  }

  Widget _stat(String label, int count, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          _iconBox(icon, color),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  count.toString(),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _toolbarInputDec({required String label, IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 20) : null,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      labelStyle: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.maroon, width: 1.5),
      ),
    );
  }

  Widget _buildToolbar(CapstoneDeliverablesState state) {
    final List<String> stageOptions = _uniqueStrings(state.stageOptions);
    final selectedStage = stageOptions.contains(state.selectedStage)
        ? state.selectedStage
        : null;
    final List<Map<String, dynamic>> statuses = state.statuses.isEmpty
        ? const <Map<String, dynamic>>[
            {'value': '', 'label': 'All Teams'},
            {'value': 'ready', 'label': 'Ready / Endorsed'},
            {'value': 'missing', 'label': 'Missing Requirements'},
          ]
        : state.statuses;

    final searchField = TextField(
      controller: _searchController,
      decoration: _toolbarInputDec(
        label: widget.isAdviser ? 'Search team, project' : 'Search team, project, adviser',
        prefixIcon: Icons.search,
      ),
      style: const TextStyle(
        fontSize: 13,
      ),
      onChanged: (value) {
        if (_searchDebounceTimer?.isActive ?? false) {
          _searchDebounceTimer!.cancel();
        }
        _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
          ref
              .read(capstoneDeliverablesProvider.notifier)
              .fetchDeliverables(search: value);
        });
      },
      onSubmitted: (value) {
        if (_searchDebounceTimer?.isActive ?? false) {
          _searchDebounceTimer!.cancel();
        }
        ref
            .read(capstoneDeliverablesProvider.notifier)
            .fetchDeliverables(search: value);
      },
    );

    final stageDropdown = DropdownButtonFormField<String>(
      initialValue: selectedStage,
      isExpanded: true,
      decoration: _toolbarInputDec(
        label: state.scope == 'pit' ? 'PIT Event' : 'Stage View',
      ),
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
      hint: Text(
        stageOptions.isEmpty
            ? (state.scope == 'pit' ? 'No events configured' : 'No stages configured')
            : 'Select stage',
        style: const TextStyle(fontSize: 13),
      ),
      items: stageOptions
          .map(
            (stage) => DropdownMenuItem(
              value: stage,
              child: Text(
                stage,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: stageOptions.isEmpty
          ? null
          : (value) => ref
                .read(capstoneDeliverablesProvider.notifier)
                .fetchDeliverables(
                  selectedStage: value ?? selectedStage ?? '',
                ),
    );

    final statusDropdown = DropdownButtonFormField<String>(
      initialValue: state.status,
      decoration: _toolbarInputDec(label: 'Status'),
      style: const TextStyle(
        fontSize: 13,
        color: AppColors.textPrimary,
      ),
      isExpanded: true,
      items: statuses
          .map(
            (item) => DropdownMenuItem(
              value: item['value']?.toString() ?? '',
              child: Text(
                item['label']?.toString() ?? '',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (value) => ref
          .read(capstoneDeliverablesProvider.notifier)
          .fetchDeliverables(status: value ?? ''),
    );

    final clearButton = OutlinedButton.icon(
      onPressed: () {
        _searchController.clear();
        if (_searchDebounceTimer?.isActive ?? false) {
          _searchDebounceTimer!.cancel();
        }
        ref
            .read(capstoneDeliverablesProvider.notifier)
            .fetchDeliverables(search: '', status: '');
      },
      icon: const Icon(Icons.clear_all_rounded, size: 18),
      label: const Text(
        'Clear Filters',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF64748B),
        side: const BorderSide(color: Color(0xFFCBD5E1)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );

    return Container(
      decoration: _cardDecoration(),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 600) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                searchField,
                const SizedBox(height: 12),
                stageDropdown,
                const SizedBox(height: 12),
                statusDropdown,
                const SizedBox(height: 12),
                clearButton,
              ],
            );
          } else if (constraints.maxWidth < 900) {
            final calculatedWidth = (constraints.maxWidth - 48) / 2;
            final dropdownWidth = calculatedWidth.clamp(0.0, double.infinity);
            return Wrap(
              spacing: 16,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: double.infinity, child: searchField),
                SizedBox(width: dropdownWidth, child: stageDropdown),
                SizedBox(width: dropdownWidth, child: statusDropdown),
                SizedBox(width: double.infinity, child: clearButton),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: searchField),
              const SizedBox(width: 16),
              SizedBox(width: 220, child: stageDropdown),
              const SizedBox(width: 16),
              SizedBox(width: 220, child: statusDropdown),
              const SizedBox(width: 16),
              clearButton,
            ],
          );
        },
      ),
    );
  }

  List<String> _uniqueStrings(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      if (seen.add(value)) {
        result.add(value);
      }
    }
    return result;
  }





  bool _stageNotConfigured(CapstoneDeliverablesState state) {
    if (state.teams.isEmpty) {
      return false;
    }
    final stage = state.teams.first['selected_stage'];
    if (stage is! Map) {
      return false;
    }
    return stage['deliverables_configured'] != true;
  }

  Widget _requiredProgressBlock({
    required bool configured,
    required int done,
    required int total,
  }) {
    final emptyLabel = configured
        ? 'Required — No required items'
        : 'Required — Not configured';
    return _progressBlock(
      'Required',
      done,
      total,
      AppColors.success,
      emptyLabel: emptyLabel,
    );
  }

  Widget _archiveProgressBlock(Map<String, dynamic> selectedStage) {
    final unlocked = selectedStage['archive_unlocked'] == true;
    final done = _asInt(selectedStage['archive_required_uploaded']);
    final total = _asInt(selectedStage['archive_required_total']);

    if (!unlocked) {
      return _progressBlock(
        'Archive',
        0,
        0,
        AppColors.gold,
        emptyLabel: 'Archive — Locked until defense done',
      );
    }
    if (total == 0) {
      return _progressBlock(
        'Archive',
        0,
        0,
        AppColors.gold,
        emptyLabel: 'Archive — No required items',
      );
    }
    return _progressBlock('Archive', done, total, AppColors.gold);
  }

  Widget _progressBlock(
    String label,
    int done,
    int total,
    Color color, {
    String? emptyLabel,
  }) {
    if (total == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            emptyLabel ?? '$label — Not configured',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 10,
              value: 0,
              color: color.withValues(alpha: 0.35),
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      );
    }

    final pct = done / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label ($done/$total)',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Text(
              '${(pct * 100).round()}%',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 10,
            value: pct,
            color: color,
            backgroundColor: color.withValues(alpha: 0.12),
          ),
        ),
      ],
    );
  }

  Widget _deliverableRow(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    void Function(void Function()) setDialogState,
  ) {
    final uploaded = item['uploaded'] == true;
    final locked = item['locked'] == true;
    final submission = Map<String, dynamic>.from(
      item['submission'] as Map? ?? const {},
    );
    final isWPR =
        item['id'] == 'WPR'; // Check if this is Weekly Progress Report

    final suggestedFile = item['suggested_file_name']?.toString() ?? '';

    final authState = ref.watch(authProvider);
    final user = authState.user;
    final isFaculty = user?['role'] == 'faculty';
    final isAdmin = user?['role'] == 'admin';
    final stages = _stageList(team);
    final stage = _stagePayload(stages, stageLabel);
    final endorsed = stage['endorsed'] == true;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Header Row (Checkbox Icon, Title text, and Right actions centered horizontally)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    uploaded ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: uploaded ? AppColors.success : AppColors.textSecondary,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item['label']?.toString() ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right side elements aligned center
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item['required'] == true) ...[
                        _chip('Required', AppColors.danger),
                        const SizedBox(width: 8),
                      ],
                      if (isFaculty && !isAdmin) ...[
                        if (isWPR) ...[
                          OutlinedButton.icon(
                            onPressed: () => _showApproveWPRDialog(
                              team,
                              stageLabel,
                              uploaded,
                              setDialogState,
                            ),
                            icon: Icon(
                              uploaded ? Icons.visibility : Icons.check_circle_outline,
                              size: 14,
                            ),
                            label: Text(uploaded ? 'View Reports' : 'View & Approve'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: uploaded ? Colors.blue : AppColors.success,
                              side: BorderSide(
                                color: uploaded ? Colors.blue : AppColors.success,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ] else ...[
                          if (uploaded) ...[
                            if (submission['status'] == 'pending') ...[
                              IconButton(
                                onPressed: () => _reviewSubmission(
                                  _asInt(team['id']),
                                  stageLabel,
                                  item['id'],
                                  'accepted',
                                  setDialogState,
                                ),
                                icon: const Icon(Icons.check, color: AppColors.success, size: 16),
                                tooltip: 'Accept',
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                  maxWidth: 28,
                                  maxHeight: 28,
                                ),
                                padding: EdgeInsets.zero,
                                style: IconButton.styleFrom(
                                  side: const BorderSide(color: AppColors.success),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              IconButton(
                                onPressed: () => _promptRejectionFeedback(
                                  _asInt(team['id']),
                                  stageLabel,
                                  item['id'],
                                  setDialogState,
                                  isEndorsed: endorsed,
                                ),
                                icon: const Icon(Icons.close, color: AppColors.danger, size: 16),
                                tooltip: 'Reject',
                                constraints: const BoxConstraints(
                                  minWidth: 28,
                                  minHeight: 28,
                                  maxWidth: 28,
                                  maxHeight: 28,
                                ),
                                padding: EdgeInsets.zero,
                                style: IconButton.styleFrom(
                                  side: const BorderSide(color: AppColors.danger),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ),
                            ] else if (submission['status'] == 'accepted') ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.check_circle, color: AppColors.success, size: 18),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Accepted',
                                    style: TextStyle(
                                      color: AppColors.success,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () => _promptRejectionFeedback(
                                      _asInt(team['id']),
                                      stageLabel,
                                      item['id'],
                                      setDialogState,
                                      isEndorsed: endorsed,
                                    ),
                                    icon: const Icon(Icons.close, color: AppColors.danger, size: 14),
                                    tooltip: 'Reject',
                                    constraints: const BoxConstraints(
                                      minWidth: 24,
                                      minHeight: 24,
                                      maxWidth: 24,
                                      maxHeight: 24,
                                    ),
                                    padding: EdgeInsets.zero,
                                    style: IconButton.styleFrom(
                                      side: const BorderSide(color: AppColors.danger),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ] else if (submission['status'] == 'rejected') ...[
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.cancel, color: AppColors.danger, size: 18),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'Rejected',
                                    style: TextStyle(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    onPressed: () => _reviewSubmission(
                                      _asInt(team['id']),
                                      stageLabel,
                                      item['id'],
                                      'accepted',
                                      setDialogState,
                                    ),
                                    icon: const Icon(Icons.check, color: AppColors.success, size: 14),
                                    tooltip: 'Accept',
                                    constraints: const BoxConstraints(
                                      minWidth: 24,
                                      minHeight: 24,
                                      maxWidth: 24,
                                      maxHeight: 24,
                                    ),
                                    padding: EdgeInsets.zero,
                                    style: IconButton.styleFrom(
                                      side: const BorderSide(color: AppColors.success),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ] else ...[
                            const Text(
                              'Awaiting Student Upload',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ] else ...[
                        if (isWPR)
                          OutlinedButton.icon(
                            onPressed: () => _showApproveWPRDialog(
                              team,
                              stageLabel,
                              uploaded,
                              setDialogState,
                            ),
                            icon: Icon(
                              uploaded ? Icons.visibility : Icons.check_circle_outline,
                              size: 14,
                            ),
                            label: Text(uploaded ? 'View Reports' : 'View & Approve'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: uploaded ? Colors.blue : AppColors.success,
                              side: BorderSide(
                                color: uploaded ? Colors.blue : AppColors.success,
                              ),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: locked
                                ? null
                                : () => _promptUploadOrReplace(team, stageLabel, item),
                            icon: Icon(uploaded ? Icons.add : Icons.upload_file, size: 14),
                            label: Text(uploaded ? 'Upload More' : 'Upload'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ),
                      ],
                    ],
                  ),
                ],
              ),

              // 2. Details Column (indented under the text label: checkbox width 20 + gap 10 = 30px padding left)
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (uploaded) ...[
                      if (isWPR) ...[
                        const SizedBox(height: 4),
                        Text(
                          'All weekly reports approved - ${submission['uploaded_by_name'] ?? ''}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ] else ...[
                        const SizedBox(height: 6),
                        ..._buildFileList(
                          team,
                          stageLabel,
                          item,
                          submission,
                          locked,
                          isFaculty,
                          isAdmin,
                          endorsed,
                          setDialogState,
                        ),
                      ],
                      if (submission['reviewed_by_name'] != null && (submission['reviewed_by_name']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Reviewed by: ${submission['reviewed_by_name']}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (submission['status'] == 'rejected' && (submission['feedback']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.danger.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.danger.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            'Remarks: ${submission['feedback']}',
                            style: const TextStyle(
                              color: AppColors.danger,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                      if (submission['status'] == 'accepted' && (submission['feedback']?.toString() ?? '').isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.success.withValues(alpha: 0.15)),
                          ),
                          child: Text(
                            'Remarks: ${submission['feedback']}',
                            style: const TextStyle(
                              color: AppColors.success,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ] else if ((item['archive_note']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item['archive_note'].toString(),
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ] else if (isWPR) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Click "View & Approve" to review all weekly reports',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (suggestedFile.isNotEmpty && !uploaded)
          Container(
            margin: const EdgeInsets.only(bottom: 12, top: 4),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.info_outline,
                    color: AppColors.gold,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Awaiting PDF: Please use this exact filename to automatically satisfy the archive requirement.',
                        style: TextStyle(
                          color: AppColors.gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: AppColors.gold.withValues(alpha: 0.2),
                              ),
                            ),
                            child: SelectableText(
                              suggestedFile,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: suggestedFile),
                              );
                              showSuccessToast(
                                context,
                                'Filename copied to clipboard!',
                              );
                            },
                            borderRadius: BorderRadius.circular(4),
                            child: const Padding(
                              padding: EdgeInsets.all(4.0),
                              child: Icon(
                                Icons.copy,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _reviewSubmission(
    int teamId,
    String stageLabel,
    String deliverableId,
    String status,
    void Function(void Function()) setDialogState, {
    String? feedback,
  }) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.maroon),
      ),
    );

    try {
      final success = await ref
          .read(capstoneDeliverablesProvider.notifier)
          .reviewDeliverable(
            teamId: teamId,
            stageLabel: stageLabel,
            deliverableId: deliverableId,
            status: status,
            feedback: feedback,
          );

      if (mounted) Navigator.pop(context);

      if (success && mounted) {
        showSuccessToast(context, 'Deliverable review status updated.');
        setDialogState(() {});
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        showErrorToast(context, 'Failed to update review status: $e');
      }
    }
  }

  Future<void> _promptRejectionFeedback(
    int teamId,
    String stageLabel,
    String deliverableId,
    void Function(void Function()) setDialogState, {
    bool isEndorsed = false,
  }) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reject Deliverable & Request Revision'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isEndorsed) ...[
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.danger.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: AppColors.danger,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'WARNING: This team is currently endorsed. Rejecting this required pre-defense deliverable will automatically revoke their endorsement.',
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Text(
              'Please provide feedback or remarks explaining why this deliverable is rejected.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Feedback / Remarks',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isEmpty) {
                showValidationToast(context, 'Remarks are required for rejection.');
                return;
              }
              Navigator.pop(dialogContext, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _reviewSubmission(
        teamId,
        stageLabel,
        deliverableId,
        'rejected',
        setDialogState,
        feedback: controller.text.trim(),
      );
    }
  }

  IconData _getFileIcon(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      return Icons.picture_as_pdf;
    } else if (lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif')) {
      return Icons.image_outlined;
    } else if (lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mkv')) {
      return Icons.video_library_outlined;
    } else if (lowerName.endsWith('.zip') ||
        lowerName.endsWith('.rar') ||
        lowerName.endsWith('.7z')) {
      return Icons.folder_zip_outlined;
    } else if (lowerName.endsWith('.doc') ||
        lowerName.endsWith('.docx')) {
      return Icons.description_outlined;
    } else if (lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pptx')) {
      return Icons.slideshow_outlined;
    } else if (lowerName.endsWith('.xls') ||
        lowerName.endsWith('.xlsx') ||
        lowerName.endsWith('.csv')) {
      return Icons.table_chart_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Color _getFileIconColor(String fileName) {
    final lowerName = fileName.toLowerCase();
    if (lowerName.endsWith('.pdf')) {
      return Colors.red.shade700;
    } else if (lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif')) {
      return Colors.green.shade700;
    } else if (lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mkv')) {
      return Colors.indigo.shade700;
    } else if (lowerName.endsWith('.zip') ||
        lowerName.endsWith('.rar') ||
        lowerName.endsWith('.7z')) {
      return Colors.amber.shade800;
    } else if (lowerName.endsWith('.doc') ||
        lowerName.endsWith('.docx') ||
        lowerName.endsWith('.ppt') ||
        lowerName.endsWith('.pptx') ||
        lowerName.endsWith('.xls') ||
        lowerName.endsWith('.xlsx') ||
        lowerName.endsWith('.csv')) {
      return Colors.blue.shade700;
    }
    return Colors.grey.shade600;
  }

  Future<void> _viewPdf(String fileUrl, String fileName) async {
    if (fileUrl.isEmpty) {
      showErrorToast(context, 'File URL not available');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: AppColors.maroon),
      ),
    );

    try {
      final bytes = await ref
          .read(authenticatedHttpClientProvider)
          .fetchAuthenticatedFile(fileUrl);
      if (mounted) Navigator.pop(context);
      if (!mounted) return;
      await viewFileInDialog(
        context: context,
        fileBytes: bytes,
        fileName: fileName,
      );
    } catch (e) {
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
      if (mounted) {
        showErrorToast(context, 'Error opening file: $e');
      }
    }
  }

  List<Widget> _buildFileList(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    Map<String, dynamic> submission,
    bool locked,
    bool isFaculty,
    bool isAdmin,
    bool endorsed,
    void Function(void Function()) setDialogState,
  ) {
    final filesList = submission['files'] as List? ?? [];
    
    if (filesList.isEmpty) {
      final legacyFile = {
        'id': null,
        'file_name': submission['file_name'] ?? 'document.pdf',
        'file_size': submission['file_size'] ?? '',
        'file_url': submission['file_url'] ?? '',
      };
      return [_buildFileRow(team, stageLabel, item, submission, legacyFile, locked, isFaculty, isAdmin, endorsed, setDialogState)];
    }
    
    return filesList.map((f) {
      final fileMap = Map<String, dynamic>.from(f as Map);
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: _buildFileRow(team, stageLabel, item, submission, fileMap, locked, isFaculty, isAdmin, endorsed, setDialogState),
      );
    }).toList();
  }

  Widget _buildFileRow(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item,
    Map<String, dynamic> submission,
    Map<String, dynamic> fileMap,
    bool locked,
    bool isFaculty,
    bool isAdmin,
    bool endorsed,
    void Function(void Function()) setDialogState,
  ) {
    final fileId = fileMap['id'];
    final fileName = fileMap['file_name']?.toString() ?? 'document.pdf';
    final fileSize = fileMap['file_size']?.toString() ?? '';
    final fileUrl = fileMap['file_url']?.toString() ?? '';
    
    final lowerName = fileName.toLowerCase();
    final isPreviewable = lowerName.endsWith('.pdf') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.webp') ||
        lowerName.endsWith('.gif') ||
        lowerName.endsWith('.mp4') ||
        lowerName.endsWith('.mov') ||
        lowerName.endsWith('.avi') ||
        lowerName.endsWith('.mkv');

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(
            _getFileIcon(fileName),
            size: 16,
            color: _getFileIconColor(fileName),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fileName,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (fileSize.isNotEmpty)
                  Text(
                    fileSize,
                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            iconSize: 18,
            visualDensity: VisualDensity.compact,
            tooltip: isPreviewable ? 'View File' : 'Download File',
            icon: Icon(
              isPreviewable ? Icons.visibility_outlined : Icons.download_outlined,
              color: isPreviewable ? Colors.blue : Colors.green.shade700,
            ),
            onPressed: () => _viewPdf(fileUrl, fileName),
          ),
          if (!isFaculty || isAdmin) ...[
            if (!locked) ...[
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Replace File',
                icon: const Icon(Icons.swap_horiz, color: AppColors.gold),
                onPressed: () => _promptUploadOrReplace(team, stageLabel, item, fileId: fileId),
              ),
              IconButton(
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                tooltip: 'Remove File',
                icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                onPressed: () => _removeFile(team, stageLabel, item, fileId: fileId),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Future<void> _promptUploadOrReplace(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item, {
    int? fileId,
  }) async {
    if (fileId != null) {
      final ok = await confirmDestructive(
        context,
        title: 'Replace file?',
        message: 'The current file will be replaced. This cannot be undone.',
        confirmLabel: 'Replace',
      );
      if (!ok || !mounted) return;
    }
    await _showUploadDialog(team, stageLabel, item, fileId: fileId);
  }

  Future<void> _showUploadDialog(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item, {
    int? fileId,
  }) async {
    String? selectedFileName;
    String? selectedFileSize;
    List<int>? selectedFileBytes;
    bool isUploading = false;
    double uploadProgress = 0.0;
    String? uploadError;

    await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissal during upload
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Upload ${item['id']}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['label']?.toString() ?? ''),
                const SizedBox(height: 14),
                if (!isUploading)
                  OutlinedButton.icon(
                    onPressed: () async {
                      FilePickerResult? result = await FilePicker.platform
                          .pickFiles(
                            type: FileType.custom,
                            allowedExtensions: const ['pdf', 'png', 'jpg', 'jpeg', 'webp', 'gif', 'mp4', 'mov', 'avi', 'mkv', 'zip', 'rar', '7z', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx', 'csv'],
                            withData: true, // Load file bytes
                          );

                      if (result != null &&
                          result.files.single.name.isNotEmpty) {
                        setState(() {
                          selectedFileName = result.files.single.name;
                          selectedFileBytes =
                              result.files.single.bytes; // Store file bytes
                          // Convert bytes to KB
                          final bytes = result.files.single.size;
                          selectedFileSize =
                              '${(bytes / 1024).toStringAsFixed(2)} KB';
                          uploadError = null;
                        });
                      }
                    },
                    icon: const Icon(Icons.attach_file),
                    label: const Text('Choose File'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 48),
                    ),
                  ),
                const SizedBox(height: 16),
                if (selectedFileName != null && !isUploading) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: Colors.green.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          color: Colors.green,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedFileName!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                  ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                selectedFileSize ?? '',
                                style: const TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else if (!isUploading) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'No file selected. Click "Choose File" to select a file.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (isUploading) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: uploadProgress,
                            color: AppColors.success,
                            backgroundColor: AppColors.success.withValues(
                              alpha: 0.12,
                            ),
                            minHeight: 8,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${(uploadProgress * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Uploading ${selectedFileName ?? "file"}...',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
                if (uploadError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    uploadError!,
                    style: const TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isUploading
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: (selectedFileName != null && !isUploading)
                  ? () async {
                      final suggestedName =
                          item['suggested_file_name']?.toString() ?? '';
                      if (item['type'] == 'post' && suggestedName.isNotEmpty) {
                        if (selectedFileName!.trim().toLowerCase() !=
                            suggestedName.trim().toLowerCase()) {
                          setState(() {
                            uploadError =
                                "File name must match the naming convention exactly.\nExpected: '$suggestedName'";
                          });
                          return;
                        }
                      }

                      setState(() {
                        isUploading = true;
                        uploadProgress = 0.0;
                        uploadError = null;
                      });

                      try {
                        final client = ref.read(
                          authenticatedHttpClientProvider,
                        );
                        final uri = Uri.parse(
                          '${ApiConfig.capstoneDeliverablesUrl}/upload/',
                        );

                        final request = MultipartRequestWithProgress(
                          'POST',
                          uri,
                          onProgress: (bytesSent, totalBytes) {
                            if (totalBytes > 0) {
                              setState(() {
                                uploadProgress = bytesSent / totalBytes;
                              });
                            }
                          },
                        );

                        // Add form fields
                        request.fields['team_id'] = team['id'].toString();
                        request.fields['stage_label'] = stageLabel;
                        request.fields['deliverable_id'] = item['id']
                            .toString();
                        request.fields['file_name'] = selectedFileName!;
                        request.fields['file_size'] = selectedFileSize ?? '';
                        if (fileId != null) {
                          request.fields['file_id'] = fileId.toString();
                        }

                        // Add file
                        request.files.add(
                          http.MultipartFile.fromBytes(
                            'file',
                            selectedFileBytes!,
                            filename: selectedFileName!,
                          ),
                        );

                        final response = await client.sendAuthenticated(
                          request,
                        );

                        if (response.statusCode == 200) {
                          // Refresh deliverables list
                          await ref
                              .read(capstoneDeliverablesProvider.notifier)
                              .fetchDeliverables(
                                successMessage:
                                    'Deliverable file uploaded successfully.',
                              );
                          if (context.mounted) {
                            Navigator.pop(dialogContext, true);
                          }
                        } else {
                          final responseBody = await response.stream
                              .bytesToString();
                          setState(() {
                            isUploading = false;
                            uploadError = _formatUploadFailureMessage(
                              response.statusCode,
                              responseBody,
                            );
                          });
                        }
                      } catch (e) {
                        setState(() {
                          isUploading = false;
                          uploadError = 'Upload error: $e';
                        });
                      }
                    }
                  : null,
              child: const Text('Save Upload'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _removeFile(
    Map<String, dynamic> team,
    String stageLabel,
    Map<String, dynamic> item, {
    int? fileId,
  }) async {
    final label =
        item['label']?.toString() ?? item['id']?.toString() ?? 'this file';
    final teamName = team['name']?.toString();
    final message = fileId != null
        ? 'Remove this file? This cannot be undone.'
        : (teamName != null && teamName.isNotEmpty
            ? 'Remove $label for $teamName? This cannot be undone.'
            : 'Remove $label? This cannot be undone.');

    final ok = await confirmDestructive(
      context,
      title: 'Remove file?',
      message: message,
      confirmLabel: 'Remove',
    );
    if (!ok || !mounted) return;

    _pendingRemoveTimer?.cancel();
    _pendingRemoveCancelled = false;
    final payload = {
      'team_id': _asInt(team['id']),
      'stage_label': stageLabel,
      'deliverable_id': item['id'],
      if (fileId != null) 'file_id': fileId,
    };

    showUndoToast(
      context,
      context.l10n.fileRemoved,
      undoLabel: context.l10n.undo,
      onUndo: () {
        _pendingRemoveCancelled = true;
        _pendingRemoveTimer?.cancel();
      },
    );

    _pendingRemoveTimer = Timer(const Duration(seconds: 5), () async {
      if (_pendingRemoveCancelled || !mounted) return;
      final removed = await ref
          .read(capstoneDeliverablesProvider.notifier)
          .removeDeliverable(payload);
      if (mounted && !removed) {
        showErrorToast(context, context.l10n.fileRemoveFailed);
      }
    });
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _buildStageStatusBadge(Map<String, dynamic> stage) {
    final endorsed = stage['endorsed'] == true;
    final archiveUnlocked = stage['archive_unlocked'] == true;
    final requiredComplete = stage['required_complete'] == true;
    final archiveComplete = stage['archive_complete'] == true;

    String text;
    Color bgColor;
    Color textColor;
    IconData icon;

    if (archiveComplete) {
      text = 'Completed';
      bgColor = AppColors.success.withValues(alpha: 0.15);
      textColor = AppColors.success;
      icon = Icons.check_circle;
    } else if (endorsed) {
      text = 'Fully Endorsed';
      bgColor = AppColors.success.withValues(alpha: 0.15);
      textColor = AppColors.success;
      icon = Icons.verified;
    } else if (archiveUnlocked) {
      text = 'Post-Defense Phase';
      bgColor = Colors.blue.withValues(alpha: 0.15);
      textColor = Colors.blue;
      icon = Icons.inventory;
    } else if (requiredComplete) {
      text = 'Pre-Defense Completed';
      bgColor = AppColors.success.withValues(alpha: 0.15);
      textColor = AppColors.success;
      icon = Icons.check_circle;
    } else {
      text = 'Pre-Defense In-Progress';
      bgColor = Colors.orange.withValues(alpha: 0.15);
      textColor = Colors.orange;
      icon = Icons.pending_actions;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: textColor),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    switch (status) {
      case 'stage_completed':
        return _chip('Completed', AppColors.success, icon: Icons.check_circle);
      case 'endorsed':
        return _chip('Endorsed', AppColors.success, icon: Icons.verified);
      case 'complete':
        return _chip('Ready to Endorse', Colors.blue, icon: Icons.check_circle);
      case 'pending_review':
        return _chip('Pending Review', Colors.orange, icon: Icons.rate_review);
      case 'needs_revision':
        return _chip('Needs Revision', AppColors.danger, icon: Icons.assignment_return);
      case 'missing':
      default:
        return _chip('Missing Files', AppColors.warning, icon: Icons.warning_amber);
    }
  }

  Widget _chip(String label, Color color, {IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notice(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFE2E8F0)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.02),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }

  Widget _iconBox(IconData icon, Color color) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color),
    );
  }

  List<Map<String, dynamic>> _stageList(Map<String, dynamic> team) {
    final stages = team['stages'];
    if (stages is! List) {
      return [];
    }
    return stages
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> _stagePayload(
    List<Map<String, dynamic>> stages,
    String stageLabel,
  ) {
    return stages.firstWhere(
      (stage) => stage['stage_label'] == stageLabel,
      orElse: () => stages.isEmpty ? <String, dynamic>{} : stages.first,
    );
  }

  List<Map<String, dynamic>> _deliverables(
    Map<String, dynamic> stage,
    String type,
  ) {
    final rows = stage['deliverables'];
    if (rows is! List) {
      return [];
    }
    return rows
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => item['type'] == type)
        .toList();
  }

  int _count(CapstoneDeliverablesState state, String key) {
    return _asInt(state.counts[key]);
  }

  Future<void> _showApproveWPRDialog(
    Map<String, dynamic> team,
    String stageLabel,
    bool alreadyApproved,
    void Function(void Function()) setDialogState,
  ) async {
    final teamId = team['id']?.toString() ?? '';

    if (teamId.isEmpty) {
      showValidationToast(context, 'Invalid team ID.');
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch fresh weekly progress reports from database for this team
      await ref.read(weeklyProgressProvider.notifier).fetchReports();

      // Get the updated state
      final progressState = ref.read(weeklyProgressProvider);

      // Filter reports for this specific team
      final teamReports = progressState.reports
          .where((r) => r['team'].toString() == teamId)
          .toList();

      // Close loading indicator
      if (mounted) Navigator.pop(context);

      if (teamReports.isEmpty) {
        if (mounted) {
          showValidationToast(
            context,
            'No weekly progress reports found for ${team['name']}. Students must submit reports first.',
          );
        }
        return;
      }

      // Show approval dialog
      if (mounted) {
        final approved = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                Icon(
                  alreadyApproved
                      ? Icons.visibility
                      : Icons.check_circle_outline,
                  color: alreadyApproved ? Colors.blue : AppColors.success,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    alreadyApproved
                        ? 'Weekly Reports - ${team['name']}'
                        : 'Approve Weekly Reports - ${team['name']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 650,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team: ${team['name']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Stage: $stageLabel',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: alreadyApproved
                          ? const Color(0xFFDCFCE7)
                          : const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: alreadyApproved
                            ? const Color(0xFF86EFAC)
                            : const Color(0xFFBAE6FD),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          alreadyApproved
                              ? Icons.check_circle
                              : Icons.info_outline,
                          color: alreadyApproved
                              ? const Color(0xFF166534)
                              : const Color(0xFF0369A1),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            alreadyApproved
                                ? 'PDF compilation of all weekly reports has been generated and submitted. You can view the reports below or download them again.'
                                : 'Review the ${teamReports.length} weekly progress reports submitted by this team. Click "Generate & Submit PDF" to compile all reports into a single PDF document and submit it as the WPR deliverable.',
                            style: TextStyle(
                              color: alreadyApproved
                                  ? const Color(0xFF166534)
                                  : const Color(0xFF0369A1),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Weekly reports submitted (${teamReports.length}):',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _showCompileWPRDialog(team);
                        },
                        icon: const Icon(Icons.folder_zip_outlined, size: 16),
                        label: const Text('Download All'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.maroon,
                          side: const BorderSide(color: AppColors.maroon),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: teamReports.length,
                      itemBuilder: (context, index) {
                        final report = teamReports[index];
                        return Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Week ${report['week_number'] ?? 0}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Date: ${report['report_date'] ?? 'N/A'} • Submitted by: ${report['student_name'] ?? 'Unknown'}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Week ${report['week_number']}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Close'),
              ),
              if (!alreadyApproved)
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  icon: const Icon(Icons.picture_as_pdf),
                  label: Text(
                    'Generate & Submit PDF (${teamReports.length} reports)',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                  ),
                ),
            ],
          ),
        );

        // If approved, generate PDF and save to database
        if (approved == true && mounted) {
          // Show loading indicator
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) =>
                const Center(child: CircularProgressIndicator()),
          );

          try {
            // Call backend API to generate PDF and save as deliverable
            final success = await _generateAndSubmitPDF(
              _asInt(team['id']),
              stageLabel,
            );

            // Close loading indicator
            if (mounted) Navigator.pop(context);

            if (success && mounted) {
              // Refresh the dialog to show updated status
              setDialogState(() {});

              showSuccessToast(
                context,
                'Weekly Progress Reports PDF generated and submitted for ${team['name']}!',
              );
            }
          } catch (e) {
            // Close loading indicator
            if (mounted) Navigator.pop(context);

            if (mounted) {
              showErrorToast(context, 'Error generating PDF: $e');
            }
          }
        }
      }
    } catch (e) {
      // Close loading indicator if still open
      if (mounted) Navigator.pop(context);

      // Show error message
      if (mounted) {
        showErrorToast(context, 'Error fetching weekly reports: $e');
      }
    }
  }

  Future<void> _showCompileWPRDialog(Map<String, dynamic> team) async {
    final teamId = team['id']?.toString() ?? '';

    if (teamId.isEmpty) {
      showValidationToast(context, 'Invalid team ID.');
      return;
    }

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // Fetch fresh weekly progress reports from database for this team
      await ref.read(weeklyProgressProvider.notifier).fetchReports();

      // Get the updated state
      final progressState = ref.read(weeklyProgressProvider);

      // Filter reports for this specific team
      final teamReports = progressState.reports
          .where((r) => r['team'].toString() == teamId)
          .toList();

      // Close loading indicator
      if (mounted) Navigator.pop(context);

      if (teamReports.isEmpty) {
        if (mounted) {
          showValidationToast(
            context,
            'No weekly progress reports found for ${team['name']}.',
          );
        }
        return;
      }

      // Show compilation dialog
      if (mounted) {
        await showDialog(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.folder_zip, color: AppColors.maroon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Compile Weekly Reports - ${team['name']}',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 600,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Team: ${team['name']}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFF0369A1),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'This will generate a compilation report of all ${teamReports.length} weekly progress reports for this team from the database.',
                            style: const TextStyle(
                              color: Color(0xFF0369A1),
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Weekly reports to compile:',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    constraints: const BoxConstraints(maxHeight: 300),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: teamReports.length,
                      itemBuilder: (context, index) {
                        final report = teamReports[index];
                        return Container(
                          padding: const EdgeInsets.all(10),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: const Color(0xFFE5E7EB)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.check_circle,
                                color: AppColors.success,
                                size: 18,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Week ${report['week_number'] ?? 0}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Date: ${report['report_date'] ?? 'N/A'}',
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Week ${report['week_number']}',
                                  style: const TextStyle(
                                    color: Colors.green,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
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
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _downloadWPRCompilation(team, teamReports);
                },
                icon: const Icon(Icons.download),
                label: const Text('Download Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.maroon,
                  foregroundColor: AppColors.gold,
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading indicator if still open
      if (mounted) Navigator.pop(context);

      // Show error message
      if (mounted) {
        showErrorToast(context, 'Error fetching weekly reports: $e');
      }
    }
  }

  void _downloadWPRCompilation(
    Map<String, dynamic> team,
    List<Map<String, dynamic>> reports,
  ) {
    // Generate a simple text report
    final buffer = StringBuffer();
    buffer.writeln('=' * 60);
    buffer.writeln('WEEKLY PROGRESS REPORTS COMPILATION');
    buffer.writeln('=' * 60);
    buffer.writeln();
    buffer.writeln('Team: ${team['name']}');
    buffer.writeln('Project: ${team['project_title'] ?? 'N/A'}');
    buffer.writeln('Section: ${team['year_level'] ?? 'N/A'}');
    buffer.writeln('Generated: ${DateTime.now().toString().substring(0, 19)}');
    buffer.writeln();
    buffer.writeln('=' * 60);
    buffer.writeln('WEEKLY REPORTS (${reports.length})');
    buffer.writeln('=' * 60);
    buffer.writeln();

    for (var i = 0; i < reports.length; i++) {
      final report = reports[i];
      final weekNumber = report['week_number'] ?? 0;
      final reportDate = report['report_date'] ?? 'N/A';
      final studentName = report['student_name'] ?? 'Unknown';
      final submittedAt = report['submitted_at'] ?? 'N/A';

      buffer.writeln('${i + 1}. WEEK $weekNumber');
      buffer.writeln('   Date: $reportDate');
      buffer.writeln('   Submitted by: $studentName');
      buffer.writeln('   Submitted at: $submittedAt');
      buffer.writeln();

      // Accomplishments
      final accomplishments =
          (report['accomplishments'] as List?)?.cast<Map<String, dynamic>>() ??
          [];
      if (accomplishments.isNotEmpty) {
        buffer.writeln('   Accomplishments:');
        for (var acc in accomplishments) {
          buffer.writeln('   - Task: ${acc['task'] ?? 'N/A'}');
          buffer.writeln('     Description: ${acc['description'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Contributions
      final contributions =
          (report['contributions'] as List?)?.cast<Map<String, dynamic>>() ??
          [];
      if (contributions.isNotEmpty) {
        buffer.writeln('   Individual Contributions:');
        for (var contrib in contributions) {
          buffer.writeln(
            '   - ${contrib['member'] ?? 'N/A'}: ${contrib['contribution'] ?? 'N/A'}',
          );
        }
        buffer.writeln();
      }

      // Issues
      final issues =
          (report['issues'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (issues.isNotEmpty) {
        buffer.writeln('   Issues & Actions:');
        for (var issue in issues) {
          buffer.writeln('   - Issue: ${issue['issue'] ?? 'N/A'}');
          buffer.writeln('     Action: ${issue['action'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      // Plans
      final plans =
          (report['plans'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (plans.isNotEmpty) {
        buffer.writeln('   Plans for Next Week:');
        for (var plan in plans) {
          buffer.writeln('   - Task: ${plan['task'] ?? 'N/A'}');
          buffer.writeln('     Expected Output: ${plan['output'] ?? 'N/A'}');
        }
        buffer.writeln();
      }

      buffer.writeln('-' * 60);
      buffer.writeln();
    }

    buffer.writeln('=' * 60);
    buffer.writeln('END OF COMPILATION');
    buffer.writeln('=' * 60);

    // Show success message with view action
    showSuccessToast(
      context,
      'Compilation report generated for ${team['name']}\n'
      '${reports.length} weekly reports compiled.',
      duration: const Duration(seconds: 4),
      action: FeedbackToastAction(
        label: 'View',
        textColor: Colors.white,
        onPressed: () {
          // Show the report in a dialog
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Compilation Report'),
              content: SizedBox(
                width: 600,
                height: 400,
                child: SingleChildScrollView(
                  child: SelectableText(
                    buffer.toString(),
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<bool> _generateAndSubmitPDF(int teamId, String stageLabel) async {
    try {
      final client = ref.read(authenticatedHttpClientProvider);
      final response = await client.post(
        Uri.parse(
          '${ApiConfig.capstoneDeliverablesUrl}/compile-weekly-reports/',
        ),
        body: jsonEncode({'team_id': teamId, 'stage_label': stageLabel}),
      );

      if (response.statusCode == 200) {
        jsonDecode(response.body);

        // Refresh deliverables to show the new PDF submission
        await ref
            .read(capstoneDeliverablesProvider.notifier)
            .fetchDeliverables();

        return true;
      } else {
        final error = jsonDecode(response.body);
        throw Exception(error['error'] ?? 'Failed to generate PDF');
      }
    } catch (e) {
      rethrow;
    }
  }

  Widget _expandedTabButton(int teamId, int tabIndex, String label) {
    final activeTab = _cardActiveTabs[teamId] ?? 0;
    final isActive = activeTab == tabIndex;
    return InkWell(
      onTap: () {
        setState(() {
          _cardActiveTabs[teamId] = tabIndex;
        });
      },
      child: Container(
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: isActive
              ? const Border(
                  bottom: BorderSide(
                    color: AppColors.maroon,
                    width: 2,
                  ),
                )
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            color: isActive ? AppColors.maroon : AppColors.textSecondary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _assignedRubricFromGrade(Map<String, dynamic> grade) {
    final rubricId = grade['assigned_adviser_rubric_id'];
    if (rubricId == null) {
      return null;
    }
    final criteria = grade['assigned_adviser_criteria'];
    return {
      'id': rubricId,
      'name': grade['assigned_adviser_rubric_name']?.toString() ?? 'Adviser rubric',
      'scale': grade['assigned_adviser_rubric_scale'],
      'criteria': criteria is List ? criteria : [],
    };
  }

  void _initializeGradingControllersForTeam(int teamId, String stageLabel, Map<String, dynamic> gradeRecord) {
    final key = '$teamId-$stageLabel';
    if (_teamManualScoreCtrls.containsKey(key)) {
      return; // Already initialized for this team and stage
    }

    final manualCtrl = TextEditingController();
    final existing = gradeRecord['adviser_score'];
    if (existing != null) {
      manualCtrl.text = existing.toString();
    }
    _teamManualScoreCtrls[key] = manualCtrl;

    final criteriaCtrls = <String, TextEditingController>{};
    final assigned = _assignedRubricFromGrade(gradeRecord);
    _teamSelectedRubrics[key] = assigned;

    if (assigned != null) {
      final savedScores = <String, String>{};
      if (gradeRecord['breakdowns'] is List) {
        for (final row in gradeRecord['breakdowns'] as List) {
          if (row is! Map) continue;
          if (row['evaluation_type']?.toString() != 'adviser') continue;
          final name = row['criterion_name']?.toString() ?? '';
          if (name.isNotEmpty) {
            savedScores[name] = row['score']?.toString() ?? '';
          }
        }
      }

      for (final c in (assigned['criteria'] as List? ?? [])) {
        final cMap = c as Map;
        final name = cMap['name']?.toString() ?? '';
        criteriaCtrls[name] = TextEditingController(text: savedScores[name] ?? '');
      }
    }
    _teamCriteriaScoreCtrls[key] = criteriaCtrls;
  }

  double _computeTotalScoreForTeam(int teamId, String stageLabel) {
    final key = '$teamId-$stageLabel';
    final rubric = _teamSelectedRubrics[key];
    if (rubric == null) return 0;
    final criteria = (rubric['criteria'] as List? ?? []);
    if (criteria.isEmpty) return 0;
    double total = 0;
    double maxTotal = 0;
    final subMap = _teamCriteriaScoreCtrls[key] ?? const {};
    for (final c in criteria) {
      final name = (c as Map)['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final entered = double.tryParse(subMap[name]?.text ?? '') ?? 0;
      total += entered.clamp(0, maxScore);
      maxTotal += maxScore;
    }
    if (maxTotal == 0) return 0;
    return (total / maxTotal * 100).clamp(0, 100);
  }

  bool _allCriteriaFilledForTeam(int teamId, String stageLabel) {
    final key = '$teamId-$stageLabel';
    final rubric = _teamSelectedRubrics[key];
    if (rubric == null) return false;
    final criteria = (rubric['criteria'] as List? ?? []);
    if (criteria.isEmpty) return false;
    final subMap = _teamCriteriaScoreCtrls[key] ?? const {};
    for (final c in criteria) {
      final name = (c as Map)['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = subMap[name]?.text.trim() ?? '';
      if (text.isEmpty) return false;
      final value = double.tryParse(text);
      if (value == null || value < 0 || value > maxScore) return false;
    }
    return true;
  }

  int _filledCountForTeam(int teamId, String stageLabel) {
    final key = '$teamId-$stageLabel';
    final rubric = _teamSelectedRubrics[key];
    if (rubric == null) return 0;
    final criteria = (rubric['criteria'] as List? ?? []);
    int count = 0;
    final subMap = _teamCriteriaScoreCtrls[key] ?? const {};
    for (final c in criteria) {
      final name = (c as Map)['name']?.toString() ?? '';
      final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
      final text = subMap[name]?.text.trim() ?? '';
      final value = double.tryParse(text);
      if (text.isNotEmpty && value != null && value >= 0 && value <= maxScore) count++;
    }
    return count;
  }

  Future<void> _submitAdviserGrade({
    required int teamId,
    required String stageLabel,
    required Map<String, dynamic> gradeRecord,
  }) async {
    final key = '$teamId-$stageLabel';
    final gradeId = gradeRecord['id'] as int?;
    if (gradeId == null) {
      showErrorToast(context, 'No grading record available for this team and stage.');
      return;
    }

    final rubric = _teamSelectedRubrics[key];
    final subMap = _teamCriteriaScoreCtrls[key] ?? const {};
    final manualCtrl = _teamManualScoreCtrls[key];

    double adviserScore;
    List<Map<String, dynamic>> criteriaScores = [];
    int? rubricId;

    if (rubric != null) {
      final criteria = (rubric['criteria'] as List? ?? []);
      for (final c in criteria) {
        final cMap = c as Map;
        final name = cMap['name']?.toString() ?? '';
        final maxScore = ((cMap['max_score'] as num?) ?? 10).toDouble();
        final entered = (double.tryParse(subMap[name]?.text ?? '') ?? 0).clamp(0, maxScore);
        criteriaScores.add({
          'criterion_name': name,
          'score': entered,
          'max_score': maxScore,
          'display_order': cMap['display_order'] ?? 0,
        });
      }
      adviserScore = _computeTotalScoreForTeam(teamId, stageLabel);
      rubricId = rubric['id'] as int?;
    } else {
      if (manualCtrl == null) return;
      adviserScore = double.tryParse(manualCtrl.text) ?? 0;
      adviserScore = adviserScore.clamp(0, 100);
    }

    final success = await ref.read(adviserGradingProvider.notifier).submitGrade(
          gradeId: gradeId,
          adviserScore: adviserScore,
          rubricId: rubricId,
          criteriaScores: criteriaScores,
        );

    if (success && mounted) {
      showSuccessToast(context, 'Grade submitted successfully!');
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
    }
  }

  Widget _buildGradesAndRubricTab(Map<String, dynamic> team, String selectedStage) {
    final teamId = _asInt(team['id']);
    final gradingState = ref.watch(adviserGradingProvider);
    
    final gradeRecord = gradingState.grades.firstWhere(
      (g) => _asInt(g['team_id']) == teamId && g['stage_label']?.toString() == selectedStage,
      orElse: () => team['grade'] is Map ? Map<String, dynamic>.from(team['grade'] as Map) : <String, dynamic>{},
    );

    // Initialize scoring controllers for this team/stage
    _initializeGradingControllersForTeam(teamId, selectedStage, gradeRecord);

    final status = gradeRecord['status']?.toString() ?? 'pending';
    final panelScore = gradeRecord['panel_score'];
    final peerScore = gradeRecord['peer_score'];
    final adviserScore = gradeRecord['adviser_score'];
    final finalGrade = gradeRecord['final_grade'];
    final result = gradeRecord['result']?.toString() ?? 'pending';

    final scheduleId = gradeRecord['schedule_id'];
    final rawScheduledDate = gradeRecord['scheduled_date'];

    DateTime? scheduledDate;
    if (rawScheduledDate != null) {
      scheduledDate = DateTime.tryParse(rawScheduledDate.toString());
    }

    bool isLockedBySchedule = false;
    String lockReason = '';

    if (scheduleId == null) {
      isLockedBySchedule = true;
      lockReason = "Adviser grading is locked because this team's defense has not been scheduled yet.";
    } else {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (scheduledDate != null && today.isBefore(scheduledDate)) {
        final formattedDate = "${scheduledDate.year}-${scheduledDate.month.toString().padLeft(2, '0')}-${scheduledDate.day.toString().padLeft(2, '0')}";
        isLockedBySchedule = true;
        lockReason = "Adviser grading is locked until the scheduled defense date: $formattedDate.";
      }
    }

    Color statusBg = const Color(0xFFFEF3C7);
    Color statusText = const Color(0xFFD97706);
    String statusLabel = 'Pending';

    if (status == 'published') {
      statusBg = const Color(0xFFD1FAE5);
      statusText = const Color(0xFF047857);
      statusLabel = 'Published';
    } else if (status == 'awaiting_peers') {
      statusBg = const Color(0xFFDBEAFE);
      statusText = const Color(0xFF2563EB);
      statusLabel = 'Awaiting Peers';
    }

    final key = '$teamId-$selectedStage';
    final assignedRubric = _teamSelectedRubrics[key];
    final isAlreadyGraded = adviserScore != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Overall Grade Badges
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Grade Overview',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  color: statusText,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _gradeBadge('Panel', panelScore),
            _gradeBadge('Peer', peerScore),
            _gradeBadge('Adviser', adviserScore),
            _overallGradeBadge(finalGrade, result),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(color: Color(0xFFF1F5F9), height: 1),
        const SizedBox(height: 16),

        // Rubric Grading Form
        if (widget.isAdviser) ...[
          if (!gradingState.adviserGradingEnabled) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.textSecondary),
                  SizedBox(height: 12),
                  Text(
                    'Adviser Grading is Disabled',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Adviser grading is currently turned off by the administrator for this stage/period.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ] else if (isLockedBySchedule) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.lock_outline_rounded, size: 48, color: AppColors.textSecondary),
                  const SizedBox(height: 12),
                  const Text(
                    'Adviser Grading is Locked',
                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    lockReason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
          ] else if (assignedRubric == null) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No adviser rubric is assigned for this defense stage yet. Ask your administrator to set panel, adviser, and peer rubrics in Defense Stages Setup or the scheduler.',
                      style: TextStyle(color: AppColors.warning, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Row(
              children: [
                _sectionTitle('Rubric: ${assignedRubric['name']} (${assignedRubric['scale'] ?? ''})'),
                const Spacer(),
                Builder(builder: (_) {
                  final total = (assignedRubric['criteria'] as List? ?? []).length;
                  final filled = _filledCountForTeam(teamId, selectedStage);
                  final allDone = filled == total && total > 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: allDone
                          ? AppColors.success.withValues(alpha: 0.1)
                          : AppColors.warning.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '$filled / $total scored',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: allDone ? AppColors.success : AppColors.warning,
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 10),
            _buildCriteriaTableForTeam(teamId, selectedStage, assignedRubric),
            const SizedBox(height: 16),
            // Computed score
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.maroon.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.maroon.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Text(
                    'Computed Adviser Score:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                  ),
                  const Spacer(),
                  Text(
                    _computeTotalScoreForTeam(teamId, selectedStage).toStringAsFixed(2),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.maroon),
                  ),
                  const Text(' / 100', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Submit Button
            Builder(builder: (_) {
              final canSubmit = _allCriteriaFilledForTeam(teamId, selectedStage);
              return SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (gradingState.isSaving || !canSubmit)
                      ? null
                      : () => _submitAdviserGrade(
                            teamId: teamId,
                            stageLabel: selectedStage,
                            gradeRecord: gradeRecord,
                          ),
                  icon: gradingState.isSaving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.save_rounded, size: 14),
                  label: Text(isAlreadyGraded ? 'Update Adviser Grade' : 'Submit Adviser Grade'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canSubmit ? AppColors.maroon : Colors.grey.shade300,
                    foregroundColor: canSubmit ? Colors.white : Colors.grey.shade500,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                ),
              );
            }),
          ],
        ],
      ],
    );
  }

  Widget _buildCriteriaTableForTeam(int teamId, String stageLabel, Map<String, dynamic> rubric) {
    final criteria = (rubric['criteria'] as List? ?? []);
    if (criteria.isEmpty) {
      return const Text(
        'This rubric has no criteria defined.',
        style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
      );
    }

    final key = '$teamId-$stageLabel';
    final subMap = _teamCriteriaScoreCtrls[key] ?? const {};

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: criteria.asMap().entries.map((entry) {
          final i = entry.key;
          final c = entry.value as Map;
          final name = c['name']?.toString() ?? '';
          final desc = c['description']?.toString() ?? '';
          final maxScore = ((c['max_score'] as num?) ?? 10).toDouble();
          final ctrl = subMap[name] ?? TextEditingController();

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: i < criteria.length - 1
                  ? const Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.5))
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                      ),
                      if (desc.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          desc,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text('/ $maxScore', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 12),
                SizedBox(
                  width: 80,
                  child: TextField(
                    controller: ctrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: 'Score',
                      hintStyle: const TextStyle(fontSize: 11),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _gradeBadge(String label, dynamic score) {
    final parsedScore = _asDouble(score);
    final hasScore = parsedScore != null;
    final valueText = hasScore ? parsedScore.toStringAsFixed(2) : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: hasScore ? const Color(0xFFF3F4F6) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasScore ? const Color(0xFFE5E7EB) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          Text(
            valueText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: hasScore ? AppColors.textPrimary : const Color(0xFFB45309),
            ),
          ),
        ],
      ),
    );
  }

  Widget _overallGradeBadge(dynamic score, String result) {
    final parsedScore = _asDouble(score);
    final hasScore = parsedScore != null;
    final valueText = hasScore ? parsedScore.toStringAsFixed(2) : 'Pending';

    Color bg = const Color(0xFFF3F4F6);
    Color border = const Color(0xFFE5E7EB);
    Color text = AppColors.textPrimary;

    if (hasScore) {
      if (result == 'passed') {
        bg = const Color(0xFFECFDF5);
        border = const Color(0xFFA7F3D0);
        text = const Color(0xFF047857);
      } else {
        bg = const Color(0xFFFEF2F2);
        border = const Color(0xFFFCA5A5);
        text = const Color(0xFFB91C1C);
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Overall Grade: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          Text(
            valueText,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: text,
            ),
          ),
          if (hasScore) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: result == 'passed' ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                result == 'passed' ? 'PASSED' : 'FAILED',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: result == 'passed' ? const Color(0xFF065F46) : const Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRosterAndIndividualGrades(Map<String, dynamic> team, Map<String, dynamic>? grade) {
    final List<dynamic> members = team['members'] as List? ?? [];
    final List<dynamic> peerGrades = grade?['peer_per_student'] as List? ?? [];

    if (members.isEmpty) {
      return const Text(
        'No members assigned to this team.',
        style: TextStyle(color: AppColors.textSecondary, fontStyle: FontStyle.italic),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF3F4F6)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: members.length,
        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE5E7EB)),
        itemBuilder: (context, index) {
          final rawMember = members[index];
          if (rawMember is! Map) return const SizedBox.shrink();
          final member = Map<String, dynamic>.from(rawMember);
          final studentId = member['id'];
          final name = member['name']?.toString() ?? member['username']?.toString() ?? 'Student';
          final role = member['role']?.toString() ?? 'member';
          final isLeader = role == 'leader';

          final peerDetails = peerGrades.firstWhere(
            (g) => g is Map && g['student_id'] == studentId,
            orElse: () => null,
          );

          final double? avgScore = _asDouble(peerDetails?['average_score']);
          final double maxScore = _asDouble(peerDetails?['max_score']) ?? 5.0;
          final double? normScore = _asDouble(peerDetails?['normalized_score']);

          final sanitizedName = name.trim().replaceAll(RegExp(r'\s+'), ' ');
          final parts = sanitizedName.split(' ');
          final initials = parts.isNotEmpty
              ? (parts.first.isNotEmpty ? parts.first[0] : '') +
                  (parts.length > 1 && parts.last.isNotEmpty ? parts.last[0] : '')
              : '';

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.maroon.withValues(alpha: 0.1),
                  child: Text(
                    initials.toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.maroon,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (isLeader) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.gold.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'Leader',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.gold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        member['username']?.toString() ?? '',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (avgScore != null) ...[
                            Text(
                              'Peer Score: ${avgScore.toStringAsFixed(2)} / ${maxScore.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Normalized: ${normScore?.toStringAsFixed(2)}%',
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ] else ...[
                            const Text(
                              'Peer Score: Pending',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildExpandedSection(
    Map<String, dynamic> team,
    CapstoneDeliverablesState state,
  ) {
    final teamId = _asInt(team['id']);
    final stages = _stageList(team);
    final selectedStage = _cardSelectedStages[teamId] ?? state.selectedStage;

    final stage = _stagePayload(stages, selectedStage);
    final pre = _deliverables(stage, 'pre');
    final vault = _deliverables(stage, 'post');

    final configured = stage['deliverables_configured'] == true;
    final complete = stage['required_complete'] == true;
    final endorsed = stage['endorsed'] == true;
    final canEndorse = configured && complete && !endorsed;

    final activeTab = _cardActiveTabs[teamId] ?? 0;

    final gradingState = ref.watch(adviserGradingProvider);
    final gradeRecord = gradingState.grades.firstWhere(
      (g) => _asInt(g['team_id']) == teamId && g['stage_label']?.toString() == selectedStage,
      orElse: () => team['grade'] is Map ? Map<String, dynamic>.from(team['grade'] as Map) : <String, dynamic>{},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Inline Tab Swapping (Moved to the very top)
        Container(
          height: 38,
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: Row(
            children: [
              _expandedTabButton(teamId, 0, '📁 Deliverables'),
              const SizedBox(width: 20),
              _expandedTabButton(teamId, 1, '📊 Grades & Rubric'),
              const SizedBox(width: 20),
              _expandedTabButton(teamId, 2, '👥 Team Roster'),
              if (state.scope == 'capstone') ...[
                const SizedBox(width: 20),
                _expandedTabButton(teamId, 3, '📅 Weekly Reports'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (activeTab == 0) ...[
          // 1. Unified Stage Overview Card (All metrics and documents nested within)
          if (stages.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Defense Stage Overview',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                          color: AppColors.textSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      _buildStageStatusBadge(stage),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: stages.map((item) {
                      final label = item['stage_label']?.toString() ?? '';
                      final active = label == selectedStage;

                      final isStageComplete = item['required_complete'] == true;
                      final isStageEndorsed = item['endorsed'] == true;

                      Widget labelWidget = Text(label);
                      if (isStageEndorsed) {
                        labelWidget = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.verified, size: 14, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text(label),
                          ],
                        );
                      } else if (isStageComplete) {
                        labelWidget = Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.check_circle_outline, size: 14, color: Colors.blue),
                            const SizedBox(width: 4),
                            Text(label),
                          ],
                        );
                      }

                      return ChoiceChip(
                        label: labelWidget,
                        selected: active,
                        selectedColor: AppColors.maroon.withValues(alpha: 0.15),
                        backgroundColor: const Color(0xFFF1F5F9),
                        labelStyle: TextStyle(
                          fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          color: active ? AppColors.maroon : AppColors.textPrimary,
                          fontSize: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: active ? AppColors.maroon : const Color(0xFFCBD5E1),
                          ),
                        ),
                        onSelected: (_) {
                          setState(() {
                            _cardSelectedStages[teamId] = label;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Divider(color: Color(0xFFF1F5F9), height: 1),
                  ),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final useVerticalLayout = constraints.maxWidth < 600;
                      final requiredUploaded = _asInt(stage['required_uploaded']);
                      final requiredTotal = _asInt(stage['required_total']);
                      final configured = stage['deliverables_configured'] == true;
                      final archiveUnlocked = stage['archive_unlocked'] == true;

                      final reqBlock = Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: _requiredProgressBlock(
                          configured: configured,
                          done: requiredUploaded,
                          total: requiredTotal,
                        ),
                      );

                      if (!archiveUnlocked) {
                        return reqBlock;
                      }

                      final archiveBlock = Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFF1F5F9)),
                        ),
                        child: _archiveProgressBlock(stage),
                      );

                      if (useVerticalLayout) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            reqBlock,
                            const SizedBox(height: 12),
                            archiveBlock,
                          ],
                        );
                      }

                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: reqBlock),
                          const SizedBox(width: 16),
                          Expanded(child: archiveBlock),
                        ],
                      );
                    },
                  ),

                  // Divider between metrics and nested requirements checklists
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Divider(color: Color(0xFFE2E8F0), height: 1),
                  ),

                  // 2. Pre-Defense Requirements Checklist
                  _sectionTitle('Pre-Defense Requirements'),
                  const SizedBox(height: 8),
                  if (pre.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        'No pre-defense requirements configured.',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontStyle: FontStyle.italic,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    ...pre.map(
                      (item) => _deliverableRow(
                        team,
                        selectedStage,
                        item,
                        (fn) => setState(fn),
                      ),
                    ),

                  // 3. Post-Defense Deliverables Checklist (Only nested when archive is unlocked/defense is done)
                  if (stage['archive_unlocked'] == true) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(color: Color(0xFFE2E8F0), height: 1),
                    ),
                    _sectionTitle('Post-Defense Deliverables'),
                    const SizedBox(height: 8),
                    if (vault.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No post-defense deliverables configured.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                          ),
                        ),
                      )
                    else
                      ...vault.map(
                        (item) => _deliverableRow(
                          team,
                          selectedStage,
                          item,
                          (fn) => setState(fn),
                        ),
                      ),
                  ],
                  if (canEndorse) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(color: Color(0xFFE2E8F0), height: 1),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: state.isSaving
                            ? null
                            : () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (dialogContext) => AlertDialog(
                                    title: const Text('Endorse Team'),
                                    content: Text(
                                      'Endorse ${team['name']} for $selectedStage? '
                                      'This confirms all required deliverables are complete '
                                      'and the team is ready for defense scheduling.',
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, false),
                                        child: const Text('Cancel'),
                                      ),
                                      ElevatedButton.icon(
                                        onPressed: () =>
                                            Navigator.pop(dialogContext, true),
                                        icon: const Icon(Icons.verified_outlined),
                                        label: const Text('Endorse'),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.success,
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && mounted) {
                                  await ref
                                      .read(capstoneDeliverablesProvider.notifier)
                                      .endorseTeam(
                                        _asInt(team['id']),
                                        selectedStage,
                                      );
                                }
                              },
                        icon: const Icon(Icons.verified_outlined, size: 16),
                        label: const Text(
                          'Endorse Team',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.maroon,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ] else if (activeTab == 1) ...[
          _buildGradesAndRubricTab(team, selectedStage),
        ] else if (activeTab == 2) ...[
          _buildRosterAndIndividualGrades(team, gradeRecord),
        ] else ...[
          _buildWeeklyReportsTab(teamId.toString()),
        ],
      ],
    );
  }

  Widget _buildWeeklyReportsTab(String teamId) {
    return SizedBox(
      height: 650,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFE2E8F0)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: WeeklyProgressReportsScreen(
            embeddedTeamId: teamId,
          ),
        ),
      ),
    );
  }

  int _asInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}
