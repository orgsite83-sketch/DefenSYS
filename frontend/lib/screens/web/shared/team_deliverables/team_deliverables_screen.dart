import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/weekly_progress_provider.dart';
import 'package:defensys/services/defense/adviser_defense_provider.dart';
import 'package:defensys/services/defense/team_defense_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/theme/defensys_tokens.dart';
import 'package:defensys/theme/defensys_button_styles.dart';
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'components/deliverables_filter_bar.dart';
import 'components/deliverables_table.dart';
import 'components/faculty_teams_overview_export.dart';
import 'components/cohort_submissions_matrix.dart';
import 'deliverables_view_types.dart';
import '../../admin/student_teams/team_creation_page.dart';
export 'deliverables_view_types.dart';

Widget _notice(IconData icon, String message, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

bool _stageNotConfigured(CapstoneDeliverablesState state) {
  if (state.stageOptions.isEmpty || state.selectedStage.isEmpty) return true;
  if (state.teams.isNotEmpty) {
    for (final team in state.teams) {
      final stages = team['stages'];
      if (stages is List) {
        for (final s in stages) {
          if (s is Map && s['stage_label']?.toString() == state.selectedStage) {
            if (s['deliverables_configured'] == true) return false;
          }
        }
      }
    }
  }
  final counts = state.counts;
  final configured = counts['deliverables_configured'] == true ||
      (counts['deliverables_configured'] is int &&
          counts['deliverables_configured'] == 1);
  return !configured;
}

class TeamDeliverablesScreen extends ConsumerStatefulWidget {
  final String? initialScope;
  final bool isAdviser;
  final bool isPitInstructor;
  final String? pitYearLevel;
  final String? pitSection;
  final int? initialTeamId;
  final int? initialTab;
  final String? initialStage;
  final DeliverablesViewMode? initialViewMode;

  const TeamDeliverablesScreen({
    super.key,
    this.initialScope,
    this.isAdviser = false,
    this.isPitInstructor = false,
    this.pitYearLevel,
    this.pitSection,
    this.initialTeamId,
    this.initialStage,
    this.initialTab,
    this.initialViewMode,
  });

  @override
  ConsumerState<TeamDeliverablesScreen> createState() =>
      _TeamDeliverablesScreenState();
}

class _TeamDeliverablesScreenState
    extends ConsumerState<TeamDeliverablesScreen> {
  final _searchController = TextEditingController();
  late DeliverablesViewMode _viewMode;
  TeamTriageFilter _triageFilter = TeamTriageFilter.all;
  int? _activeTeamId;

  @override
  void initState() {
    super.initState();
    _activeTeamId = widget.initialTeamId;
    final isEvaluator = widget.isAdviser || widget.isPitInstructor;
    _viewMode = widget.initialViewMode ??
        (isEvaluator ? DeliverablesViewMode.dossier : DeliverablesViewMode.matrix);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
        workspace: widget.isAdviser ? 'adviser' : widget.isPitInstructor ? 'instructor' : 'operations',
        search: widget.initialTeamId != null ? '' : null,
        status: widget.initialTeamId != null ? '' : null,
        scope: widget.initialScope,
        selectedStage: widget.initialStage,
        yearLevel: widget.pitYearLevel ?? '',
        section: widget.pitSection ?? '',
      );
      ref.read(adviserGradingProvider.notifier).fetchAll();
      ref.read(weeklyProgressProvider.notifier).fetchReports();
      if (widget.isAdviser) {
        ref.read(adviserDefenseProvider.notifier).fetch(workspace: 'adviser');
      } else if (widget.isPitInstructor) {
        ref.read(pitInstructorDefenseProvider.notifier).fetch();
      }
    });
  }

  @override
  void didUpdateWidget(covariant TeamDeliverablesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialViewMode != null &&
        widget.initialViewMode != oldWidget.initialViewMode) {
      _viewMode = widget.initialViewMode!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openCreation({bool importTab = false}) async {
    final state = ref.read(capstoneDeliverablesProvider);
    final saved = await openTeamCreation(context, importTab: importTab,
      level: widget.pitYearLevel == null ? null : '${widget.pitYearLevel} PIT',
      section: widget.pitSection, event: state.selectedStage);
    if (saved == true && mounted) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
      ref.read(pitInstructorDefenseProvider.notifier).fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(capstoneDeliverablesProvider);
    final isWide = MediaQuery.of(context).size.width >= 900;
    final isEvaluator = widget.isAdviser || widget.isPitInstructor;
    final isPit = widget.initialScope == 'pit' ||
        widget.pitYearLevel != null ||
        widget.pitSection != null ||
        state.scope == 'pit';
    final showViewToggle = isEvaluator && (state.teams.length >= 3 || widget.isPitInstructor);

    final String pageTitle;
    final String pageSubtitle;
    if (widget.isPitInstructor) {
      pageTitle = 'PIT Teams';
      pageSubtitle = widget.pitSection != null
          ? 'Section ${widget.pitSection} · Evaluation & Stage Deliverables'
          : (state.activeSemester?['display_name']?.toString() ?? 'Active Semester');
    } else if (widget.isAdviser) {
      pageTitle = 'Capstone Teams';
      pageSubtitle = state.activeSemester?['display_name']?.toString() ?? 'Active Semester';
    } else if (isPit) {
      pageTitle = 'PIT Cohort Deliverables';
      pageSubtitle = widget.pitYearLevel != null
          ? '${widget.pitYearLevel} Cohort · Deliverables Tracking & Reminders'
          : (state.activeSemester?['display_name']?.toString() ?? 'Active Semester');
    } else {
      pageTitle = 'Capstone Cohort Deliverables';
      pageSubtitle = 'All Teams · Deliverables Tracking & Reminders';
    }

    final filteredTeams = DeliverablesTriageHelper.reviewFirst(state.teams
        .where((t) => DeliverablesTriageHelper.matchesFilter(t, _triageFilter)));

    final pendingCount = state.teams.fold<int>(0,
        (count, team) => count + DeliverablesTriageHelper.pendingReviewCount(team));
    final reviewTeamCount = state.teams.where(DeliverablesTriageHelper.hasPendingReview).length;
    final content = SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DefensysPageHeader(
            programScope: isPit ? 'pit' : 'capstone',
            icon: Icons.folder_open_outlined,
            title: pageTitle,
            subtitle: pageSubtitle,
            actions: Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Tooltip(
                  message: 'Refresh',
                  child: OutlinedButton.icon(
                    onPressed: state.isSaving
                        ? null
                        : () {
                            ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
                            if (widget.isAdviser) {
                              ref.read(adviserDefenseProvider.notifier).fetch();
                              ref.read(adviserGradingProvider.notifier).fetchAll();
                            } else if (widget.isPitInstructor) {
                              ref.read(pitInstructorDefenseProvider.notifier).fetch();
                              ref.read(adviserGradingProvider.notifier).fetchAll();
                            }
                          },
                    style: DefensysButtonStyles.secondary(context),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Refresh'),
                  ),
                ),
                if (widget.isPitInstructor) ...[
                  OutlinedButton.icon(
                    onPressed: state.isSaving ? null : () => _openCreation(importTab: true),
                    style: DefensysButtonStyles.secondary(context),
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('Import'),
                  ),
                  ElevatedButton.icon(
                    onPressed: state.isSaving ? null : () => _openCreation(),
                    style: DefensysButtonStyles.primary(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Team Creation'),
                  ),
                ],
              ],
            ),
          ),
          if (state.error != null) ...[
            const SizedBox(height: 12),
            _notice(Icons.error_outline, state.error!, AppColors.danger),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 12),
            _notice(Icons.check_circle_outline, state.message!, AppColors.success),
          ],
          if (_stageNotConfigured(state)) ...[
            const SizedBox(height: 12),
            _notice(
              Icons.info_outline,
              state.scope == 'pit'
                  ? (state.stageOptions.isEmpty
                      ? 'No PIT events configured for this semester or year level. Add them in PIT Events Setup.'
                      : 'No deliverables configured for ${state.selectedStage}. Add them in PIT Events Setup.')
                  : widget.isAdviser
                      ? (state.stageOptions.isEmpty
                          ? 'No defense stages configured.'
                          : 'No deliverables configured for ${state.selectedStage}.')
                      : (state.stageOptions.isEmpty
                          ? 'No defense stages configured. Add them in Defense Stages Setup.'
                          : 'No deliverables configured for ${state.selectedStage}. Add them in Defense Stages Setup so Required progress can be tracked.'),
              AppColors.gold,
            ),
          ],
          const SizedBox(height: 16),
          DeliverablesFilterBar(
            state: state,
            searchController: _searchController,
            isAdviser: isEvaluator,
            viewMode: _viewMode,
            onViewModeChanged: (mode) {
              setState(() {
                _viewMode = mode;
              });
            },
            activeTriageFilter: _triageFilter,
            onTriageFilterChanged: (filter) {
              setState(() {
                _triageFilter = filter;
              });
            },
            showViewToggle: showViewToggle,
          ),
          const SizedBox(height: 16),
          if (!state.isLoading && pendingCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(LucideIcons.clock, size: 16, color: Color(0xFF1D4ED8)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '$pendingCount ${pendingCount == 1 ? 'submission' : 'submissions'} awaiting review across '
                      '$reviewTeamCount ${reviewTeamCount == 1 ? 'team' : 'teams'}. Teams needing review appear first.',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1D4ED8),
                      ),
                    ),
                  ),
                  ShadButton.ghost(
                    size: ShadButtonSize.sm,
                    foregroundColor: const Color(0xFF1D4ED8),
                    hoverBackgroundColor: const Color(0xFFDBEAFE),
                    trailing: const Icon(LucideIcons.arrowRight, size: 14),
                    onPressed: () => setState(() {
                      _triageFilter = TeamTriageFilter.needsReview;
                      _activeTeamId = int.tryParse(DeliverablesTriageHelper.reviewFirst(state.teams).first['id'].toString());
                      if (isEvaluator) {
                        _viewMode = DeliverablesViewMode.dossier;
                      }
                    }),
                    child: const Text('View submissions', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          state.isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              : (_viewMode == DeliverablesViewMode.matrix
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.isAdviser || widget.isPitInstructor) ...[
                          FacultyTeamsOverviewExport(
                            teams: filteredTeams,
                            workspace: widget.isAdviser ? 'adviser' : 'pit_instructor',
                            selectedStage: state.selectedStage,
                          ),
                          const SizedBox(height: 12),
                        ],
                        CohortSubmissionsMatrix(
                          teams: filteredTeams,
                          state: state,
                          isAdviser: isEvaluator,
                          initialExpandedTeamId: _activeTeamId ?? widget.initialTeamId,
                          onSelectTeam: (teamId) {
                            setState(() {
                              _activeTeamId = teamId;
                              if (isEvaluator) {
                                _viewMode = DeliverablesViewMode.dossier;
                              }
                            });
                          },
                        )
                      ],
                    )
                  : DeliverablesTablePane(
                      state: state,
                      isAdviser: widget.isAdviser,
                      isPitInstructor: widget.isPitInstructor,
                      key: ValueKey(_activeTeamId),
                      initialTeamId: _activeTeamId ?? widget.initialTeamId,
                      initialTab: widget.initialTab,
                      activeTriageFilter: _triageFilter,
                    )),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: DefensysTokens.backgroundOf(context),
      appBar: null,
      body: DefensysShadcnScope(
        child: isWide
            ? content
            : RefreshIndicator(
                onRefresh: () =>
                    ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(),
                child: content,
              ),
      ),
    );
  }
}

