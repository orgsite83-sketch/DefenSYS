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
import 'package:defensys/widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'components/deliverables_filter_bar.dart';
import 'components/deliverables_table.dart';
import 'components/faculty_teams_overview_export.dart';
import 'components/cohort_submissions_matrix.dart';
import 'deliverables_view_types.dart';
import 'package:defensys/widgets/repository/section_concept_workspace.dart';
import 'package:defensys/widgets/repository/requirement_summary.dart';
import 'package:defensys/models/team_workflow_status.dart';
import '../../faculty/team_roster_screen.dart';
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
  final configured =
      counts['deliverables_configured'] == true ||
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
  bool _showConceptReview = false;
  int? _conceptReviewProjectId;
  final _sharedReviewKeys = <int, GlobalKey<SectionConceptOverviewState>>{};

  GlobalKey<SectionConceptOverviewState> _sharedReviewKey(int projectId) =>
      _sharedReviewKeys.putIfAbsent(
        projectId,
        () => GlobalKey<SectionConceptOverviewState>(),
      );

  void _openSharedReview(int projectId) async {
    if (widget.isAdviser || widget.isPitInstructor) {
      setState(() {
        _viewMode = DeliverablesViewMode.dossier;
        _showConceptReview = true;
        _conceptReviewProjectId = projectId;
      });
      return;
    }
    final review = _sharedReviewKey(projectId).currentState;
    if (review != null) {
      review.openReview();
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SectionConceptWorkspace(projectId: projectId),
      ),
    );
    if (mounted) {
      await ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
    }
  }

  @override
  void initState() {
    super.initState();
    _activeTeamId = widget.initialTeamId;
    final isEvaluator = widget.isAdviser || widget.isPitInstructor;
    _viewMode = isEvaluator
        ? DeliverablesViewMode.dossier
        : widget.initialViewMode ?? DeliverablesViewMode.matrix;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(capstoneDeliverablesProvider.notifier)
          .fetchDeliverables(
            workspace: widget.isAdviser
                ? 'adviser'
                : widget.isPitInstructor
                ? 'instructor'
                : 'operations',
            search: widget.initialTeamId != null ? '' : null,
            status: '',
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
    if (oldWidget.initialTeamId != widget.initialTeamId &&
        widget.initialTeamId != null) {
      _activeTeamId = widget.initialTeamId;
      _showConceptReview = false;
    }
    if (widget.initialViewMode != null &&
        widget.initialViewMode != oldWidget.initialViewMode) {
      _viewMode = widget.isAdviser || widget.isPitInstructor
          ? DeliverablesViewMode.dossier
          : widget.initialViewMode!;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openRoster() async {
    await openTeamRoster(
      context,
      year: widget.pitYearLevel,
      section: widget.pitSection,
      event: ref.read(capstoneDeliverablesProvider).selectedStage,
      instructor: true,
    );
    if (mounted) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
      ref.read(pitInstructorDefenseProvider.notifier).fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(capstoneDeliverablesProvider);
    final isWide = MediaQuery.of(context).size.width >= 900;
    final isEvaluator = widget.isAdviser || widget.isPitInstructor;
    final isPit =
        widget.initialScope == 'pit' ||
        widget.pitYearLevel != null ||
        widget.pitSection != null ||
        state.scope == 'pit';
    const showViewToggle = false;
    final sharedReviews = sharedReviewsForTeams(
      state.teams,
      stageLabel: state.selectedStage,
    );
    final hasConceptReview =
        sharedReviews.isNotEmpty ||
        state.teams.any((team) {
          final stage = DeliverablesTriageHelper.resolveActiveStage(team) ?? {};
          return (stage['concept_workflow'] as Map?)?['enabled'] == true ||
              TeamWorkflowStatus.items(stage).any(isConceptRequirement);
        });

    final String pageTitle;
    final String pageSubtitle;
    if (widget.isPitInstructor) {
      pageTitle = 'PIT Teams';
      pageSubtitle = widget.pitSection != null
          ? 'Section ${widget.pitSection} · Concepts & team deliverables'
          : (state.activeSemester?['display_name']?.toString() ??
                'Active Semester');
    } else if (widget.isAdviser) {
      pageTitle = 'Capstone Teams';
      pageSubtitle =
          state.activeSemester?['display_name']?.toString() ??
          'Active Semester';
    } else if (isPit) {
      pageTitle = 'PIT Cohort Deliverables';
      pageSubtitle = widget.pitYearLevel != null
          ? '${widget.pitYearLevel} Cohort · Deliverables Tracking & Reminders'
          : (state.activeSemester?['display_name']?.toString() ??
                'Active Semester');
    } else {
      pageTitle = 'Capstone Cohort Deliverables';
      pageSubtitle = 'All Teams · Deliverables Tracking & Reminders';
    }

    final filteredTeams = DeliverablesTriageHelper.reviewFirst(
      state.teams.where(
        (t) => DeliverablesTriageHelper.matchesFilter(t, _triageFilter),
      ),
    );

    final pendingCount = state.teams.fold<int>(
      0,
      (count, team) =>
          count + DeliverablesTriageHelper.pendingReviewCount(team),
    );
    final reviewTeamCount = state.teams
        .where(DeliverablesTriageHelper.hasPendingReview)
        .length;
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
                  child: ShadButton.outline(
                    height: 40,
                    enabled: !state.isSaving,
                    onPressed: state.isSaving
                        ? null
                        : () {
                            ref
                                .read(capstoneDeliverablesProvider.notifier)
                                .fetchDeliverables();
                            if (widget.isAdviser) {
                              ref.read(adviserDefenseProvider.notifier).fetch();
                              ref
                                  .read(adviserGradingProvider.notifier)
                                  .fetchAll();
                            } else if (widget.isPitInstructor) {
                              ref
                                  .read(pitInstructorDefenseProvider.notifier)
                                  .fetch();
                              ref
                                  .read(adviserGradingProvider.notifier)
                                  .fetchAll();
                            }
                          },
                    leading: const Icon(Icons.refresh_rounded, size: 16),
                    child: const Text('Refresh'),
                  ),
                ),
                if (widget.isPitInstructor) ...[
                  ShadButton.outline(
                    height: 40,
                    enabled: !state.isSaving,
                    onPressed: state.isSaving ? null : _openRoster,
                    leading: const Icon(Icons.groups_outlined, size: 16),
                    child: const Text('Team roster'),
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
            _notice(
              Icons.check_circle_outline,
              state.message!,
              AppColors.success,
            ),
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
          if (!state.isLoading && pendingCount > 0 && !isEvaluator) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(DefensysTokens.radiusMd),
                border: Border.all(color: const Color(0xFFBFDBFE)),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.clock,
                    size: 16,
                    color: Color(0xFF1D4ED8),
                  ),
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
                      _activeTeamId = int.tryParse(
                        DeliverablesTriageHelper.reviewFirst(
                          state.teams,
                        ).first['id'].toString(),
                      );
                      if (isEvaluator) {
                        _viewMode = DeliverablesViewMode.dossier;
                      }
                    }),
                    child: const Text(
                      'View submissions',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (isEvaluator) ...[
            Wrap(
              spacing: 10,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (hasConceptReview)
                  SizedBox(
                    width: 280,
                    child: ShadTabs<bool>(
                      value: _showConceptReview,
                      gap: 0,
                      onChanged: (concepts) => setState(() {
                        _viewMode = DeliverablesViewMode.dossier;
                        _showConceptReview = concepts;
                        _conceptReviewProjectId =
                            !concepts || sharedReviews.isEmpty
                            ? null
                            : sharedReviews.first['project_id'] as int;
                      }),
                      tabs: const [
                        ShadTab(value: true, child: Text('Concept review')),
                        ShadTab(value: false, child: Text('By team')),
                      ],
                    ),
                  )
                else
                  const Text(
                    'By team',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                if (pendingCount > 0)
                  TextButton(
                    onPressed: () => setState(() {
                      _triageFilter = TeamTriageFilter.needsReview;
                      _viewMode = DeliverablesViewMode.dossier;
                      _showConceptReview = false;
                    }),
                    child: Text('$pendingCount awaiting review'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (!isEvaluator &&
              !state.isLoading &&
              _viewMode == DeliverablesViewMode.dossier)
            for (final review in sharedReviewsForTeams(
              state.teams,
              stageLabel: state.selectedStage,
            ))
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: SectionConceptOverview(
                  key: _sharedReviewKey(review['project_id'] as int),
                  projectId: review['project_id'] as int,
                  section: '${review['section']}',
                  stageLabel: '${review['stage_label']}',
                  systems: (review['systems'] as List? ?? [])
                      .whereType<Map>()
                      .map((s) => Map<String, dynamic>.from(s))
                      .toList(),
                  summary: review,
                  onChanged: () => ref
                      .read(capstoneDeliverablesProvider.notifier)
                      .fetchDeliverables(),
                ),
              ),
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
                              workspace: widget.isAdviser
                                  ? 'adviser'
                                  : 'pit_instructor',
                              selectedStage: state.selectedStage,
                            ),
                            const SizedBox(height: 12),
                          ],
                          CohortSubmissionsMatrix(
                            teams: filteredTeams,
                            state: state,
                            isAdviser: isEvaluator,
                            sharedReviewKey: _sharedReviewKey,
                            onOpenSharedReview: _openSharedReview,
                            initialExpandedTeamId:
                                _activeTeamId ?? widget.initialTeamId,
                            onSelectTeam: (teamId) {
                              setState(() {
                                _activeTeamId = teamId;
                                if (isEvaluator) {
                                  _viewMode = DeliverablesViewMode.dossier;
                                }
                              });
                            },
                          ),
                        ],
                      )
                    : DeliverablesTablePane(
                        state: state,
                        isAdviser: widget.isAdviser,
                        isPitInstructor: widget.isPitInstructor,
                        key: isEvaluator
                            ? const ValueKey('faculty-workspace')
                            : ValueKey(_activeTeamId),
                        initialTeamId: _activeTeamId ?? widget.initialTeamId,
                        initialTab: widget.initialTab,
                        activeTriageFilter: _triageFilter,
                        onOpenSharedReview: _openSharedReview,
                        compactFaculty: isEvaluator,
                        conceptReview:
                            isEvaluator &&
                            hasConceptReview &&
                            _showConceptReview,
                        conceptReviewProjectId: _conceptReviewProjectId,
                        onSelectedTeamChanged: (teamId) =>
                            _activeTeamId = teamId,
                        onReturnToTeam: () =>
                            setState(() => _showConceptReview = false),
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
                onRefresh: () => ref
                    .read(capstoneDeliverablesProvider.notifier)
                    .fetchDeliverables(),
                child: content,
              ),
      ),
    );
  }
}
