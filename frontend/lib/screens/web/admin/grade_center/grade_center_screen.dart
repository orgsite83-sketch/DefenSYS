import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../navigation/admin_route_paths.dart';
import '../../../../services/auth_provider.dart';
import '../../../../services/defense_stages_provider.dart';
import '../../../../services/grade_center_provider.dart';
import '../admin_shell.dart';
import 'grade_center_capstone_table.dart';
import 'grade_center_event_teams_screen.dart';
import 'grade_center_shared.dart';
import 'grade_center_team_detail_screen.dart';
import '../../../../theme/defensys_tokens.dart';
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

    ref.listen<GradeCenterState>(gradeCenterProvider, (previous, next) {
      if (next.incompleteTeams.isEmpty) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        showIncompleteGradingTeamsDialog(
          context,
          teams: next.incompleteTeams,
        );
        ref.read(gradeCenterProvider.notifier).clearIncompleteTeams();
      });
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
            actions: null,
          ),
          const SizedBox(height: 26),
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

    final tabs = [
      {'key': 'capstone', 'label': '🚀 Capstone Stages'},
      {'key': 'pit', 'label': '💡 PIT Expos & Events'},
      {'key': 'all', 'label': '📊 All Scopes'},
    ];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _isDark ? DefensysTokens.mistInputFill : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isDark ? DefensysTokens.mistBorder : const Color(0xFFE5E7EB)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: tabs.map((tab) {
          final isSelected = currentScope == tab['key'] ||
              (currentScope.isEmpty && tab['key'] == 'capstone');
          return InkWell(
            onTap: state.isSaving
                ? null
                : () {
                    if (currentScope != tab['key']) {
                      ref
                          .read(gradeCenterProvider.notifier)
                          .fetchGrades(scope: tab['key']!);
                    }
                  },
            borderRadius: BorderRadius.circular(7),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected ? DefensysUi.primaryMaroon : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: DefensysUi.primaryMaroon.withValues(alpha: 0.2),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        )
                      ]
                    : null,
              ),
              child: Text(
                tab['label']!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : (_isDark ? DefensysTokens.textSecondaryDark : DefensysUi.steelGrey),
                ),
              ),
            ),
          );
        }).toList(),
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
    final total = _kpiTotal(state);
    final publishedPct = total == 0 ? 0.0 : _count(state, 'published') / total;
    final pendingPct = total == 0 ? 0.0 : _count(state, 'pending') / total;

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

    return Row(
      children: [
        Expanded(
          child: gradeCenterKpiStatCard(
            context: context,
            title: teamsTitle,
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
            context: context,
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
            context: context,
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

    final isPit = scope == 'pit';
    final activeStages = isPit ? state.pitEvents : stages;
    final activeLoading = isPit ? false : stagesLoading;

    return CapstoneStagesUnifiedCard(
      scope: scope,
      state: state,
      stages: activeStages,
      stagesLoading: activeLoading,
      isAdmin: isAdmin,
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
        );
      },
      onOfficiallyCompleteChanged: (row, value) {
        final rowScope = row.groupKey.split('|').first;
        ref.read(gradeCenterProvider.notifier).updateGroupSettings(
              scope: rowScope,
              stageLabel: row.label,
              isOfficiallyComplete: value,
              peerGradingEnabled: value ? false : null,
            );
      },
      onPeerGradingChanged: (row, value) {
        final rowScope = row.groupKey.split('|').first;
        ref.read(gradeCenterProvider.notifier).updateGroupSettings(
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


  int _percent(GradeCenterState state, String key) {
    final total = _kpiTotal(state);
    if (total == 0) {
      return 0;
    }
    return ((_count(state, key) / total) * 100).round();
  }

  int _count(GradeCenterState state, String key) {
    final value = state.counts[key];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
