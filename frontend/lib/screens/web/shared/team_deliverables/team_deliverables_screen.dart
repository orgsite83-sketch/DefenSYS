import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:defensys/services/adviser_grading_provider.dart';
import 'package:defensys/services/capstone_deliverables_provider.dart';
import 'package:defensys/services/weekly_progress_provider.dart';
import 'package:defensys/services/defense/adviser_defense_provider.dart';
import 'package:defensys/theme/app_theme.dart';
import 'package:defensys/screens/web/admin/widgets/defensys_admin_shell.dart';
import 'components/deliverables_filter_bar.dart';
import 'components/deliverables_table.dart';
import 'components/cohort_submissions_matrix.dart';
import 'deliverables_view_types.dart';

Widget _notice(IconData icon, String message, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withValues(alpha: 0.25)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color, size: 18),
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
  final String? pitYearLevel;
  final String? pitSection;
  final int? initialTeamId;
  final int? initialTab;
  final String? initialStage;

  const TeamDeliverablesScreen({
    super.key,
    this.initialScope,
    this.isAdviser = false,
    this.pitYearLevel,
    this.pitSection,
    this.initialTeamId,
    this.initialStage,
    this.initialTab,
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
    final isInstructor = widget.initialScope == 'pit' ||
        widget.pitYearLevel != null ||
        widget.pitSection != null;
    _viewMode = isInstructor && widget.initialTeamId == null ? DeliverablesViewMode.matrix : DeliverablesViewMode.dossier;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(
        scope: widget.initialScope,
        selectedStage: widget.initialStage,
        yearLevel: widget.pitYearLevel,
        section: widget.pitSection,
      );
      ref.read(adviserGradingProvider.notifier).fetchAll();
      ref.read(weeklyProgressProvider.notifier).fetchReports();
      if (widget.isAdviser) {
        ref.read(adviserDefenseProvider.notifier).fetch();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(capstoneDeliverablesProvider);
    final isWide = MediaQuery.of(context).size.width >= 900;
    final isInstructor = widget.initialScope == 'pit' ||
        widget.pitYearLevel != null ||
        widget.pitSection != null ||
        state.scope == 'pit';
    final showViewToggle = isInstructor || state.teams.length >= 3;

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
            icon: Icons.folder_open_outlined,
            title: state.scope == 'pit' ? 'PIT Teams' : 'Capstone Teams',
            subtitle: state.activeSemester?['display_name']?.toString() ?? 'Active Semester',
            actions: IconButton(
              tooltip: 'Refresh',
              onPressed: state.isSaving
                  ? null
                  : () {
                      ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables();
                      if (widget.isAdviser) {
                        ref.read(adviserDefenseProvider.notifier).fetch();
                      }
                    },
              icon: const Icon(Icons.refresh),
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
            isAdviser: widget.isAdviser,
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
            _notice(Icons.fact_check_outlined,
                '$pendingCount ${pendingCount == 1 ? 'submission' : 'submissions'} awaiting review across '
                '$reviewTeamCount ${reviewTeamCount == 1 ? 'team' : 'teams'}. Teams needing review appear first.',
                const Color(0xFF1D4ED8)),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() {
                  _triageFilter = TeamTriageFilter.needsReview;
                  _activeTeamId = int.tryParse(DeliverablesTriageHelper.reviewFirst(state.teams).first['id'].toString());
                  _viewMode = DeliverablesViewMode.dossier;
                }),
                child: const Text('View submissions'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          state.isLoading
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(),
                  ),
                )
              : (_viewMode == DeliverablesViewMode.matrix
                  ? CohortSubmissionsMatrix(
                      teams: filteredTeams,
                      state: state,
                      isAdviser: widget.isAdviser,
                      onSelectTeam: (teamId) {
                        setState(() {
                          _activeTeamId = teamId;
                          _viewMode = DeliverablesViewMode.dossier;
                        });
                      },
                    )
                  : DeliverablesTablePane(
                      state: state,
                      isAdviser: widget.isAdviser,
                      key: ValueKey(_activeTeamId),
                      initialTeamId: _activeTeamId ?? widget.initialTeamId,
                      initialTab: widget.initialTab,
                      activeTriageFilter: _triageFilter,
                    )),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: null,
      body: isWide
          ? content
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(capstoneDeliverablesProvider.notifier).fetchDeliverables(),
              child: content,
            ),
    );
  }
}

