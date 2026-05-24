import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../navigation/admin_route_paths.dart';
import '../../../services/auth_provider.dart';
import '../../../services/defense_stages_provider.dart';
import '../../../services/grade_center_provider.dart';
import 'admin_shell.dart';
import 'grade_center_capstone_table.dart';
import 'grade_center_event_teams_screen.dart';
import '../../../widgets/defensys_skeleton.dart';
import 'grade_center_shared.dart';
import 'grade_center_team_detail_screen.dart';
import 'widgets/defensys_admin_shell.dart';

class GradeCenterScreen extends ConsumerStatefulWidget {
  const GradeCenterScreen({super.key});

  @override
  ConsumerState<GradeCenterScreen> createState() => _GradeCenterScreenState();
}

class _GradeCenterScreenState extends ConsumerState<GradeCenterScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  bool _searchFieldFocused = false;

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
      final pitLeadOnly = _isPitLeadOnly(user);
      ref.read(gradeCenterProvider.notifier).fetchGrades(
            scope: isAdmin
                ? 'capstone'
                : (pitLeadOnly ? 'pit' : null),
          );
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
    if (state.scope.isNotEmpty) return state.scope;
    final user = ref.read(authProvider).user;
    if (_isPitLeadOnly(user)) return 'pit';
    return 'capstone';
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

    ref.listen(activeAdminSectionProvider, (previous, next) {
      if (previous == DefensysAdminSection.gradeCenter &&
          next != DefensysAdminSection.gradeCenter) {
        setState(() {
          _eventGroupKey = null;
          _eventScope = null;
          _eventStageLabel = null;
          _eventTitle = null;
          _teamDetailGradeId = null;
        });
      }
      if (next == DefensysAdminSection.gradeCenter &&
          previous != DefensysAdminSection.gradeCenter) {
        final user = ref.read(authProvider).user;
        final isAdmin = _isGradeCenterAdmin(user);
        final pitLeadOnly = _isPitLeadOnly(user);
        final currentScope = state.scope;
        ref.read(gradeCenterProvider.notifier).fetchGrades(
              scope: currentScope.isNotEmpty
                  ? currentScope
                  : (isAdmin
                      ? 'capstone'
                      : (pitLeadOnly ? 'pit' : null)),
            );
        if (isAdmin) {
          _ensureDefenseStagesLoaded();
        }
      }
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
  }) {
    if (GoRouterState.of(context).uri.path.startsWith('/admin/')) {
      context.push(
        AdminRoutes.gradeEventTeams(
          groupKey,
          scope: scope,
          stageLabel: stageLabel,
          title: title,
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
    ref.read(gradeCenterProvider.notifier).fetchGrades(
          scope: gcState.scope.isNotEmpty ? gcState.scope : (scope ?? ''),
        );
  }

  void _openTeamDetail(int gradeId, bool isLocked) {
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
    return SingleChildScrollView(
      padding: DefensysUi.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DefensysPageHeader(
            icon: Icons.star_rounded,
            title: 'Evaluation & Grade Center',
            subtitle:
                'Monitor real-time grading from Panelists, Advisors, and Peer-to-Peer rubrics.',
            actions: _primaryButton(
              icon: Icons.file_download_rounded,
              label: 'Export Grading Sheet',
              onTap: state.grades.isEmpty
                  ? null
                  : () => _showExportDialog(state),
            ),
          ),
          const SizedBox(height: 26),
          _buildStats(state),
          if (state.error != null) ...[
            const SizedBox(height: 14),
            _buildNotice(
              icon: Icons.error_outline_rounded,
              text: state.error!,
              color: const Color(0xFFDC2626),
            ),
          ],
          if (state.message != null) ...[
            const SizedBox(height: 14),
            _buildNotice(
              icon: Icons.check_circle_outline_rounded,
              text: state.message!,
              color: const Color(0xFF10B981),
            ),
          ],
          const SizedBox(height: 22),
          _buildMainCard(state),
        ],
      ),
    );
  }

  bool _filtersActive(GradeCenterState state) {
    return state.search.trim().isNotEmpty ||
        state.yearLevel.isNotEmpty ||
        state.status.isNotEmpty;
  }

  int _kpiTotal(GradeCenterState state) {
    if (_filtersActive(state)) {
      return _count(state, 'filtered');
    }
    return _count(state, 'all');
  }

  Widget _buildStats(GradeCenterState state) {
    final filtersActive = _filtersActive(state);
    final total = _kpiTotal(state);
    final publishedPct = total == 0 ? 0.0 : _count(state, 'published') / total;
    final pendingPct = total == 0 ? 0.0 : _count(state, 'pending') / total;

    return Row(
      children: [
        Expanded(
          child: gradeCenterKpiStatCard(
            title: filtersActive ? 'Filtered teams' : 'Total teams',
            value: total.toString(),
            icon: Icons.groups_rounded,
            accent: DefensysUi.techBlue,
            iconBg: const Color(0xFFEFF6FF),
            progress: total == 0 ? 0 : 1,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: gradeCenterKpiStatCard(
            title: 'Fully graded (100%)',
            value:
                '${_count(state, 'published')} (${_percent(state, 'published')}%)',
            icon: Icons.check_circle_outline_rounded,
            accent: const Color(0xFF10B981),
            iconBg: const Color(0xFFE7F6EC),
            progress: publishedPct,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: gradeCenterKpiStatCard(
            title: 'Awaiting panelists',
            value: _count(state, 'pending').toString(),
            icon: Icons.schedule_rounded,
            accent: const Color(0xFFF59E0B),
            iconBg: const Color(0xFFFFFBEB),
            progress: pendingPct,
          ),
        ),
      ],
    );
  }

  bool _isGradeCenterAdmin(Map<String, dynamic>? user) {
    if (user == null) return false;
    if (user['role']?.toString() == 'admin') return true;
    if (user['is_superuser'] == true) return true;
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

  Widget _buildMainCard(GradeCenterState state) {
    final isAdmin = _isGradeCenterAdmin(ref.watch(authProvider).user);
    final scope = _effectiveScope(state);
    final stagesState = ref.watch(defenseStagesProvider);
    final stages = state.capstoneStages.isNotEmpty
        ? state.capstoneStages
        : stagesState.activeStages;
    final stagesLoading =
        state.capstoneStages.isEmpty && stagesState.isLoading;

    if (scope == 'capstone') {
      return CapstoneStagesUnifiedCard(
        state: state,
        stages: stages,
        stagesLoading: stagesLoading,
        isAdmin: isAdmin,
        searchController: _searchController,
        scopeFilter: _scopeFilter(state),
        yearLevelFilter: _yearLevelFilter(state),
        statusFilter: _statusFilter(state),
        onOpenStage: (row) => _openEventTeams(
          groupKey: row.groupKey,
          scope: 'capstone',
          stageLabel: row.label,
          title: row.title,
        ),
        onOfficiallyCompleteChanged: (row, value) {
          ref.read(gradeCenterProvider.notifier).updateGroupSettings(
                scope: 'capstone',
                stageLabel: row.label,
                isOfficiallyComplete: value,
                peerGradingEnabled: value ? false : null,
              );
        },
        onSearchChanged: _onSearchChanged,
        onSearchSubmitted: _onSearchSubmitted,
        onSearchFocusChanged: (focused) => _searchFieldFocused = focused,
      );
    }

    final title = scope == 'pit' ? 'PIT events' : 'Grade groups';
    final subtitle = scope == 'pit'
        ? 'Manage panel and peer grading by PIT event.'
        : 'Capstone and PIT grade groups for the active term.';

    return GradeCenterGroupedUnifiedCard(
      title: title,
      subtitle: subtitle,
      state: state,
      isAdmin: isAdmin,
      searchController: _searchController,
      scopeFilter: _scopeFilter(state),
      yearLevelFilter: _yearLevelFilter(state),
      statusFilter: _statusFilter(state),
      listContent: _buildGroupedListContent(state),
      onSearchChanged: _onSearchChanged,
      onSearchSubmitted: _onSearchSubmitted,
      onSearchFocusChanged: (focused) => _searchFieldFocused = focused,
    );
  }

  Widget _buildGroupedListContent(GradeCenterState state) {
    if (state.isLoading && state.grades.isEmpty) {
      return DefensysSkeleton.list(count: 5, rowHeight: 56);
    }

    final groups = groupGradesFromState(state);
    if (groups.isEmpty) {
      return _gradeEmptyTable();
    }

    return _gradeGroupedList(state);
  }

  Widget _scopeFilter(GradeCenterState state) {
    const scopeItems = [
      DropdownMenuItem(value: 'capstone', child: Text('Capstone')),
      DropdownMenuItem(value: 'pit', child: Text('PIT')),
      DropdownMenuItem(value: 'all', child: Text('All scopes')),
    ];
    final defaultScope = _defaultScopeForUser(ref.read(authProvider).user);
    final currentScope = state.scope.isEmpty ? defaultScope : state.scope;

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: scopeItems.any((item) => item.value == currentScope)
            ? currentScope
            : defaultScope,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        style: const TextStyle(
          color: DefensysUi.textDark,
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
        value: state.yearLevel,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        style: const TextStyle(
          color: DefensysUi.textDark,
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
        value: state.status,
        isExpanded: true,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        style: const TextStyle(
          color: DefensysUi.textDark,
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

  Widget _gradeGroupedList(GradeCenterState state) {
    final groups = groupGradesFromState(state);
    return Column(
      children: groups.entries
          .map(
            (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _eventGroupCard(state, entry.key, entry.value),
            ),
          )
          .toList(),
    );
  }

  Widget _eventGroupCard(
    GradeCenterState state,
    String groupKey,
    List<Map<String, dynamic>> grades,
  ) {
    final settings = groupSettingsForKey(state, groupKey);
    final scope = settings['scope']?.toString() ?? groupKey.split('|').first;
    final stageLabel = settings['stage_label']?.toString() ??
        (groupKey.contains('|') ? groupKey.split('|').sublist(1).join('|') : '');
    final isComplete = settings['is_officially_complete'] == true;
    final peerOpen = settings['peer_grading_enabled'] == true;
    final title = gradeGroupTitle(groupKey);

    final accent = gradeScopeAccentColor(scope);

    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accent),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    onTap: () => _openEventTeams(
                      groupKey: groupKey,
                      scope: scope,
                      stageLabel: stageLabel,
                      title: title,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: DefensysUi.textDark,
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          gradeTeamCountBadge(grades.length),
                          const SizedBox(width: 8),
                          const Icon(
                            Icons.chevron_right_rounded,
                            color: Color(0xFF98A2B3),
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Color(0xFFE5E7EB)),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    child: gradeGroupStageControlsSection(
                      state: state,
                      scope: scope,
                      isOfficiallyComplete: isComplete,
                      peerGradingEnabled: peerOpen,
                      showCapstonePeerTermBadge: scope == 'capstone',
                      onOfficiallyCompleteChanged: (value) {
                        ref.read(gradeCenterProvider.notifier).updateGroupSettings(
                              scope: scope,
                              stageLabel: stageLabel,
                              isOfficiallyComplete: value,
                              peerGradingEnabled: value ? false : null,
                            );
                      },
                      onPeerGradingChanged: (value) {
                        ref.read(gradeCenterProvider.notifier).updateGroupSettings(
                              scope: scope,
                              stageLabel: stageLabel,
                              peerGradingEnabled: value,
                            );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradeEmptyTable() {
    return Container(
      height: 78,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: const Text(
        'No teams found.',
        style: TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
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
        icon: Icon(icon, size: 16),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: DefensysUi.primaryMaroon,
          foregroundColor: DefensysUi.accentGold,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          padding: const EdgeInsets.symmetric(horizontal: 22),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }

  int _percent(GradeCenterState state, String key) {
    final total = _kpiTotal(state);
    if (total == 0) {
      return 0;
    }
    return ((_count(state, key) / total) * 100).round();
  }

  void _showExportDialog(GradeCenterState state) {
    final csv = _csvFor(state.grades);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Export Grading Sheet'),
        content: SizedBox(
          width: 720,
          height: 420,
          child: SingleChildScrollView(child: SelectableText(csv)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _csvFor(List<Map<String, dynamic>> grades) {
    final rows = [
      'Team,Scope,Year Level,Event/Stage,Panel,Adviser,Peer,Final,Status',
      ...grades.map((grade) {
        return [
          grade['team_name'],
          grade['scope'],
          grade['year_level'],
          grade['stage_label'],
          grade['panel_score'],
          grade['adviser_score'],
          grade['peer_score'],
          grade['final_grade'],
          grade['status'],
        ].map(_csvCell).join(',');
      }),
    ];
    return rows.join('\n');
  }

  String _csvCell(dynamic value) {
    final text = (value ?? '').toString().replaceAll('"', '""');
    return '"$text"';
  }

  Widget _buildNotice({
    required IconData icon,
    required String text,
    required Color color,
  }) {
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

  int _count(GradeCenterState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
