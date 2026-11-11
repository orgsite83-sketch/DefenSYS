import 'package:defensys/navigation/workspace_http_context.dart';
import 'package:defensys/widgets/export/report_export_menu.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import '../../../../widgets/academic/capstone_history_filters.dart';
import '../../../../widgets/academic/capstone_workspace_navigation.dart';
import '../../../../widgets/shadcn/defensys_shadcn_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/defense_stages_provider.dart';
import '../../../../services/grade_center_provider.dart';
import 'grade_center_capstone_table.dart';
import 'grade_center_event_teams_screen.dart';
import 'grade_center_shared.dart';
import 'grade_center_team_detail_screen.dart';
import '../../../../theme/defensys_tokens.dart';
import '../../../../widgets/table/defensys_segmented_control.dart';
import '../widgets/defensys_admin_shell.dart';

class GradeCenterScreen extends ConsumerStatefulWidget {
  const GradeCenterScreen({super.key});

  @override
  ConsumerState<GradeCenterScreen> createState() => _GradeCenterScreenState();
}

class _GradeCenterScreenState extends ConsumerState<GradeCenterScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _searchFieldFocused = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  String? _eventGroupKey;
  String? _eventScope;
  String? _eventStageLabel;
  String? _eventTitle;

  int? _teamDetailGradeId;
  bool _teamDetailIsLocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(authProvider).user;
      final isAdmin = _isGradeCenterAdmin(user);
      ref
          .read(gradeCenterProvider.notifier)
          .fetchGrades(scope: _defaultScopeForUser(user));
      if (isAdmin) {
        _ensureDefenseStagesLoaded();
      }
    });
  }

  void _ensureDefenseStagesLoaded() {
    final stagesState = ref.read(defenseStagesProvider);
    if (stagesState.stages.isEmpty && !stagesState.isLoading) {
      ref.read(defenseStagesProvider.notifier).fetchStages();
    }
  }

  String _effectiveScope(GradeCenterState state) {
    if (state.scope == 'capstone' || state.scope == 'pit') return state.scope;
    return _defaultScopeForUser(ref.read(authProvider).user);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _syncSearchController(String search) {
    if (_searchFieldFocused) return;
    if (_searchController.text != search) {
      _searchController.text = search;
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      ref.read(gradeCenterProvider.notifier).fetchGrades(search: value);
    });
  }

  void _onSearchSubmitted(String value) {
    _searchDebounce?.cancel();
    ref.read(gradeCenterProvider.notifier).fetchGrades(search: value);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(gradeCenterProvider);

    ref.listen<GradeCenterState>(gradeCenterProvider, (previous, next) {
      _syncSearchController(next.search);
    });

    ref.listen<GradeCenterState>(gradeCenterProvider, (previous, next) {
      if (next.incompleteTeams.isEmpty) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        showIncompleteGradingTeamsDialog(context, teams: next.incompleteTeams);
        ref.read(gradeCenterProvider.notifier).clearIncompleteTeams();
      });
    });

    final onAdminGradeCenter =
        GoRouterState.of(context).uri.path == AdminRoutes.gradeCenter;

    if (!onAdminGradeCenter) {
      if (_teamDetailGradeId != null) {
        return GradeCenterTeamDetailScreen(
          key: ValueKey('grade-detail-$_teamDetailGradeId'),
          gradeId: _teamDetailGradeId!,
          isLocked: _teamDetailIsLocked,
          onBack: _closeTeamDetail,
        );
      }

      if (_eventGroupKey != null &&
          _eventScope != null &&
          _eventStageLabel != null &&
          _eventTitle != null) {
        return GradeCenterEventTeamsScreen(
          key: ValueKey('event-$_eventGroupKey'),
          groupKey: _eventGroupKey!,
          scope: _eventScope!,
          stageLabel: _eventStageLabel!,
          title: _eventTitle!,
          onBack: _closeEventTeams,
          onOpenTeamDetail: _openTeamDetail,
        );
      }
    }

    return _buildListView(state);
  }

  void _openEventTeams({
    required String groupKey,
    required String scope,
    required String stageLabel,
    required String title,
    GradeCenterState? phaseState,
  }) {
    final state = phaseState ?? ref.read<GradeCenterState>(gradeCenterProvider);
    final settings = groupSettingsForKey(state, groupKey);
    final phase = state.capstoneWorkspace;
    final contextParameters = <String, String>{
      if (state.activeSemester?['id'] != null)
        'semester_id': '${state.activeSemester!['id']}',
      if (scope == 'capstone' && phase.isNotEmpty) ...{
        'capstone_view': '${phase['view']}',
        'batch_id': '${phase['batch_id']}',
        'phase_semester_id': '${phase['phase_semester_id']}',
        if (settings['defense_stage_id'] != null)
          'defense_stage_id': '${settings['defense_stage_id']}',
      },
    };
    if (GoRouterState.of(context).uri.path.startsWith('/faculty/')) {
      context.push(
        FacultyRoutes.gradeEventTeams(
          groupKey,
          scope: scope,
          stageLabel: stageLabel,
          title: title,
          contextParameters: contextParameters,
        ),
      );
      return;
    }
    if (GoRouterState.of(context).uri.path.startsWith('/admin/')) {
      context.push(
        AdminRoutes.gradeEventTeams(
          groupKey,
          scope: scope,
          stageLabel: stageLabel,
          title: title,
          contextParameters: contextParameters,
        ),
      );
      return;
    }
    setState(() {
      _eventGroupKey = groupKey;
      _eventScope = scope;
      _eventStageLabel = stageLabel;
      _eventTitle = title;
      _teamDetailGradeId = null;
    });
  }

  void _closeEventTeams() {
    final scope = _eventScope;
    setState(() {
      _eventGroupKey = null;
      _eventScope = null;
      _eventStageLabel = null;
      _eventTitle = null;
      _teamDetailGradeId = null;
    });
    final gcState = ref.read(gradeCenterProvider);
    ref
        .read(gradeCenterProvider.notifier)
        .fetchGrades(
          scope: gcState.scope.isNotEmpty ? gcState.scope : (scope ?? ''),
        );
  }

  void _openTeamDetail(int gradeId, bool isLocked) {
    if (GoRouterState.of(context).uri.path.startsWith('/faculty/')) {
      context.push(
        '${FacultyRoutes.gradeDetail(gradeId)}?locked=${isLocked ? 1 : 0}',
      );
      return;
    }
    if (GoRouterState.of(context).uri.path.startsWith('/admin/')) {
      context.push(
        '${AdminRoutes.gradeDetail(gradeId)}?locked=${isLocked ? 1 : 0}',
      );
      return;
    }
    setState(() {
      _teamDetailGradeId = gradeId;
      _teamDetailIsLocked = isLocked;
    });
  }

  void _closeTeamDetail() {
    setState(() => _teamDetailGradeId = null);
    final scope = _eventScope;
    if (scope != null) {
      ref.read(gradeCenterProvider.notifier).fetchGrades(scope: scope);
    }
  }

  Widget _buildListView(GradeCenterState state) {
    final isAdmin = _isGradeCenterAdmin(ref.watch(authProvider).user);

    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.star_rounded,
            title: 'Evaluation & Grades',
            subtitle:
                'Monitor real-time grading from Panelists, Advisors, and Peer-to-Peer rubrics.',
            actions: const ReportExportMenu(reportId: 'semester-grades'),
          ),
          const SizedBox(height: 26),
          if (isAdmin && _effectiveScope(state) == 'capstone')
            CapstoneWorkspaceNavigation(
              data: state.capstoneWorkspace,
              enabled: !state.isLoading && !state.isSaving,
              onChanged: (view, batch, semester) {
                _searchDebounce?.cancel();
                setState(() {
                  _eventGroupKey = null;
                  _teamDetailGradeId = null;
                });
                ref
                    .read(gradeCenterProvider.notifier)
                    .selectCapstoneWorkspace(view, batch, semester);
              },
            )
          else
            AcademicHistoryDropdown(
              label: 'Academic period',
              value: state.historySemester,
              items: [
                const MapEntry('', 'Current Term'),
                ...state.historySemesters.map(
                  (t) => MapEntry('${t['id']}', '${t['label']}'),
                ),
              ],
              onChanged: (value) => ref
                  .read(gradeCenterProvider.notifier)
                  .fetchGrades(historySemester: value),
            ),
          const SizedBox(height: 16),
          if (_effectiveScope(state) == 'capstone' &&
              state.capstoneWorkspace.isNotEmpty) ...[
            Text(
              '${state.capstoneWorkspace['view'] == 'history' ? 'Latest recorded phase' : 'Current phase'} · ${state.activeSemester?['display_name'] ?? ''}',
              style: TextStyle(
                fontFamily: DefensysTokens.fontFamilyInter,
                color: DefensysTokens.textSecondaryOf(context),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 8),
          ],
          _buildStats(state),

          if (isAdmin) ...[
            const SizedBox(height: 22),
            _buildScopeTabs(state),
            const SizedBox(height: 16),
          ] else ...[
            const SizedBox(height: 22),
          ],

          _buildMainCard(state),
        ],
      ),
    );
  }

  Widget _buildScopeTabs(GradeCenterState state) {
    final currentScope = _effectiveScope(state);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DefensysSegmentedControl<String>(
        value: currentScope,
        enabled: !state.isSaving,
        items: const [
          DefensysSegmentItem(
            value: 'capstone',
            label: 'Capstone Stages',
            icon: Icons.rocket_launch_rounded,
          ),
          DefensysSegmentItem(
            value: 'pit',
            label: 'PIT Expos & Events',
            icon: Icons.lightbulb_rounded,
          ),
        ],
        onChanged: (scope) =>
            ref.read(gradeCenterProvider.notifier).fetchGrades(scope: scope),
      ),
    );
  }

  bool _filtersActive(GradeCenterState state) {
    return state.search.trim().isNotEmpty ||
        state.yearLevel.isNotEmpty ||
        state.status.isNotEmpty;
  }

  int _kpiTotal(GradeCenterState state) {
    return _count(state, 'filtered');
  }

  Widget _buildStats(GradeCenterState state) {
    final filtersActive = _filtersActive(state);
    final scope = _effectiveScope(state);
    final stats = scope == 'capstone'
        ? state.phaseStatistics
        : const <String, dynamic>{};
    final total = (stats['total_teams'] as num?)?.toInt() ?? _kpiTotal(state);
    final published =
        (stats['fully_graded_teams'] as num?)?.toInt() ??
        _count(state, 'published');
    final pending =
        (stats['awaiting_panelists'] as num?)?.toInt() ??
        _count(state, 'pending');
    final publishedPct = total == 0 ? 0.0 : published / total;
    final pendingPct = total == 0 ? 0.0 : pending / total;

    final String teamsTitle;
    if (filtersActive) {
      if (scope == 'capstone') {
        teamsTitle = 'Filtered Capstone teams';
      } else if (scope == 'pit') {
        teamsTitle = 'Filtered PIT teams';
      } else {
        teamsTitle = 'Filtered teams';
      }
    } else {
      if (scope == 'capstone') {
        teamsTitle = 'Total Capstone teams';
      } else if (scope == 'pit') {
        teamsTitle = 'Total PIT teams';
      } else {
        teamsTitle = 'Total teams';
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 650;
        Widget slot(Widget child) => narrow ? child : Expanded(child: child);
        return Flex(
          direction: narrow ? Axis.vertical : Axis.horizontal,
          crossAxisAlignment: narrow
              ? CrossAxisAlignment.stretch
              : CrossAxisAlignment.center,
          children: [
            slot(
              gradeCenterKpiStatCard(
                context: context,
                title: teamsTitle,
                value: total.toString(),
                icon: Icons.groups_rounded,
                accent: DefensysTokens.maroonTextOf(context),
                iconBg: DefensysTokens.maroonOf(
                  context,
                ).withValues(alpha: 0.08),
                progress: total == 0 ? 0 : 1,
              ),
            ),
            SizedBox(width: 14, height: narrow ? 12 : 0),
            slot(
              gradeCenterKpiStatCard(
                context: context,
                title: 'Fully graded (100%)',
                value: '$published (${(publishedPct * 100).round()}%)',
                icon: Icons.check_circle_outline_rounded,
                accent: const Color(0xFF10B981),
                iconBg: const Color(0xFFE7F6EC),
                progress: publishedPct,
              ),
            ),
            SizedBox(width: 14, height: narrow ? 12 : 0),
            slot(
              gradeCenterKpiStatCard(
                context: context,
                title: 'Awaiting panelists',
                value: pending.toString(),
                icon: Icons.schedule_rounded,
                accent: const Color(0xFFF59E0B),
                iconBg: const Color(0xFFFFFBEB),
                progress: pendingPct,
              ),
            ),
          ],
        );
      },
    );
  }

  bool _isGradeCenterAdmin(Map<String, dynamic>? user) {
    if (user == null) return false;
    if (isAdminWorkspace(user)) return true;
    return false;
  }

  /// PIT lead without admin/superuser — default Grade Center to PIT scope (matches defense scheduler).
  bool _isPitLeadOnly(Map<String, dynamic>? user) {
    if (user == null) return false;
    if (_isGradeCenterAdmin(user)) return false;
    return user['is_pit_lead'] == true;
  }

  String _defaultScopeForUser(Map<String, dynamic>? user) {
    if (_isGradeCenterAdmin(user)) return 'capstone';
    if (_isPitLeadOnly(user)) return 'pit';
    return 'capstone';
  }

  Widget _buildMainCard(
    GradeCenterState state, {
    String? title,
    String? subtitle,
    bool showFilters = true,
    int stageOrderOffset = 0,
  }) {
    final isAdmin = _isGradeCenterAdmin(ref.watch(authProvider).user);
    final scope = _effectiveScope(state);
    if (scope == 'capstone' && state.capstonePhases.isNotEmpty) {
      return _buildPhaseSequence(state);
    }
    final stagesState = ref.watch(defenseStagesProvider);
    final stages =
        state.capstoneWorkspace.isNotEmpty || state.capstoneStages.isNotEmpty
        ? state.capstoneStages
        : stagesState.activeStages;
    final stagesLoading = state.capstoneStages.isEmpty && stagesState.isLoading;

    final isPit = scope == 'pit';
    final activeStages = isPit ? state.pitEvents : stages;
    final activeLoading = isPit ? false : stagesLoading;

    return CapstoneStagesUnifiedCard(
      scope: scope,
      title: title,
      subtitle: subtitle,
      showFilters: showFilters,
      stageOrderOffset: stageOrderOffset,
      canManageStages:
          (isAdmin ||
          scope == 'pit' && _isPitLeadOnly(ref.read(authProvider).user)),
      state: state,
      stages: activeStages,
      stagesLoading: activeLoading,
      isAdmin:
          isAdmin &&
          state.capstoneWorkspace['read_only'] != true &&
          state.activeSemester?['is_active'] != false,
      searchController: _searchController,
      scopeFilter: _scopeFilter(state),
      yearLevelFilter: _yearLevelFilter(state),
      statusFilter: _statusFilter(state),
      onOpenStage: (row) {
        final rowScope = row.groupKey.split('|').first;
        _openEventTeams(
          groupKey: row.groupKey,
          scope: rowScope,
          stageLabel: row.label,
          title: row.title,
          phaseState: state,
        );
      },
      onOfficiallyCompleteChanged: (row, value) {
        final rowScope = row.groupKey.split('|').first;
        ref
            .read(gradeCenterProvider.notifier)
            .updateGroupSettings(
              scope: rowScope,
              stageLabel: row.label,
              isOfficiallyComplete: value,
              peerGradingEnabled: value ? false : null,
            );
      },
      onPeerGradingChanged: (row, value) {
        final rowScope = row.groupKey.split('|').first;
        ref
            .read(gradeCenterProvider.notifier)
            .updateGroupSettings(
              scope: rowScope,
              stageLabel: row.label,
              peerGradingEnabled: value,
            );
      },
      onSearchChanged: _onSearchChanged,
      onSearchSubmitted: _onSearchSubmitted,
      onSearchFocusChanged: (focused) => _searchFieldFocused = focused,
    );
  }

  Widget _buildPhaseSequence(GradeCenterState state) {
    var offset = 0;
    final sections = <Widget>[
      _sequenceFilters(state),
      const SizedBox(height: 16),
    ];
    for (final phase in state.capstonePhases) {
      final phaseState = state.forPhase(phase);
      if (offset > 0 || sections.length > 2) {
        sections.add(
          Padding(
            padding: const EdgeInsets.only(left: 32),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 1,
                height: 20,
                color: DefensysTokens.borderOf(context),
              ),
            ),
          ),
        );
      }
      sections.add(
        KeyedSubtree(
          key: ValueKey('grade-phase-${phase['semester_id']}'),
          child: _buildMainCard(
            phaseState,
            title: '${phase['phase_label']}',
            subtitle: phase['read_only'] == true
                ? 'Read-only record'
                : 'Current phase',
            showFilters: false,
            stageOrderOffset: offset,
          ),
        ),
      );
      offset +=
          (phase['stage_count'] as num?)?.toInt() ??
          phaseState.capstoneStages.length;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: sections,
    );
  }

  Widget _sequenceFilters(GradeCenterState state) {
    Widget field(String label, IconData icon, Widget child) =>
        gradeCenterFilterField(
          label: label,
          icon: icon,
          context: context,
          dropdown: gradeCenterFilterDropdownShell(
            context: context,
            child: child,
          ),
        );
    final controls = [
      field('Year level', Icons.school_outlined, _yearLevelFilter(state)),
      field('Status', Icons.flag_outlined, _statusFilter(state)),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Search',
            style: TextStyle(
              fontFamily: DefensysTokens.fontFamilyInter,
              fontSize: 12,
              color: DefensysTokens.textSecondaryOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Focus(
            onFocusChange: (focused) => _searchFieldFocused = focused,
            child: ShadInput(
              controller: _searchController,
              enabled: !state.isSaving,
              placeholder: const Text('Search teams...'),
              onChanged: _onSearchChanged,
              onSubmitted: _onSearchSubmitted,
            ),
          ),
        ],
      ),
    ];
    return DefensysShadcnScope(
      child: DefensysCard(
        padding: const EdgeInsets.all(16),
        child: LayoutBuilder(
          builder: (context, constraints) => constraints.maxWidth < 650
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final control in controls) ...[
                      control,
                      const SizedBox(height: 12),
                    ],
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < controls.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(flex: i == 2 ? 3 : 2, child: controls[i]),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _scopeFilter(GradeCenterState state) {
    const scopeItems = [
      DropdownMenuItem(value: 'capstone', child: Text('Capstone')),
      DropdownMenuItem(value: 'pit', child: Text('PIT')),
    ];
    final defaultScope = _defaultScopeForUser(ref.read(authProvider).user);
    final currentScope = _effectiveScope(state);

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        dropdownColor: _isDark ? DefensysTokens.mistSurface : Colors.white,
        value: scopeItems.any((item) => item.value == currentScope)
            ? currentScope
            : defaultScope,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        style: TextStyle(
          color: _isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark,
          fontFamily: DefensysUi.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        items: scopeItems,
        onChanged: state.isSaving
            ? null
            : (value) {
                final nextScope = value ?? 'capstone';
                ref
                    .read(gradeCenterProvider.notifier)
                    .fetchGrades(scope: nextScope);
                if (nextScope == 'capstone') {
                  _ensureDefenseStagesLoaded();
                }
              },
      ),
    );
  }

  Widget _yearLevelFilter(GradeCenterState state) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        dropdownColor: _isDark ? DefensysTokens.mistSurface : Colors.white,
        value: state.yearLevel,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        style: TextStyle(
          color: _isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark,
          fontFamily: DefensysUi.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('All levels')),
          ...state.yearLevels.map(
            (level) => DropdownMenuItem(value: level, child: Text(level)),
          ),
        ],
        onChanged: state.isSaving
            ? null
            : (value) {
                ref
                    .read(gradeCenterProvider.notifier)
                    .fetchGrades(yearLevel: value ?? '');
              },
      ),
    );
  }

  Widget _statusFilter(GradeCenterState state) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        dropdownColor: _isDark ? DefensysTokens.mistSurface : Colors.white,
        value: state.status,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        style: TextStyle(
          color: _isDark ? DefensysTokens.textPrimaryDark : DefensysUi.textDark,
          fontFamily: DefensysUi.fontFamily,
          fontSize: 12.5,
          fontWeight: FontWeight.w500,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('All statuses')),
          ...state.statuses.map(
            (status) => DropdownMenuItem(
              value: status,
              child: Text(statusLabel(status)),
            ),
          ),
        ],
        onChanged: state.isSaving
            ? null
            : (value) {
                ref
                    .read(gradeCenterProvider.notifier)
                    .fetchGrades(status: value ?? '');
              },
      ),
    );
  }

  int _count(GradeCenterState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
